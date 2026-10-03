import Foundation

actor DropboxBackend: RemoteWorkspaceBackend {
    let rootID: String
    let client: CloudHTTPClient
    private var cachedCursor: String?
    private var cachedRootPath: String?

    init(rootID: String, client: CloudHTTPClient) { self.rootID = rootID; self.client = client }

    func scan(cursor: String?) async throws -> RemoteScan {
        let root = try await rootPath()
        if let cursor, cursor == cachedCursor, root == cachedRootPath {
            do {
                let result = try await list(cursor: cursor)
                // Folder moves can alter every descendant path. Re-enumerate the
                // complete tree rather than publish incomplete path updates.
                if result.entries.contains(where: { ($0[".tag"] as? String) != "file" }) {
                    return try await fullScan(root: root)
                }
                let files = coalesce(try result.entries.map { try decode($0, root: root) })
                cachedCursor = result.cursor
                return RemoteScan(files: files, cursor: result.cursor, isFullSnapshot: false)
            } catch StorageError.conflict { return try await fullScan(root: root) }
        }
        return try await fullScan(root: root)
    }

    private func fullScan(root: String) async throws -> RemoteScan {
        let result = try await list(cursor: nil)
        let files = coalesce(try result.entries.compactMap { entry -> RemoteFile? in
            if entry[".tag"] as? String == "deleted" { return nil }
            return try decode(entry, root: root)
        })
        cachedCursor = result.cursor; cachedRootPath = root
        return RemoteScan(files: files, cursor: result.cursor)
    }

    private func list(cursor: String?) async throws -> (entries: [[String: Any]], cursor: String) {
        var cursor = cursor, entries: [[String: Any]] = [], seen = Set<String>()
        while true {
            let endpoint = cursor == nil ? "list_folder" : "list_folder/continue"
            let body: [String: Any] = cursor.map { ["cursor": $0] }
                ?? ["path": rootID, "recursive": true, "include_deleted": false,
                    "include_non_downloadable_files": false, "limit": 2000]
            let json = try await rpc(endpoint, body: body)
            guard let page = json["entries"] as? [[String: Any]], let more = json["has_more"] as? Bool else {
                throw StorageError.invalidResponse
            }
            let next = try StorageHTTP.string(json, "cursor")
            entries += page
            guard entries.count <= StorageHTTP.maximumEntries else { throw StorageError.tooLarge }
            if !more { return (entries, next) }
            guard seen.insert(next).inserted else { throw StorageError.invalidResponse }
            cursor = next
        }
    }

    private func coalesce(_ files: [RemoteFile]) -> [RemoteFile] {
        var order: [String] = [], latest: [String: RemoteFile] = [:]
        for file in files {
            if latest[file.id] == nil { order.append(file.id) }
            latest[file.id] = file
        }
        return order.map { latest[$0]! }
    }

    func download(_ file: RemoteFile, maxBytes: Int) async throws -> RemoteDownload {
        let root = try await rootPath()
        var request = URLRequest(url: URL(string: "https://content.dropboxapi.com/2/files/download")!)
        request.httpMethod = "POST"
        request.setValue(try argument(["path": file.id]), forHTTPHeaderField: "Dropbox-API-Arg")
        let response = try await client.send(request, maxBytes: maxBytes).checked(path: file.path)
        guard let metadata = response.headers["dropbox-api-result"],
              let json = try JSONSerialization.jsonObject(with: Data(metadata.utf8)) as? [String: Any] else {
            throw StorageError.invalidResponse
        }
        let downloaded = try decode(json, root: root)
        guard downloaded.id == file.id else { throw StorageError.invalidResponse }
        return RemoteDownload(file: downloaded, data: response.data)
    }

    func upload(path: String, data: Data, existing: RemoteFile?, operationID: UUID) async throws -> RemoteFile {
        try StorageError.validate(path: path)
        guard data.count <= 150 * 1024 * 1024 else { throw StorageError.tooLarge }
        let root = try await rootPath()
        let mode: [String: Any]
        if let existing {
            guard let revision = existing.revision, !existing.isDirectory else { throw StorageError.conflict(path) }
            let current = try await metadata(id: existing.id, root: root)
            guard current.path == path, current.revision == revision else { throw StorageError.conflict(path) }
            mode = [".tag": "update", "update": revision]
        } else { mode = [".tag": "add"] }
        var request = URLRequest(url: URL(string: "https://content.dropboxapi.com/2/files/upload")!)
        request.httpMethod = "POST"; request.httpBody = data
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue(try argument(["path": root + "/" + path, "mode": mode,
                                       "autorename": false, "strict_conflict": true, "mute": true]),
                         forHTTPHeaderField: "Dropbox-API-Arg")
        let json = try await client.send(request).checked(path: path).json()
        let file = try decode(json, root: root)
        cachedCursor = nil
        return file
    }

    func createDirectory(path: String) async throws -> RemoteFile {
        try StorageError.validate(path: path)
        let root = try await rootPath()
        let json = try await rpc("create_folder_v2", body: ["path": root + "/" + path, "autorename": false], path: path)
        guard let metadata = json["metadata"] as? [String: Any] else { throw StorageError.invalidResponse }
        cachedCursor = nil
        return try decode(metadata, root: root)
    }

    func move(_ file: RemoteFile, to path: String) async throws -> RemoteFile {
        try StorageError.validate(path: path)
        guard path != file.path, !path.hasPrefix(file.path + "/") else { throw StorageError.unsafePath(path) }
        let root = try await rootPath()
        let current = try await metadata(id: file.id, root: root)
        guard current.path == file.path, current.revision == file.revision else { throw StorageError.conflict(file.path) }
        let json = try await rpc("move_v2", body: ["from_path": file.id, "to_path": root + "/" + path,
                                                   "autorename": false, "allow_shared_folder": false,
                                                   "allow_ownership_transfer": false], path: path)
        guard let metadata = json["metadata"] as? [String: Any] else { throw StorageError.invalidResponse }
        cachedCursor = nil
        return try decode(metadata, root: root)
    }

    private func rootPath() async throws -> String {
        let json: [String: Any]
        do { json = try await rpc("get_metadata", body: ["path": rootID]) }
        catch StorageError.conflict { throw StorageError.rootUnavailable }
        guard json[".tag"] as? String == "folder", json["id"] as? String == rootID,
              let path = json["path_display"] as? String, path.hasPrefix("/") else { throw StorageError.rootUnavailable }
        return path
    }

    private func metadata(id: String, root: String) async throws -> RemoteFile {
        try decode(await rpc("get_metadata", body: ["path": id]), root: root)
    }

    private func decode(_ json: [String: Any], root: String) throws -> RemoteFile {
        let tag = try StorageHTTP.string(json, ".tag")
        guard tag == "file" || tag == "folder" else { throw StorageError.invalidResponse }
        let absolute = try StorageHTTP.string(json, "path_display")
        let rootParts = root.split(separator: "/"), parts = absolute.split(separator: "/")
        guard parts.count > rootParts.count,
              zip(parts, rootParts).allSatisfy({ String($0).caseInsensitiveCompare(String($1)) == .orderedSame }) else {
            throw StorageError.unsafePath(absolute)
        }
        let path = parts.dropFirst(rootParts.count).joined(separator: "/")
        try StorageError.validate(path: path)
        let revision = json["rev"] as? String
        if tag == "file", revision == nil { throw StorageError.invalidResponse }
        return RemoteFile(id: try StorageHTTP.string(json, "id"), path: path, isDirectory: tag == "folder",
                          revision: revision, modifiedAt: StorageHTTP.date(json["server_modified"]),
                          size: StorageHTTP.size(json["size"]))
    }

    private func rpc(_ endpoint: String, body: [String: Any], path: String = "") async throws -> [String: Any] {
        try await client.json(URL(string: "https://api.dropboxapi.com/2/files/" + endpoint)!,
                              method: "POST", body: body, path: path)
    }

    private func argument(_ json: [String: Any]) throws -> String {
        // Dropbox arguments live in an HTTP header, so escape non-ASCII scalars.
        let string = String(decoding: try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys]), as: UTF8.self)
        return string.utf16.map { unit in
            if unit > 0x7e { return String(format: "\\u%04x", unit) }
            return String(UnicodeScalar(unit)!)
        }.joined()
    }
}
