import Foundation

/// The filesystem boundary for a workspace. The caller owns its security scope.
/// Actor isolation keeps directory traversal and coordinated file I/O off the UI actor.
actor WorkspaceFileStore {
    enum Failure: Error, Equatable, LocalizedError {
        case unavailableRoot
        case unsafePath(String)
        case conflict(String)
        case invalidUTF8(String)
        case unsupportedFile(String)
        case unreadable(String)

        var errorDescription: String? {
            switch self {
            case .unavailableRoot:
                return String(localized: "The workspace folder is unavailable. Reconnect the folder and try again.")
            case .unsafePath(let path):
                return String(localized: "The workspace cannot access \(path) because its path leaves the selected folder or contains a symbolic-link cycle.")
            case .conflict(let path):
                return String(localized: "\(path) changed outside orgenda. Your local edit has been kept; reload the file before saving again.")
            case .invalidUTF8(let path):
                return String(localized: "\(path) is not a valid UTF-8 text file.")
            case .unsupportedFile(let path):
                return String(localized: "\(path) is not an Org or Markdown file.")
            case .unreadable(let path):
                return String(localized: "\(path) could not be read. The existing workspace has been kept.")
            }
        }
    }

    enum ImageReadFailure: Error, Equatable, LocalizedError {
        case tooLarge
        case notRegularFile
        case invalidSizeLimit

        var errorDescription: String? {
            switch self {
            case .tooLarge:
                return String(localized: "The image is too large to display.")
            case .notRegularFile:
                return String(localized: "The image path does not point to a readable file.")
            case .invalidSizeLimit:
                return String(localized: "The image could not be loaded because its size limit is invalid.")
            }
        }
    }

    private let rootURL: URL
    nonisolated let recoveryIdentity: String
    private let fileManager = FileManager.default

    init(rootURL: URL) {
        self.rootURL = rootURL
        recoveryIdentity = rootURL.resolvingSymlinksInPath().standardizedFileURL.path
    }

    /// Returns a complete load or throws. An inaccessible file must never look
    /// like a remote deletion to the caller's reconciliation logic.
    func load() throws -> [WorkspaceDocument] {
        try Task.checkCancellation()
        let root = try resolvedRoot()
        let coordinator = NSFileCoordinator(filePresenter: nil)
        return try coordinatedRead(at: root, coordinator: coordinator) { coordinatedRoot in
            let root = coordinatedRoot.resolvingSymlinksInPath().standardizedFileURL
            var documents: [WorkspaceDocument] = []
            try self.collect(directory: root, relativePath: "", root: root,
                             ancestors: [], coordinator: coordinator, documents: &documents)
            return documents.sorted { $0.path < $1.path }
        }
    }

    /// Reads an attachment directly, including hidden Org attachment folders,
    /// without adding binary files to the workspace's document index. The
    /// caller owns the selected folder's security scope, as with `load()`.
    func readImageData(path: String, maxBytes: Int = 20 * 1024 * 1024) throws -> Data {
        try Task.checkCancellation()
        guard !path.isEmpty, !path.contains("\0") else { throw Failure.unsafePath(path) }
        guard maxBytes >= 0 else { throw ImageReadFailure.invalidSizeLimit }
        let root = try resolvedRoot()
        let requestedURL: URL
        if path.hasPrefix("/") {
            // Absolute paths can use the original root's alias (for example
            // /var rather than /private/var), but must resolve inside the root.
            requestedURL = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL
        } else {
            requestedURL = root.appendingPathComponent(path)
        }
        let safeURL = try containedURL(requestedURL, root: root, path: path)
        let coordinator = NSFileCoordinator(filePresenter: nil)
        return try coordinatedRead(at: safeURL, coordinator: coordinator) { coordinatedURL in
            let currentURL = try self.containedURL(coordinatedURL, root: root, path: path)
            guard currentURL == safeURL else { throw Failure.unsafePath(path) }
            // Check after coordination so the file provider can materialize
            // an evicted image before its type, size, or bytes are inspected.
            let values = try currentURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true else { throw ImageReadFailure.notRegularFile }
            if let size = values.fileSize, size > maxBytes { throw ImageReadFailure.tooLarge }

            let handle = try FileHandle(forReadingFrom: currentURL)
            defer { try? handle.close() }
            var data = Data()
            while true {
                try Task.checkCancellation()
                let remaining = maxBytes - data.count
                // Reading at most one byte beyond the budget also catches
                // files that grow after the size check, without an unbounded
                // allocation or overflowing when maxBytes equals Int.max.
                let chunkSize = remaining >= 64 * 1024 ? 64 * 1024 : remaining + 1
                guard let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty else { break }
                guard chunk.count <= remaining else { throw ImageReadFailure.tooLarge }
                data.append(chunk)
            }
            return data
        }
    }

    /// `nil` means creation: it never grants permission to replace an existing
    /// file. Compare and atomic replacement happen inside one coordinated write.
    func write(path: String, contents: String, expectedContents: String?) throws {
        try Task.checkCancellation()
        try validate(path: path)
        guard Self.documentKind(for: path) != nil else { throw Failure.unsupportedFile(path) }
        let root = try resolvedRoot()
        let requestedURL = root.appendingPathComponent(path)
        let destination = try containedURL(requestedURL, root: root, path: path)
        let parent = destination.deletingLastPathComponent()

        // Resolve and validate before creating directories, so a nested link can
        // never redirect even a new file outside the selected workspace.
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        var coordinationError: NSError?
        var result: Result<Void, Error>?
        let coordinator = NSFileCoordinator(filePresenter: nil)
        // Updating a document uses the default coordination option, including
        // when the implementation atomically renames temporary bytes into place.
        coordinator.coordinate(writingItemAt: destination, options: [],
                               error: &coordinationError) { coordinatedURL in
            result = Result {
                let safeURL = try self.containedURL(coordinatedURL, root: root, path: path)
                guard safeURL == destination else { throw Failure.conflict(path) }
                let current = try self.existingData(at: safeURL)
                let expected = expectedContents.map { Data($0.utf8) }
                if current == Data(contents.utf8) { return }
                guard current == expected else { throw Failure.conflict(path) }
                try Data(contents.utf8).write(to: safeURL, options: .atomic)
            }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw Failure.unreadable(path) }
        try result.get()
    }

    private func collect(
        directory: URL, relativePath: String, root: URL,
        ancestors: Set<String>, coordinator: NSFileCoordinator,
        documents: inout [WorkspaceDocument]
    ) throws {
        let resolvedDirectory = try containedURL(directory, root: root, path: relativePath)
        guard !ancestors.contains(resolvedDirectory.path) else {
            throw Failure.unsafePath(relativePath)
        }
        var ancestors = ancestors
        ancestors.insert(resolvedDirectory.path)
        let children = try fileManager.contentsOfDirectory(
            at: resolvedDirectory,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey],
            options: []
        ).sorted { $0.lastPathComponent < $1.lastPathComponent }

        for child in children {
            try Task.checkCancellation()
            let name = child.lastPathComponent
            let path = relativePath.isEmpty ? name : relativePath + "/" + name
            if name.hasPrefix(".") {
                // Legacy iCloud placeholders have hidden `.name.org.icloud`
                // names. Ignoring one would report an evicted file as deleted.
                if name.hasSuffix(".icloud") {
                    let originalName = String(name.dropFirst().dropLast(".icloud".count))
                    if Self.documentKind(for: originalName) != nil {
                        throw Failure.unreadable(relativePath.isEmpty ? originalName : relativePath + "/" + originalName)
                    }
                }
                continue
            }
            // Validate links even if their extension is not supported: an
            // escaping directory link must not become a hidden partial import.
            let safeURL = try containedURL(child, root: root, path: path)
            let values = try safeURL.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
            if values.isDirectory == true {
                documents.append(WorkspaceDocument(path: path, title: name, contents: "", kind: .folder))
                try collect(directory: safeURL, relativePath: path, root: root,
                            ancestors: ancestors, coordinator: coordinator, documents: &documents)
            } else if let kind = Self.documentKind(for: path) {
                guard values.isRegularFile == true else { throw Failure.unreadable(path) }
                // Directory coordination does not coordinate its ordinary child
                // files. Each read also gives a file provider a chance to finish
                // downloading an evicted document before its contents are read.
                let data = try coordinatedRead(at: safeURL, coordinator: coordinator) { coordinatedURL in
                    let currentURL = try self.containedURL(coordinatedURL, root: root, path: path)
                    guard currentURL == safeURL else { throw Failure.unreadable(path) }
                    return try Data(contentsOf: currentURL)
                }
                guard let contents = String(data: data, encoding: .utf8) else {
                    throw Failure.invalidUTF8(path)
                }
                documents.append(WorkspaceDocument(
                    path: path,
                    title: child.deletingPathExtension().lastPathComponent,
                    contents: contents,
                    kind: kind
                ))
            }
        }
    }

    private func resolvedRoot() throws -> URL {
        guard rootURL.isFileURL else { throw Failure.unavailableRoot }
        // A user-selected root may itself be a symlink (for example ~/org).
        let root = rootURL.resolvingSymlinksInPath().standardizedFileURL
        let values = try root.resourceValues(forKeys: [.isDirectoryKey])
        guard values.isDirectory == true else { throw Failure.unavailableRoot }
        return root
    }

    private func containedURL(_ url: URL, root: URL, path: String) throws -> URL {
        let rootComponents = root.pathComponents
        let components = url.standardizedFileURL.pathComponents
        guard components.starts(with: rootComponents) else {
            throw Failure.unsafePath(path)
        }
        // Resolving the complete URL is insufficient when its final component
        // does not exist: Foundation may leave a linked ancestor unresolved.
        // Walk every component before creating any of the missing directories.
        var resolved = root
        for component in components.dropFirst(rootComponents.count) {
            resolved = resolved.appendingPathComponent(component)
                .resolvingSymlinksInPath().standardizedFileURL
            guard resolved.pathComponents.starts(with: rootComponents) else {
                throw Failure.unsafePath(path)
            }
        }
        return resolved
    }

    private func validate(path: String) throws {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.isEmpty, !path.contains("\0"),
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." })
        else { throw Failure.unsafePath(path) }
    }

    private func existingData(at url: URL) throws -> Data? {
        do {
            return try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        }
    }

    private func coordinatedRead<T>(
        at url: URL, coordinator: NSFileCoordinator, accessor: (URL) throws -> T
    ) throws -> T {
        var coordinationError: NSError?
        var result: Result<T, Error>?
        coordinator.coordinate(
            readingItemAt: url, options: .withoutChanges, error: &coordinationError
        ) { coordinatedURL in
            result = Result { try accessor(coordinatedURL) }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw Failure.unreadable(url.lastPathComponent) }
        return try result.get()
    }

    private static func documentKind(for path: String) -> WorkspaceDocument.Kind? {
        switch (path as NSString).pathExtension.lowercased() {
        case "org", "org_archive": return .org
        case "md", "markdown": return .markdown
        default: return nil
        }
    }
}

