import Foundation

actor OneDriveBackend: RemoteWorkspaceBackend {
    let driveID: String
    let rootID: String
    let client: CloudHTTPClient
    private var items: [String: [String: Any]] = [:]
    private var deltaCursor: String?

    init(driveID: String, rootID: String, client: CloudHTTPClient) {
        self.driveID = driveID; self.rootID = rootID; self.client = client
    }

    func scan(cursor: String?) async throws -> RemoteScan {
        _ = try await root()
        do {
            let incremental = cursor != nil && cursor == deltaCursor && !items.isEmpty
            let start = incremental ? URL(string: cursor!)! : try itemURL(rootID, suffix: "/delta")
            var next: URL? = start, seen = Set<String>(), candidate = incremental ? items : [:]
            var finalCursor: String?
            while let url = next {
                guard seen.insert(url.absoluteString).inserted else { throw StorageError.invalidResponse }
                let json = try await client.json(url)
                guard let values = json["value"] as? [[String: Any]] else { throw StorageError.invalidResponse }
                for item in values {
                    let id = try StorageHTTP.string(item, "id")
                    if item["deleted"] != nil { candidate.removeValue(forKey: id) }
                    else { candidate[id] = item }
                }
                guard candidate.count <= StorageHTTP.maximumEntries else { throw StorageError.tooLarge }
                next = try nextLink(json)
                if next == nil { finalCursor = json["@odata.deltaLink"] as? String }
            }
            guard let finalCursor, let cursorURL = URL(string: finalCursor),
                  cursorURL.scheme == "https", cursorURL.host == "graph.microsoft.com" else { throw StorageError.invalidResponse }
            let files = try buildFiles(candidate, allowOutside: incremental)
            items = candidate; deltaCursor = finalCursor
            // Reconstruct all paths after a folder move, returning one complete
            // authoritative snapshot even when the network query used delta.
            return RemoteScan(files: files, cursor: finalCursor)
        } catch StorageError.http(let status) where [400, 403, 405, 501].contains(status) {
            return try await enumerateChildren()
        } catch StorageError.rootUnavailable {
            // An expired delta token must not turn into remote deletions.
            _ = try await root()
            return try await enumerateChildren()
        }
    }

    private func enumerateChildren() async throws -> RemoteScan {
        var queue = [(rootID, "")], result: [RemoteFile] = [], seenIDs = Set<String>()
        while !queue.isEmpty {
            let (id, parent) = queue.removeFirst()
            var next: URL? = try itemURL(id, suffix: "/children"), seenPages = Set<String>()
            while let url = next {
                guard seenPages.insert(url.absoluteString).inserted else { throw StorageError.invalidResponse }
                let json = try await client.json(url)
                guard let children = json["value"] as? [[String: Any]] else { throw StorageError.invalidResponse }
                for child in children {
                    let path = try StorageHTTP.child(parent, StorageHTTP.string(child, "name"))
                    let file = try decode(child, path: path)
                    guard seenIDs.insert(file.id).inserted else { throw StorageError.invalidResponse }
                    result.append(file)
                    if file.isDirectory { queue.append((file.id, file.path)) }
                    guard result.count <= StorageHTTP.maximumEntries else { throw StorageError.tooLarge }
                }
                next = try nextLink(json)
            }
        }
        deltaCursor = nil; items = [:]
        return RemoteScan(files: result)
    }

    func download(_ file: RemoteFile, maxBytes: Int) async throws -> RemoteDownload {
        _ = try await root()
        for _ in 0..<3 {
            let before = try await client.json(itemURL(file.id))
            let currentPath = try await path(for: before)
            let metadata = try decode(before, path: currentPath)
            if let size = metadata.size, size > maxBytes { throw StorageError.tooLarge }
            guard let link = before["@microsoft.graph.downloadUrl"] as? String, let url = URL(string: link) else {
                throw StorageError.invalidResponse
            }
            try StorageHTTP.requireHTTPS(url)
            // This URL is already authorized; never attach the Graph bearer token.
            let response = try await client.transport.send(URLRequest(url: url), maxBytes: maxBytes).checked(path: currentPath)
            let after = try await client.json(itemURL(file.id))
            guard before["eTag"] as? String == after["eTag"] as? String else { continue }
            return RemoteDownload(file: metadata, data: response.data)
        }
        throw StorageError.conflict(file.path)
    }

    func upload(path: String, data: Data, existing: RemoteFile?, operationID: UUID) async throws -> RemoteFile {
        try StorageError.validate(path: path)
        _ = try await root()
        let url: URL
        var headers: [String: String] = [:]
        if let existing {
            let current = try await client.json(itemURL(existing.id))
            guard try await self.path(for: current) == path,
                  let etag = existing.revision, current["eTag"] as? String == etag else { throw StorageError.conflict(path) }
            headers["If-Match"] = etag
            url = try itemURL(existing.id, suffix: "/createUploadSession")
        } else {
            let parentID = try await directoryID((path as NSString).deletingLastPathComponent)
            url = try pathURL(parentID: parentID, name: (path as NSString).lastPathComponent, suffix: "/createUploadSession")
        }
        guard !data.isEmpty else {
            // Graph upload sessions do not accept zero-byte ranges. Use the
            // conditional content endpoint, retaining both preconditions.
            let contentURL: URL
            if let existing { contentURL = try itemURL(existing.id, suffix: "/content") }
            else {
                let parent = try await directoryID((path as NSString).deletingLastPathComponent)
                var components = URLComponents(url: try pathURL(parentID: parent, name: (path as NSString).lastPathComponent, suffix: "/content"), resolvingAgainstBaseURL: false)!
                components.queryItems = [.init(name: "@microsoft.graph.conflictBehavior", value: "fail")]
                contentURL = components.url!
            }
            var request = URLRequest(url: contentURL)
            request.httpMethod = "PUT"; request.httpBody = data
            request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            if let existing { request.setValue(existing.revision, forHTTPHeaderField: "If-Match") }
            else { request.setValue("*", forHTTPHeaderField: "If-None-Match") }
            let result = try await client.send(request).checked(path: path).json()
            deltaCursor = nil
            return try decode(result, path: path)
        }
        let json = try await client.json(url, method: "POST",
                                         body: ["item": ["@microsoft.graph.conflictBehavior": existing == nil ? "fail" : "replace",
                                                          "name": (path as NSString).lastPathComponent]], headers: headers, path: path)
        guard let link = json["uploadUrl"] as? String, let uploadURL = URL(string: link) else { throw StorageError.invalidResponse }
        try StorageHTTP.requireHTTPS(uploadURL)
        let chunkSize = 10 * 320 * 1024
        var offset = 0, final: [String: Any]?
        while offset < data.count {
            let end = min(offset + chunkSize, data.count)
            var request = URLRequest(url: uploadURL)
            request.httpMethod = "PUT"; request.httpBody = data.subdata(in: offset..<end)
            request.setValue("bytes \(offset)-\(end - 1)/\(data.count)", forHTTPHeaderField: "Content-Range")
            request.setValue(String(end - offset), forHTTPHeaderField: "Content-Length")
            let response = try await client.transport.send(request, maxBytes: StorageHTTP.metadataLimit).checked(path: path)
            if response.status == 200 || response.status == 201 {
                guard end == data.count else { throw StorageError.invalidResponse }
                final = try response.json()
            } else if response.status == 202 {
                let status = try response.json()
                guard end < data.count, let ranges = status["nextExpectedRanges"] as? [String],
                      ranges.first == "\(end)-" else { throw StorageError.invalidResponse }
            } else { throw StorageError.invalidResponse }
            offset = end
        }
        guard let final else { throw StorageError.invalidResponse }
        let result = try decode(final, path: path)
        deltaCursor = nil
        let verified = try await download(result, maxBytes: max(1, data.count))
        guard verified.data == data else { throw StorageError.conflict(path) }
        return verified.file
    }

    func createDirectory(path: String) async throws -> RemoteFile {
        try StorageError.validate(path: path)
        let parent = try await directoryID((path as NSString).deletingLastPathComponent)
        let json = try await client.json(itemURL(parent, suffix: "/children"), method: "POST",
                                         body: ["name": (path as NSString).lastPathComponent, "folder": [:], "@microsoft.graph.conflictBehavior": "fail"], path: path)
        deltaCursor = nil
        return try decode(json, path: path)
    }

    func move(_ file: RemoteFile, to path: String) async throws -> RemoteFile {
        try StorageError.validate(path: path)
        guard path != file.path, !path.hasPrefix(file.path + "/") else { throw StorageError.unsafePath(path) }
        let parent = try await directoryID((path as NSString).deletingLastPathComponent)
        guard let etag = file.revision else { throw StorageError.conflict(file.path) }
        let current = try await client.json(itemURL(file.id))
        guard try await self.path(for: current) == file.path else { throw StorageError.conflict(file.path) }
        let json = try await client.json(itemURL(file.id), method: "PATCH",
                                         body: ["name": (path as NSString).lastPathComponent, "parentReference": ["id": parent],
                                                "@microsoft.graph.conflictBehavior": "fail"],
                                         headers: ["If-Match": etag], path: path)
        deltaCursor = nil
        return try decode(json, path: path)
    }

    private func root() async throws -> [String: Any] {
        let json = try await client.json(itemURL(rootID))
        guard json["id"] as? String == rootID, json["folder"] != nil, json["deleted"] == nil else {
            throw StorageError.rootUnavailable
        }
        return json
    }

    private func directoryID(_ path: String) async throws -> String {
        _ = try await root()
        if path.isEmpty { return rootID }
        try StorageError.validate(path: path)
        let snapshot = try await enumerateChildren()
        let matches = snapshot.files.filter { $0.path == path && $0.isDirectory }
        guard matches.count == 1 else { throw StorageError.rootUnavailable }
        return matches[0].id
    }

    private func path(for item: [String: Any]) async throws -> String {
        var item = item, components: [String] = [], visited = Set<String>()
        while try StorageHTTP.string(item, "id") != rootID {
            let id = try StorageHTTP.string(item, "id")
            guard visited.insert(id).inserted, visited.count < 256,
                  let parent = item["parentReference"] as? [String: Any], let parentID = parent["id"] as? String else {
                throw StorageError.rootUnavailable
            }
            components.append(try StorageHTTP.string(item, "name"))
            if parentID == rootID { break }
            item = try await client.json(itemURL(parentID))
        }
        let path = components.reversed().joined(separator: "/")
        try StorageError.validate(path: path)
        return path
    }

    private func buildFiles(_ records: [String: [String: Any]], allowOutside: Bool) throws -> [RemoteFile] {
        var result: [RemoteFile] = []
        for (id, record) in records where id != rootID {
            var current = record, names: [String] = [], seen = Set<String>()
            while true {
                let currentID = try StorageHTTP.string(current, "id")
                guard seen.insert(currentID).inserted, seen.count < 256,
                      let parent = current["parentReference"] as? [String: Any], let parentID = parent["id"] as? String else {
                    throw StorageError.invalidResponse
                }
                names.append(try StorageHTTP.string(current, "name"))
                if parentID == rootID { break }
                guard let ancestor = records[parentID] else {
                    if !allowOutside { throw StorageError.invalidResponse }
                    names = []; break
                }
                current = ancestor
            }
            if names.isEmpty { continue } // Item moved out of the connected root.
            result.append(try decode(record, path: names.reversed().joined(separator: "/")))
        }
        return result
    }

    private func decode(_ json: [String: Any], path: String) throws -> RemoteFile {
        try StorageError.validate(path: path)
        guard json["remoteItem"] == nil else { throw StorageError.unsupported(String(localized: "Shortcuts to other OneDrive locations are not supported in the workspace.")) }
        let directory = json["folder"] != nil
        guard directory || json["file"] != nil, let revision = json["eTag"] as? String else { throw StorageError.invalidResponse }
        return RemoteFile(id: try StorageHTTP.string(json, "id"), path: path, isDirectory: directory, revision: revision,
                          modifiedAt: StorageHTTP.date(json["lastModifiedDateTime"]), size: StorageHTTP.size(json["size"]))
    }

    private func itemURL(_ id: String, suffix: String = "") throws -> URL {
        try StorageHTTP.url("https://graph.microsoft.com", path: "/v1.0/drives/\(driveID)/items/\(id)" + suffix)
    }
    private func pathURL(parentID: String, name: String, suffix: String) throws -> URL {
        try StorageHTTP.url("https://graph.microsoft.com", path: "/v1.0/drives/\(driveID)/items/\(parentID):/\(name):" + suffix)
    }
    private func nextLink(_ json: [String: Any]) throws -> URL? {
        guard let string = json["@odata.nextLink"] as? String else { return nil }
        guard let url = URL(string: string), url.host == "graph.microsoft.com", url.scheme == "https" else { throw StorageError.invalidResponse }
        return url
    }
}
