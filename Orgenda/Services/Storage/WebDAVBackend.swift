import Foundation

actor WebDAVBackend: RemoteWorkspaceBackend {
    let rootURL: URL
    let transport: any StorageHTTPTransport

    init(rootURL: URL, transport: any StorageHTTPTransport) {
        self.rootURL = rootURL; self.transport = transport
    }

    func scan(cursor: String?) async throws -> RemoteScan {
        let root = try await properties(path: "", depth: 0)
        guard root.count == 1, root[0].path.isEmpty, root[0].isDirectory else { throw StorageError.rootUnavailable }
        var queue = [""], files: [RemoteFile] = [], visited = Set<String>()
        while !queue.isEmpty {
            try Task.checkCancellation()
            let parent = queue.removeFirst()
            let listing = try await properties(path: parent, depth: 1)
            let selfEntries = listing.filter { $0.path == parent }
            guard selfEntries.count == 1, selfEntries[0].isDirectory else { throw StorageError.conflict(parent) }
            for file in listing where file.path != parent {
                guard (file.path as NSString).deletingLastPathComponent == parent, visited.insert(file.path).inserted else {
                    throw StorageError.invalidResponse
                }
                files.append(file)
                if file.isDirectory { queue.append(file.path) }
                guard files.count <= StorageHTTP.maximumEntries else { throw StorageError.tooLarge }
            }
        }
        // RFC 6578 is optional. A complete Depth:1 traversal is a safe fallback;
        // failure in any child throws instead of publishing a partial snapshot.
        return RemoteScan(files: files, isFullSnapshot: true)
    }

    func download(_ file: RemoteFile, maxBytes: Int) async throws -> RemoteDownload {
        guard !file.isDirectory else { throw StorageError.invalidResponse }
        for _ in 0..<3 {
            let before = try await metadata(file.path)
            guard let revision = StorageHTTP.strongETag(before.revision) else {
                throw StorageError.unsupported(String(localized: "This WebDAV server does not provide strong file ETags."))
            }
            let response = try await send("GET", path: file.path,
                                          headers: ["If-Match": revision], limit: maxBytes)
            if response.status == 412 { continue }
            _ = try response.checked(path: file.path)
            if let returned = response.headers["etag"], returned != revision { continue }
            let after = try await metadata(file.path)
            guard after.revision == revision else { continue }
            return RemoteDownload(file: after, data: response.data)
        }
        throw StorageError.conflict(file.path)
    }

    func upload(path: String, data: Data, existing: RemoteFile?, operationID: UUID) async throws -> RemoteFile {
        try StorageError.validate(path: path)
        var headers = ["Content-Type": "application/octet-stream"]
        if let existing {
            guard existing.path == path, !existing.isDirectory,
                  let etag = StorageHTTP.strongETag(existing.revision) else {
                throw StorageError.conflict(path)
            }
            headers["If-Match"] = etag
        } else { headers["If-None-Match"] = "*" }
        _ = try await send("PUT", path: path, headers: headers, body: data).checked(path: path)
        let file = try await metadata(path)
        guard StorageHTTP.strongETag(file.revision) != nil else {
            throw StorageError.unsupported(String(localized: "This WebDAV server did not return a strong ETag after saving."))
        }
        // Do not claim success if another writer won immediately after our PUT.
        let downloaded = try await download(file, maxBytes: max(data.count, 1))
        guard downloaded.data == data else { throw StorageError.conflict(path) }
        return downloaded.file
    }

    func createDirectory(path: String) async throws -> RemoteFile {
        try StorageError.validate(path: path)
        let response = try await send("MKCOL", path: path)
        if response.status == 405 {
            let current = try await metadata(path)
            guard current.isDirectory else { throw StorageError.conflict(path) }
            return current
        }
        _ = try response.checked(path: path)
        return try await metadata(path)
    }

    func move(_ file: RemoteFile, to path: String) async throws -> RemoteFile {
        try StorageError.validate(path: path)
        guard path != file.path, !path.hasPrefix(file.path + "/") else { throw StorageError.unsafePath(path) }
        var headers = ["Destination": try url(path).absoluteString, "Overwrite": "F"]
        if !file.isDirectory {
            guard let etag = StorageHTTP.strongETag(file.revision) else { throw StorageError.conflict(file.path) }
            headers["If-Match"] = etag
        }
        _ = try await send("MOVE", path: file.path, headers: headers).checked(path: path)
        return try await metadata(path)
    }

    func metadata(_ path: String) async throws -> RemoteFile {
        guard let item = try await properties(path: path, depth: 0).first(where: { $0.path == path }) else {
            throw StorageError.rootUnavailable
        }
        return item
    }

    /// The connection is not accepted until create-only, conditional replacement,
    /// stale rejection and cleanup have all been exercised on our own probe file.
    func verifyWritable() async throws {
        let root = try await metadata("")
        guard root.isDirectory else { throw StorageError.rootUnavailable }
        let path = ".orgenda-probe-" + UUID().uuidString.lowercased()
        let original = Data("Orgenda connection check".utf8)
        var created = false
        do {
            let create = try await send("PUT", path: path, headers: ["If-None-Match": "*"], body: original)
            _ = try create.checked(path: path); created = true
            let file = try await metadata(path)
            guard let etag = StorageHTTP.strongETag(file.revision) else {
                throw StorageError.unsupported(String(localized: "Safe synchronization requires strong ETags from this WebDAV server."))
            }
            let duplicate = try await send("PUT", path: path, headers: ["If-None-Match": "*"], body: Data("unexpected".utf8))
            guard duplicate.status == 412 else {
                throw StorageError.unsupported(String(localized: "This WebDAV server does not enforce create-only writes."))
            }
            let stale = try await send("PUT", path: path, headers: ["If-Match": "\"orgenda-stale-\(UUID().uuidString)\""], body: Data("unexpected".utf8))
            guard stale.status == 412 else {
                throw StorageError.unsupported(String(localized: "This WebDAV server does not reject conflicting changes."))
            }
            let read = try await download(file, maxBytes: 1024)
            guard read.data == original else { throw StorageError.invalidResponse }
            _ = try await send("PUT", path: path, headers: ["If-Match": etag], body: Data("Verified".utf8)).checked(path: path)
            try await deleteProbe(path)
            created = false
        } catch {
            if created { try? await deleteProbe(path) }
            throw error
        }
    }

    private func deleteProbe(_ path: String) async throws {
        // This private method only receives the unique file created above.
        let file = try await metadata(path)
        var headers: [String: String] = [:]
        if let etag = StorageHTTP.strongETag(file.revision) { headers["If-Match"] = etag }
        _ = try await send("DELETE", path: path, headers: headers).checked(path: path)
    }

    func ensureRootDuringSetup() async throws {
        let response = try await send("PROPFIND", path: "", headers: ["Depth": "0"], body: Self.propertyBody)
        if response.status == 404 {
            _ = try await send("MKCOL", path: "").checked()
        } else { _ = try response.checked() }
    }

    private static let propertyBody = Data("""
    <?xml version="1.0" encoding="utf-8"?><d:propfind xmlns:d="DAV:"><d:prop><d:resourcetype/><d:getetag/><d:getlastmodified/><d:getcontentlength/></d:prop></d:propfind>
    """.utf8)

    private func properties(path: String, depth: Int) async throws -> [RemoteFile] {
        let result = try await send("PROPFIND", path: path,
                                    headers: ["Depth": String(depth), "Content-Type": "application/xml; charset=utf-8"],
                                    body: Self.propertyBody).checked(path: path)
        guard result.status == 207 else { throw StorageError.invalidResponse }
        let parser = WebDAVMultistatusParser()
        return try parser.parse(result.data, root: rootURL)
    }

    private func url(_ path: String) throws -> URL {
        try StorageError.validate(path: path, allowEmpty: true)
        return path.split(separator: "/").reduce(rootURL) { $0.appendingPathComponent(String($1)) }
    }

    private func send(_ method: String, path: String, headers: [String: String] = [:],
                      body: Data? = nil, limit: Int = StorageHTTP.metadataLimit) async throws -> StorageHTTPResponse {
        var request = URLRequest(url: try url(path))
        request.httpMethod = method; request.httpBody = body
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        return try await transport.send(request, maxBytes: limit)
    }
}

