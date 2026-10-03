import CryptoKit
import Foundation

/// Drive v2 is intentional: it exposes ETags and conditional media upload,
/// including conflict detection when a resumable upload commits.
actor GoogleDriveBackend: RemoteWorkspaceBackend {
    let rootID: String
    let client: CloudHTTPClient
    private static let fields = "id,title,mimeType,etag,modifiedDate,fileSize,md5Checksum,parents(id),properties,labels(trashed)"

    init(rootID: String, client: CloudHTTPClient) { self.rootID = rootID; self.client = client }

    func scan(cursor: String?) async throws -> RemoteScan {
        _ = try await root()
        if let cursor, UInt64(cursor) != nil {
            do {
                if let unchangedCursor = try await unchangedSince(cursor) {
                    return RemoteScan(files: [], cursor: unchangedCursor, isFullSnapshot: false)
                }
            } catch StorageError.rootUnavailable {
                _ = try await root() // Expired change cursor, not a deleted root.
            } catch StorageError.http(400) {
                // A rejected/expired token requires a fresh, complete snapshot.
            }
        }
        // Capture the cursor before enumeration so changes during traversal are
        // revisited next time. Persisting a post-scan cursor could miss edits.
        let startCursor = try await currentCursor()
        var queue = [(rootID, "")], files: [RemoteFile] = [], seenIDs = Set<String>(), seenPaths = Set<String>()
        while !queue.isEmpty {
            let (parentID, parentPath) = queue.removeFirst()
            for item in try await children(parentID) {
                let path = try StorageHTTP.child(parentPath, StorageHTTP.string(item, "title"))
                let file = try decode(item, path: path)
                guard seenIDs.insert(file.id).inserted else { throw StorageError.invalidResponse }
                guard seenPaths.insert(path).inserted else { throw StorageError.conflict(path) }
                files.append(file)
                if file.isDirectory { queue.append((file.id, path)) }
                guard files.count <= StorageHTTP.maximumEntries else { throw StorageError.tooLarge }
            }
        }
        return RemoteScan(files: files, cursor: startCursor)
    }

    private func currentCursor() async throws -> String {
        let json = try await client.json(StorageHTTP.url("https://www.googleapis.com", path: "/drive/v2/about",
                                                         query: [.init(name: "fields", value: "largestChangeId")]))
        return try Self.nextChangeID(json["largestChangeId"])
    }

    /// The account-wide feed is used only as an invalidation signal. Request no
    /// names or contents outside the workspace. Any change triggers complete
    /// subtree enumeration, which correctly rebuilds paths after external moves.
    private func unchangedSince(_ cursor: String) async throws -> String? {
        var page: String?, seen = Set<String>()
        repeat {
            var query: [URLQueryItem] = [.init(name: "startChangeId", value: cursor), .init(name: "maxResults", value: "1000"),
                                         .init(name: "includeDeleted", value: "true"),
                                         .init(name: "fields", value: "items(id,fileId,deleted),largestChangeId,nextPageToken")]
            if let page { query.append(.init(name: "pageToken", value: page)) }
            let json = try await client.json(StorageHTTP.url("https://www.googleapis.com", path: "/drive/v2/changes", query: query))
            if let changes = json["items"] as? [[String: Any]], !changes.isEmpty { return nil }
            page = json["nextPageToken"] as? String
            if let page {
                guard seen.insert(page).inserted, seen.count < 1000 else { throw StorageError.invalidResponse }
            } else { return try Self.nextChangeID(json["largestChangeId"]) }
        } while page != nil
        throw StorageError.invalidResponse
    }

    private static func nextChangeID(_ value: Any?) throws -> String {
        let string = (value as? String) ?? (value as? NSNumber)?.stringValue
        guard let string, let id = UInt64(string), id < UInt64.max else { throw StorageError.invalidResponse }
        return String(id + 1)
    }

    func download(_ file: RemoteFile, maxBytes: Int) async throws -> RemoteDownload {
        _ = try await root()
        for _ in 0..<3 {
            let before = try await metadata(file.id)
            let path = try await relativePath(before)
            let current = try decode(before, path: path)
            guard !current.isDirectory else { throw StorageError.invalidResponse }
            if let size = current.size, size > maxBytes { throw StorageError.tooLarge }
            var request = URLRequest(url: try Self.fileURL(file.id, query: [.init(name: "alt", value: "media")]))
            request.setValue(current.revision, forHTTPHeaderField: "If-Match")
            var response = try await client.send(request, maxBytes: maxBytes)
            if response.status == 412 { continue }
            if (300..<400).contains(response.status), let location = response.headers["location"],
               let url = URL(string: location),
               (url.host?.hasSuffix(".googleusercontent.com") == true || url.host == "googleusercontent.com") {
                try StorageHTTP.requireHTTPS(url)
                response = try await client.transport.send(URLRequest(url: url), maxBytes: maxBytes)
            }
            _ = try response.checked(path: path)
            let after = try await metadata(file.id)
            guard before["etag"] as? String == after["etag"] as? String else { continue }
            if let expected = before["md5Checksum"] as? String,
               expected.lowercased() != Self.md5(response.data) { continue }
            return RemoteDownload(file: current, data: response.data)
        }
        throw StorageError.conflict(file.path)
    }

    func upload(path: String, data: Data, existing: RemoteFile?, operationID: UUID) async throws -> RemoteFile {
        try StorageError.validate(path: path)
        _ = try await root()
        let operation = operationID.uuidString.lowercased()
        let checksum = Self.md5(data)
        var payload: [String: Any] = ["properties": [["key": "orgendaOperation", "value": operation, "visibility": "PRIVATE"]]]
        var etag: String?, fileID: String?
        if let existing {
            let current = try await metadata(existing.id)
            let actualPath = try await relativePath(current)
            guard actualPath == path else { throw StorageError.conflict(path) }
            if Self.operation(current) == operation, current["md5Checksum"] as? String == checksum {
                return try decode(current, path: path) // Successful upload whose response was lost.
            }
            guard let revision = StorageHTTP.strongETag(existing.revision), current["etag"] as? String == revision,
                  !existing.isDirectory else { throw StorageError.conflict(path) }
            etag = revision; fileID = existing.id
        } else {
            let parent = try await directoryID((path as NSString).deletingLastPathComponent)
            let siblings = try await children(parent)
            let matching = siblings.filter { $0["title"] as? String == (path as NSString).lastPathComponent }
            if matching.count == 1, Self.operation(matching[0]) == operation,
               matching[0]["md5Checksum"] as? String == checksum { return try decode(matching[0], path: path) }
            guard matching.isEmpty else { throw StorageError.conflict(path) }
            payload["title"] = (path as NSString).lastPathComponent
            payload["mimeType"] = "application/octet-stream"
            payload["parents"] = [["id": parent]]
            let generated = try await client.json(Self.fileURL("generateIds", query: [.init(name: "maxResults", value: "1")]))
            guard let ids = generated["ids"] as? [String], let id = ids.first else { throw StorageError.invalidResponse }
            payload["id"] = id
        }
        let json: [String: Any]
        if data.count <= 5 * 1024 * 1024 {
            json = try await multipart(data: data, metadata: payload, fileID: fileID, etag: etag, path: path)
        } else {
            json = try await resumable(data: data, metadata: payload, fileID: fileID, etag: etag, path: path)
        }
        let result = try decode(json, path: path)
        guard json["md5Checksum"] as? String == checksum else { throw StorageError.conflict(path) }
        return result
    }

    private func multipart(data: Data, metadata: [String: Any], fileID: String?, etag: String?, path: String) async throws -> [String: Any] {
        let boundary = "orgenda-" + UUID().uuidString
        var body = Data("--\(boundary)\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n".utf8)
        body.append(try JSONSerialization.data(withJSONObject: metadata, options: [.sortedKeys]))
        body.append(Data("\r\n--\(boundary)\r\nContent-Type: application/octet-stream\r\n\r\n".utf8))
        body.append(data); body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        var request = URLRequest(url: try Self.uploadURL(fileID, type: "multipart"))
        request.httpMethod = fileID == nil ? "POST" : "PUT"; request.httpBody = body
        request.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if let etag { request.setValue(etag, forHTTPHeaderField: "If-Match") }
        return try await client.send(request).checked(path: path).json()
    }

    private func resumable(data: Data, metadata: [String: Any], fileID: String?, etag: String?, path: String) async throws -> [String: Any] {
        var request = URLRequest(url: try Self.uploadURL(fileID, type: "resumable"))
        request.httpMethod = fileID == nil ? "POST" : "PUT"; request.httpBody = try JSONSerialization.data(withJSONObject: metadata, options: [.sortedKeys])
        request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue("application/octet-stream", forHTTPHeaderField: "X-Upload-Content-Type")
        request.setValue(String(data.count), forHTTPHeaderField: "X-Upload-Content-Length")
        if let etag { request.setValue(etag, forHTTPHeaderField: "If-Match") }
        let response = try await client.send(request).checked(path: path)
        guard let location = response.headers["location"], let url = URL(string: location),
              url.host == "www.googleapis.com", url.scheme == "https" else { throw StorageError.invalidResponse }
        var offset = 0
        let chunkSize = 8 * 256 * 1024
        while offset < data.count {
            let end = min(offset + chunkSize, data.count)
            var upload = URLRequest(url: url)
            upload.httpMethod = "PUT"; upload.httpBody = data.subdata(in: offset..<end)
            upload.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            upload.setValue("bytes \(offset)-\(end - 1)/\(data.count)", forHTTPHeaderField: "Content-Range")
            let result = try await client.send(upload)
            if result.status == 308 {
                guard end < data.count, result.headers["range"] == "bytes=0-\(end - 1)" else { throw StorageError.invalidResponse }
            } else {
                _ = try result.checked(path: path) // Includes 412 at final commit.
                guard end == data.count else { throw StorageError.invalidResponse }
                return try result.json()
            }
            offset = end
        }
        throw StorageError.invalidResponse
    }

    func createDirectory(path: String) async throws -> RemoteFile {
        try StorageError.validate(path: path)
        let parent = try await directoryID((path as NSString).deletingLastPathComponent)
        let matches = try await children(parent).filter { $0["title"] as? String == (path as NSString).lastPathComponent }
        guard matches.isEmpty else { throw StorageError.conflict(path) }
        let json = try await client.json(Self.fileURL(), method: "POST",
                                         body: ["title": (path as NSString).lastPathComponent, "mimeType": "application/vnd.google-apps.folder",
                                                "parents": [["id": parent]]], path: path)
        return try decode(json, path: path)
    }

    func move(_ file: RemoteFile, to path: String) async throws -> RemoteFile {
        try StorageError.validate(path: path)
        guard path != file.path, !path.hasPrefix(file.path + "/") else { throw StorageError.unsafePath(path) }
        let current = try await metadata(file.id)
        guard try await relativePath(current) == file.path,
              let revision = StorageHTTP.strongETag(file.revision), current["etag"] as? String == revision else {
            throw StorageError.conflict(file.path)
        }
        let parent = try await directoryID((path as NSString).deletingLastPathComponent)
        guard try await children(parent).allSatisfy({ $0["title"] as? String != (path as NSString).lastPathComponent }) else {
            throw StorageError.conflict(path)
        }
        let oldParents = (current["parents"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
        let query = [URLQueryItem(name: "addParents", value: parent), .init(name: "removeParents", value: oldParents.joined(separator: ","))]
        let json = try await client.json(Self.fileURL(file.id, query: query), method: "PATCH",
                                         body: ["title": (path as NSString).lastPathComponent], headers: ["If-Match": revision], path: path)
        return try decode(json, path: path)
    }

    private func root() async throws -> [String: Any] {
        let json = try await metadata(rootID)
        guard json["id"] as? String == rootID, json["mimeType"] as? String == "application/vnd.google-apps.folder",
              (json["labels"] as? [String: Any])?["trashed"] as? Bool != true else { throw StorageError.rootUnavailable }
        return json
    }
    private func metadata(_ id: String) async throws -> [String: Any] {
        try await client.json(Self.fileURL(id, query: [.init(name: "fields", value: Self.fields)]))
    }
    private func children(_ parent: String) async throws -> [[String: Any]] {
        var result: [[String: Any]] = [], token: String?, seen = Set<String>()
        repeat {
            var query: [URLQueryItem] = [.init(name: "q", value: "'\(Self.escapeQuery(parent))' in parents and trashed = false"),
                                         .init(name: "maxResults", value: "1000"),
                                         .init(name: "fields", value: "items(\(Self.fields)),nextPageToken")]
            if let token { query.append(.init(name: "pageToken", value: token)) }
            let json = try await client.json(Self.fileURL(query: query))
            guard json["items"] == nil || json["items"] is [[String: Any]] else { throw StorageError.invalidResponse }
            let items = json["items"] as? [[String: Any]] ?? []
            result += items
            guard result.count <= StorageHTTP.maximumEntries else { throw StorageError.tooLarge }
            token = json["nextPageToken"] as? String
            if let token, !seen.insert(token).inserted { throw StorageError.invalidResponse }
        } while token != nil
        return result
    }
    private func directoryID(_ path: String) async throws -> String {
        _ = try await root()
        if path.isEmpty { return rootID }
        try StorageError.validate(path: path)
        var id = rootID
        for component in path.split(separator: "/") {
            let matches = try await children(id).filter {
                $0["title"] as? String == String(component) && $0["mimeType"] as? String == "application/vnd.google-apps.folder"
            }
            guard matches.count == 1 else { throw StorageError.rootUnavailable }
            id = try StorageHTTP.string(matches[0], "id")
        }
        return id
    }
    private func relativePath(_ json: [String: Any]) async throws -> String {
        var item = json, names: [String] = [], visited = Set<String>()
        while try StorageHTTP.string(item, "id") != rootID {
            let id = try StorageHTTP.string(item, "id")
            guard visited.insert(id).inserted, visited.count <= 256,
                  let parents = item["parents"] as? [[String: Any]], parents.count == 1,
                  let parent = parents[0]["id"] as? String else { throw StorageError.rootUnavailable }
            names.append(try StorageHTTP.string(item, "title"))
            if parent == rootID { break }
            item = try await metadata(parent)
        }
        let path = names.reversed().joined(separator: "/")
        try StorageError.validate(path: path)
        return path
    }
    private func decode(_ json: [String: Any], path: String) throws -> RemoteFile {
        try StorageError.validate(path: path)
        let mime = try StorageHTTP.string(json, "mimeType"), directory = mime == "application/vnd.google-apps.folder"
        guard directory || !mime.hasPrefix("application/vnd.google-apps.") else {
            throw StorageError.unsupported(String(localized: "Google Docs and shortcuts cannot be used as ordinary workspace files. Move them outside the Orgenda folder."))
        }
        guard let etag = StorageHTTP.strongETag(json["etag"] as? String) else { throw StorageError.invalidResponse }
        return RemoteFile(id: try StorageHTTP.string(json, "id"), path: path, isDirectory: directory, revision: etag,
                          modifiedAt: StorageHTTP.date(json["modifiedDate"]), size: StorageHTTP.size(json["fileSize"]))
    }
    static func fileURL(_ id: String? = nil, query: [URLQueryItem] = []) throws -> URL {
        try StorageHTTP.url("https://www.googleapis.com", path: "/drive/v2/files" + (id.map { "/" + $0 } ?? ""), query: query)
    }
    private static func uploadURL(_ id: String?, type: String) throws -> URL {
        try StorageHTTP.url("https://www.googleapis.com", path: "/upload/drive/v2/files" + (id.map { "/" + $0 } ?? ""),
                             query: [.init(name: "uploadType", value: type)])
    }
    static func escapeQuery(_ value: String) -> String { value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'") }
    static func md5(_ data: Data) -> String { Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private static func operation(_ json: [String: Any]) -> String? {
        (json["properties"] as? [[String: Any]])?.first { $0["key"] as? String == "orgendaOperation" && $0["visibility"] as? String == "PRIVATE" }?["value"] as? String
    }
}