extension WorkspaceFileStore {
    /// Move the filesystem item itself, including unindexed attachments and
    /// hidden children. Never reconstruct a folder from its parsed documents.
    func move(path: String, to destination: String, expected: [WorkspaceDocument]) throws {
        try validateVisiblePath(path)
        try validateVisiblePath(destination)
        guard !WorkspaceFileTransfer.contains(destination, in: path), path != destination else {
            throw WorkspaceFileActionError.invalidDestination
        }
        try coordinatedMove(from: path, to: destination, expected: expected)
    }

    func trash(document: WorkspaceDocument, expected: [WorkspaceDocument]) throws -> WorkspaceTrashEntry {
        try validateVisiblePath(document.path)
        let root = try resolvedRoot()
        let entry = WorkspaceTrashEntry(id: UUID(), originalPath: document.path,
            title: document.title, kind: document.kind, deletedAt: .now)
        let bucket = try strictURL(entry.storageFolder, root: root)
        try fileManager.createDirectory(at: bucket, withIntermediateDirectories: true)
        do {
            try JSONEncoder().encode(entry).write(to: bucket.appendingPathComponent("info.json"), options: .atomic)
            try coordinatedMove(from: document.path, to: entry.storagePath, expected: expected)
            return entry
        } catch {
            // Only clean the UUID directory owned by this failed operation,
            // and never clean a directory that already contains the payload.
            if !fileManager.fileExists(atPath: bucket.appendingPathComponent("item").path) {
                cleanTrashMetadata(in: bucket)
            }
            throw error
        }
    }

