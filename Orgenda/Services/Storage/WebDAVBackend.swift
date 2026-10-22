import Foundation

actor WebDAVBackend: RemoteWorkspaceBackend {
    let rootURL: URL
    let transport: any StorageHTTPTransport
    private var activeRequests = 0
    private var requestWaiters: [(UUID, CheckedContinuation<Void, Error>)] = []

    init(rootURL: URL, transport: any StorageHTTPTransport) {
        self.rootURL = rootURL; self.transport = transport
    }

    private var isNutstore: Bool { rootURL.host?.lowercased() == "dav.jianguoyun.com" }

    private func conditionalETag(_ value: String?) -> String? {
        if let strong = StorageHTTP.strongETag(value) { return strong }
        // Nutstore returns bare version identifiers. Preserve them exactly;
        // verifyWritable exercises real stale-version rejection before setup.
        guard isNutstore, let value, !value.isEmpty, !value.uppercased().hasPrefix("W/"),
              value.utf8.allSatisfy({ (0x21...0x7E).contains($0) && ![0x22, 0x2A, 0x2C].contains($0) }) else { return nil }
        return value
    }

    func scan() async throws -> RemoteScan {
        let root = try await properties(path: "", depth: 0)
        guard root.count == 1, root[0].path.isEmpty, root[0].isDirectory else { throw StorageError.rootUnavailable }
        var queue = [""], files: [RemoteFile] = [], visited = Set<String>()
        var unavailable: [String: String] = [:]
        while !queue.isEmpty {
            try Task.checkCancellation()
            let parents = Array(queue.prefix(4))
            queue.removeFirst(parents.count)
            let listings = await withTaskGroup(of: (String, Result<[RemoteFile], Error>).self) { group in
                for parent in parents { group.addTask {
                    do { return (parent, .success(try await self.properties(path: parent, depth: 1))) }
                    catch { return (parent, .failure(error)) }
                } }
                var result: [(String, Result<[RemoteFile], Error>)] = []
                for await listing in group { result.append(listing) }
                return result
            }
            for (parent, result) in listings {
                let listing: [RemoteFile]
                switch result {
                case .success(let value): listing = value
                case .failure(let error):
                    if parent.isEmpty || error is CancellationError || LocalStore.isUnavailable(error) { throw error }
                    if case StorageError.throttled = error { throw error }
                    unavailable[parent] = error.localizedDescription
                    continue
                }
                let selfEntries = listing.filter { $0.path == parent }
                guard selfEntries.count == 1, selfEntries[0].isDirectory else {
                    if parent.isEmpty { throw StorageError.invalidResponse }
                    unavailable[parent] = StorageError.invalidResponse.localizedDescription
                    continue
                }
                var paths = Set<String>()
                let children = listing.filter { $0.path != parent }
                guard children.allSatisfy({ ($0.path as NSString).deletingLastPathComponent == parent && paths.insert($0.path).inserted && !visited.contains($0.path) }) else {
                    if parent.isEmpty { throw StorageError.invalidResponse }
                    unavailable[parent] = StorageError.invalidResponse.localizedDescription
                    continue
                }
                for file in children {
                    visited.insert(file.path)
                    files.append(file)
                    if file.isDirectory { queue.append(file.path) }
                    guard files.count <= StorageHTTP.maximumEntries else { throw StorageError.tooLarge }
                }
            }
        }
        // Root metadata + one listing per directory + HEAD for unversioned documents.
        let pollRequests = 2 + files.filter {
            $0.isDirectory || (LocalStore.isVisible($0.path) && WorkspaceDocument.Kind(path: $0.path) != nil
                && conditionalETag($0.revision) == nil)
        }.count
        // Reserve half of Nutstore's 600 requests / 30 min allowance for edits and other clients.
        return RemoteScan(files: files, unavailablePaths: unavailable,
                          minimumSyncInterval: isNutstore ? max(300, Double(pollRequests) * 6) : 30)
    }

    func downloadIfChanged(_ file: RemoteFile, since revision: String, maxBytes: Int) async throws -> RemoteDownload? {
        // Cached revisions were validated during download; an exact match is sufficient.
        if conditionalETag(file.revision) == nil {
            let response = try await send("HEAD", path: file.path).checked(path: file.path)
            if response.headers["etag"] == revision { return nil }
        }
        return try await download(file, maxBytes: maxBytes)
    }

    func download(_ file: RemoteFile, maxBytes: Int) async throws -> RemoteDownload {
        guard !file.isDirectory else { throw StorageError.invalidResponse }
        for _ in 0..<3 {
            let before = try await metadata(file.path)
            let revision = conditionalETag(before.revision)
            let response = try await send("GET", path: file.path,
                                          headers: revision.map { ["If-Match": $0] } ?? [:], limit: maxBytes)
            if response.status == 412 { continue }
            _ = try response.checked(path: file.path)
            if let revision, let returned = response.headers["etag"], returned != revision { continue }
            let returned = conditionalETag(response.headers["etag"])
            guard let downloadedRevision = returned ?? revision else {
                throw StorageError.unsupported(String(localized: "This WebDAV server does not provide reliable file version identifiers."))
            }
            var after = try await metadata(file.path)
            let current = conditionalETag(after.revision)
            guard current == downloadedRevision || (current == nil && returned != nil) else { continue }
            // GET can provide the version even when PROPFIND and HEAD omit it.
            after.revision = downloadedRevision
            return RemoteDownload(file: after, data: response.data)
        }
        throw StorageError.conflict(file.path)
    }

    func upload(path: String, data: Data, existing: RemoteFile?) async throws -> RemoteFile {
        try StorageError.validate(path: path)
        if existing == nil && isNutstore {
            try await createWithoutReplacing(path: path, data: data)
        } else {
            var headers = ["Content-Type": "application/octet-stream"]
            if let existing {
                guard existing.path == path, !existing.isDirectory,
                      let etag = conditionalETag(existing.revision) else { throw StorageError.conflict(path) }
                headers["If-Match"] = etag
            } else { headers["If-None-Match"] = "*" }
            let response = try await send("PUT", path: path, headers: headers, body: data).checked(path: path)
            // A strong response ETag identifies the representation the server
            // stored. Later external edits remain protected by the next If-Match.
            if let revision = StorageHTTP.strongETag(response.headers["etag"]) {
                return RemoteFile(id: path, path: path, isDirectory: false, revision: revision, size: Int64(data.count))
            }
        }
        // Do not claim success if another writer won immediately after our PUT.
        let downloaded = try await download(.init(id: path, path: path, isDirectory: false), maxBytes: max(data.count, 1))
        guard downloaded.data == data else { throw StorageError.conflict(path) }
        return downloaded.file
    }

    private func createWithoutReplacing(path: String, data: Data) async throws {
        let parent = (path as NSString).deletingLastPathComponent
        let name = ".orgenda-upload-" + UUID().uuidString.lowercased()
        let temporary = parent.isEmpty ? name : parent + "/" + name
        do {
            _ = try await send("PUT", path: temporary, headers: ["Content-Type": "application/octet-stream"], body: data).checked(path: temporary)
            _ = try await send("MOVE", path: temporary,
                               headers: ["Destination": try url(path).absoluteString, "Overwrite": "F"]).checked(path: path)
        } catch {
            try? await deleteTemporaryFile(temporary)
            throw error
        }
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
            guard let etag = conditionalETag(file.revision) else { throw StorageError.conflict(file.path) }
            headers["If-Match"] = etag
        }
        _ = try await send("MOVE", path: file.path, headers: headers).checked(path: path)
        return try await metadata(path)
    }

    func metadata(_ path: String) async throws -> RemoteFile {
        guard var item = try await properties(path: path, depth: 0).first(where: { $0.path == path }) else {
            throw StorageError.rootUnavailable
        }
        if !item.isDirectory, conditionalETag(item.revision) == nil {
            let response = try await send("HEAD", path: path)
            if response.status != 405 && response.status != 501 {
                _ = try response.checked(path: path)
                item.revision = conditionalETag(response.headers["etag"])
            }
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
        do {
            let file = try await upload(path: path, data: original, existing: nil)
            guard let etag = conditionalETag(file.revision) else { throw StorageError.invalidResponse }
            do {
                _ = try await upload(path: path, data: Data("unexpected".utf8), existing: nil)
                throw StorageError.unsupported(String(localized: "This WebDAV server does not enforce create-only writes."))
            } catch StorageError.conflict(let conflicted) where conflicted == path {
                // The same create path used by real uploads must refuse replacement.
            }
            let updated = try await upload(path: path, data: Data("Verified".utf8), existing: file)
            guard updated.revision != etag else {
                throw StorageError.unsupported(String(localized: "This WebDAV server does not reject conflicting changes."))
            }
            let oldVersion = try await send("PUT", path: path, headers: ["If-Match": etag], body: original)
            guard oldVersion.status == 412 else {
                throw StorageError.unsupported(String(localized: "This WebDAV server does not reject conflicting changes."))
            }
            let verified = try await download(updated, maxBytes: 1024)
            guard verified.data == Data("Verified".utf8) else { throw StorageError.invalidResponse }
            try await deleteTemporaryFile(path)
        } catch {
            try? await deleteTemporaryFile(path)
            throw error
        }
    }

    private func deleteTemporaryFile(_ path: String) async throws {
        // This private method only receives our own unique probe/upload paths.
        let file = try await metadata(path)
        var headers: [String: String] = [:]
        if let etag = conditionalETag(file.revision) { headers["If-Match"] = etag }
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
        try await acquireRequest()
        defer { releaseRequest() }
        try Task.checkCancellation()
        return try await transport.send(request, maxBytes: limit)
    }

    private func acquireRequest() async throws {
        try Task.checkCancellation()
        if activeRequests < 4 { activeRequests += 1; return }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { requestWaiters.append((id, $0)) }
        } onCancel: {
            Task { await self.cancelRequest(id) }
        }
    }

    private func cancelRequest(_ id: UUID) {
        if let index = requestWaiters.firstIndex(where: { $0.0 == id }) {
            requestWaiters.remove(at: index).1.resume(throwing: CancellationError())
        }
    }

    private func releaseRequest() {
        if requestWaiters.isEmpty { activeRequests -= 1 }
        else { requestWaiters.removeFirst().1.resume() }
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
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
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