/// Strict namespace-aware XML parsing. Missing/failed resource responses never
/// silently disappear from a scan (which could otherwise look like deletions).
final class WebDAVMultistatusParser: NSObject, XMLParserDelegate {
    private struct Entry {
        var href = "", etag: String?, date: String?, size: String?
        var directory = false, statuses: [Int] = [], responseStatus: Int?
        var hasResourceType = false
    }
    private var entries: [Entry] = []
    private var current = Entry()
    private var stack: [String] = []
    private var text = ""
    private var propertyStatus: Int?
    private var pending = Entry()
    private var invalid = false

    func parse(_ data: Data, root: URL) throws -> [RemoteFile] {
        guard !String(decoding: data, as: UTF8.self).localizedCaseInsensitiveContains("<!DOCTYPE") else {
            throw StorageError.invalidResponse
        }
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false
        parser.delegate = self
        guard parser.parse(), !invalid, !entries.isEmpty else { throw StorageError.invalidResponse }
        let rootPath = root.standardized.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return try entries.map { entry in
            guard entry.responseStatus.map({ (200..<300).contains($0) }) ?? true,
                  entry.statuses.contains(where: { (200..<300).contains($0) }),
                  entry.hasResourceType,
                  let url = URL(string: entry.href, relativeTo: root)?.absoluteURL,
                  StorageHTTP.sameOrigin(root, url), url.query == nil, url.fragment == nil else {
                throw StorageError.invalidResponse
            }
            let absolute = url.standardized.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let path: String
            if absolute == rootPath { path = "" }
            else if absolute.hasPrefix(rootPath + "/") { path = String(absolute.dropFirst(rootPath.count + 1)) }
            else if rootPath.isEmpty { path = absolute }
            else { throw StorageError.unsafePath(entry.href) }
            try StorageError.validate(path: path, allowEmpty: true)
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
            return RemoteFile(id: path, path: path, isDirectory: entry.directory, revision: entry.etag,
                              modifiedAt: entry.date.flatMap(formatter.date(from:)), size: entry.size.flatMap(Int64.init))
        }
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        let element = namespaceURI == "DAV:" ? elementName : "_foreign"
        stack.append(element); text = ""
        if element == "response" { current = Entry() }
        if element == "propstat" { pending = Entry(); propertyStatus = nil }
        if element == "collection", stack.contains("propstat") { pending.directory = true }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let element = stack.last ?? ""
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch element {
        case "href": if !stack.contains("propstat") { current.href = value }
        case "getetag": pending.etag = value
        case "getlastmodified": pending.date = value
        case "getcontentlength": pending.size = value
        case "resourcetype": pending.hasResourceType = true
        case "status":
            let status = value.split(separator: " ").dropFirst().first.flatMap { Int($0) }
            if stack.contains("propstat") { propertyStatus = status } else { current.responseStatus = status }
        case "propstat":
            guard let status = propertyStatus else { invalid = true; break }
            current.statuses.append(status)
            if (200..<300).contains(status) {
                current.etag = pending.etag ?? current.etag
                current.date = pending.date ?? current.date
                current.size = pending.size ?? current.size
                current.directory = pending.directory || current.directory
                current.hasResourceType = pending.hasResourceType || current.hasResourceType
            }
        case "response": entries.append(current)
        default: break
        }
        _ = stack.popLast(); text = ""
    }
    func parser(_ parser: XMLParser, resolveExternalEntityName name: String, systemID: String?) -> Data? {
        invalid = true; return nil
    }
}