    func deletedEntries() throws -> [WorkspaceTrashEntry] {
        let root = try resolvedRoot()
        let trash = try strictURL(".orgenda-trash", root: root)
        guard fileManager.fileExists(atPath: trash.path) else { return [] }
        return try fileManager.contentsOfDirectory(at: trash, includingPropertiesForKeys: nil).compactMap { bucket in
            guard let id = UUID(uuidString: bucket.lastPathComponent) else { return nil }
            let metadata = try strictURL(".orgenda-trash/" + id.uuidString + "/info.json", root: root)
            guard let data = try? Data(contentsOf: metadata),
                  let entry = try? JSONDecoder().decode(WorkspaceTrashEntry.self, from: data),
                  entry.id == id else { return nil }
            try validateVisiblePath(entry.originalPath)
            let payload = try strictURL(entry.storagePath, root: root)
            return fileManager.fileExists(atPath: payload.path) ? entry : nil
        }.sorted { $0.deletedAt > $1.deletedAt }
    }

    func restore(_ entry: WorkspaceTrashEntry) throws {
        try validateVisiblePath(entry.originalPath)
        guard try deletedEntries().contains(entry) else { throw WorkspaceFileActionError.changed }
        let root = try resolvedRoot()
        let parent = try strictURL(entry.originalPath, root: root).deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        try coordinatedMove(from: entry.storagePath, to: entry.originalPath, expected: nil)
        // A failed metadata cleanup is harmless: entries without payloads are
        // excluded from Recently Deleted. Never roll back a successful restore.
        if let bucket = try? strictURL(entry.storageFolder, root: root) { cleanTrashMetadata(in: bucket) }
    }

    private func cleanTrashMetadata(in bucket: URL) {
        try? fileManager.removeItem(at: bucket.appendingPathComponent("info.json"))
        if (try? fileManager.contentsOfDirectory(atPath: bucket.path).isEmpty) == true {
            try? fileManager.removeItem(at: bucket)
        }
    }

    private func validateVisiblePath(_ path: String) throws {
        try validate(path: path)
        guard path.split(separator: "/").allSatisfy({ !$0.hasPrefix(".") }) else { throw Failure.unsafePath(path) }
    }

    private func strictURL(_ path: String, root: URL) throws -> URL {
        try validate(path: path)
        let requested = root.appendingPathComponent(path).standardizedFileURL
        let safe = try containedURL(requested, root: root, path: path)
        guard requested == safe else { throw Failure.unsafePath(path) }
        return safe
    }

    private func coordinatedMove(from path: String, to destination: String, expected: [WorkspaceDocument]?) throws {
        try Task.checkCancellation()
        let root = try resolvedRoot()
        let source = try strictURL(path, root: root)
        let target = try strictURL(destination, root: root)
        let parentValues = try target.deletingLastPathComponent().resourceValues(forKeys: [.isDirectoryKey])
        guard parentValues.isDirectory == true else { throw WorkspaceFileActionError.invalidDestination }
        var coordinationError: NSError?
        var outcome: Result<Void, Error>?
        let coordinator = NSFileCoordinator(filePresenter: nil)
        coordinator.coordinate(writingItemAt: source, options: .forMoving,
                               writingItemAt: target, options: [], error: &coordinationError) { from, to in
            outcome = Result {
                guard try self.strictURL(path, root: root) == from.standardizedFileURL,
                      try self.strictURL(destination, root: root) == to.standardizedFileURL else {
                    throw WorkspaceFileActionError.changed
                }
                guard !self.fileManager.fileExists(atPath: to.path) else { throw WorkspaceFileActionError.nameExists }
                if let expected {
                    let current = try self.moveSnapshot(at: from, path: path, root: root)
                    guard WorkspaceFileTransfer.matches(current, expected) else { throw WorkspaceFileActionError.changed }
                }
                try self.fileManager.moveItem(at: from, to: to)
                coordinator.item(at: from, didMoveTo: to)
            }
        }
        if let coordinationError { throw coordinationError }
        guard let outcome else { throw Failure.unreadable(path) }
        try outcome.get()
    }

    /// Called only while a coordinated .forMoving write holds the entire source
    /// subtree. Child reads do not start nested coordination transactions.
    private func moveSnapshot(at url: URL, path: String, root: URL) throws -> [WorkspaceDocument] {
        let safe = try strictURL(path, root: root)
        guard safe == url.standardizedFileURL else { throw Failure.unsafePath(path) }
        let values = try safe.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
        if values.isDirectory == true {
            var result = [WorkspaceDocument(path: path, title: safe.lastPathComponent, contents: "", kind: .folder)]
            for child in try fileManager.contentsOfDirectory(at: safe, includingPropertiesForKeys: nil) {
                if child.lastPathComponent.hasPrefix(".") {
                    if child.lastPathComponent.hasSuffix(".icloud") { throw Failure.unreadable(path) }
                    continue
                }
                result += try moveSnapshot(at: child, path: path + "/" + child.lastPathComponent, root: root)
            }
            return result
        }
        guard let kind = Self.documentKind(for: path) else { return [] }
        guard values.isRegularFile == true else { throw Failure.unreadable(path) }
        guard let contents = String(data: try Data(contentsOf: safe), encoding: .utf8) else { throw Failure.invalidUTF8(path) }
        return [WorkspaceDocument(path: path, title: safe.deletingPathExtension().lastPathComponent, contents: contents, kind: kind)]
    }
}
