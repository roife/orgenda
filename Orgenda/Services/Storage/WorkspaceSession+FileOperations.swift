import Foundation

extension WorkspaceSession {
    func move(path: String, to destination: String, expected: [WorkspaceDocument]) async throws {
        try StorageError.validate(path: path)
        try StorageError.validate(path: destination)
        guard Self.isVisible(path), Self.isVisible(destination), path != destination,
              !WorkspaceFileTransfer.contains(destination, in: path) else { throw StorageError.unsafePath(destination) }
        try await prepareFileOperation()
        guard WorkspaceFileTransfer.matches(expected, try load().filter { WorkspaceFileTransfer.contains($0.path, in: path) }),
              let source = manifest.entries[path]?.file else { throw StorageError.conflict(path) }
        guard manifest.entries[destination] == nil else { throw WorkspaceFileActionError.nameExists }
        try await performFileOperation(SyncFileOperation(kind: .move, sourcePath: path,
            destinationPath: destination, source: source, expected: expected))
    }

    func trash(document: WorkspaceDocument, expected: [WorkspaceDocument]) async throws -> WorkspaceTrashEntry {
        try StorageError.validate(path: document.path)
        guard Self.isVisible(document.path) else { throw StorageError.unsafePath(document.path) }
        try await prepareFileOperation()
        guard WorkspaceFileTransfer.matches(expected, try load().filter { WorkspaceFileTransfer.contains($0.path, in: document.path) }),
              let source = manifest.entries[document.path]?.file else { throw StorageError.conflict(document.path) }
        let entry = WorkspaceTrashEntry(id: UUID(), originalPath: document.path, title: document.title,
                                        kind: document.kind, deletedAt: .now)
        try await performFileOperation(SyncFileOperation(kind: .trash, sourcePath: document.path,
            destinationPath: entry.storagePath, source: source, expected: expected, trashEntry: entry))
        // Folder storage owns the trash UUID; recovery reconciles its generated
        // entry with the intent recorded before invoking the folder operation.
        return manifest.trash.first { $0.originalPath == document.path && $0.deletedAt >= entry.deletedAt.addingTimeInterval(-1) } ?? entry
    }

    func restore(_ entry: WorkspaceTrashEntry) async throws {
        try StorageError.validate(path: entry.originalPath)
        guard Self.isVisible(entry.originalPath) else { throw StorageError.unsafePath(entry.originalPath) }
        try await prepareFileOperation()
        guard manifest.entries[entry.originalPath] == nil else { throw WorkspaceFileActionError.nameExists }
        let available = try await deletedEntries()
        guard available.contains(entry) else { throw WorkspaceFileActionError.changed }
        try await performFileOperation(SyncFileOperation(kind: .restore, sourcePath: entry.storagePath,
            destinationPath: entry.originalPath, source: manifest.entries[entry.storagePath]?.file,
            expected: [], trashEntry: entry))
    }

    func deletedEntries() async throws -> [WorkspaceTrashEntry] {
        if let folder {
            do {
                let entries = try await folder.deletedEntries()
                var next = manifest
                next.trash = entries
                try commit(next)
                return entries
            } catch {
                if manifest.initialized, Self.isUnavailable(error) { return manifest.trash }
                throw error
            }
        }
        guard let remote else { throw StorageError.rootUnavailable }
        var entries: [WorkspaceTrashEntry] = []
        do {
            for metadata in manifest.entries.values where metadata.file.path.hasPrefix(".orgenda-trash/")
                && metadata.file.path.hasSuffix("/info.json") {
                let parts = metadata.file.path.split(separator: "/")
                guard parts.count == 3, let id = UUID(uuidString: String(parts[1])) else { continue }
                let result = try await remote.download(metadata.file, maxBytes: 1024 * 1024)
                guard let entry = try? JSONDecoder().decode(WorkspaceTrashEntry.self, from: result.data), entry.id == id else { continue }
                try StorageError.validate(path: entry.originalPath)
                guard Self.isVisible(entry.originalPath), manifest.entries[entry.storagePath] != nil else { continue }
                entries.append(entry)
            }
            entries.sort { $0.deletedAt > $1.deletedAt }
            var next = manifest
            next.trash = entries
            try commit(next)
            return entries
        } catch {
            if Self.isUnavailable(error) { return manifest.trash }
            throw error
        }
    }

    /// A heading move is two conditional writes, destination first. Keeping its
    /// journal separate from ordinary drafts prevents retry from duplicating an
    /// already-committed destination after an interrupted request.
    func commitOnlineMove(source: WorkspaceDocument, destination: WorkspaceDocument,
                          expectedSource: String, expectedDestination: String?) async throws {
        try Self.validateVisibleDocument(source.path)
        try Self.validateVisibleDocument(destination.path)
        try await prepareFileOperation()
        guard try localData(source.path) == Data(expectedSource.utf8),
              try localData(destination.path) == expectedDestination.map({ Data($0.utf8) }) else {
            throw StorageError.conflict(source.path)
        }
        let oldSource = Self.document(path: source.path, contents: expectedSource, kind: source.kind)
        try await performFileOperation(SyncFileOperation(kind: .refile, sourcePath: source.path,
            destinationPath: destination.path, source: manifest.entries[source.path]?.file,
            expected: [oldSource], destinationContents: destination.contents,
            sourceContents: source.contents, expectedDestination: expectedDestination))
    }

    func prepareFileOperation() async throws {
        try await synchronize()
        guard manifest.pending.isEmpty, manifest.conflicts.isEmpty, manifest.fileOperation == nil,
              !isSynchronizing, !isPerformingFileOperation else { throw StorageError.busy }
    }

    func performFileOperation(_ operation: SyncFileOperation) async throws {
        guard !isSynchronizing, !isPerformingFileOperation, manifest.pending.isEmpty else { throw StorageError.busy }
        isPerformingFileOperation = true
        defer { isPerformingFileOperation = false }
        var next = manifest
        next.fileOperation = operation
        try commit(next)
        do {
            try await finishFileOperation()
            // A committed move already updates the cached tree. A failed refresh
            // must not report that successful move as a failed mutation.
            try? await refreshFromSource()
        } catch {
            if Self.isConflict(error) || error is WorkspaceFileActionError {
                var latest = manifest
                latest.fileOperation = nil
                try commit(latest)
            }
            throw error
        }
    }

    func finishFileOperation() async throws {
        guard let operation = manifest.fileOperation else { return }
        if operation.kind == .refile { try await finishRefile(operation); return }
        if let folder { try await finishFolderOperation(operation, folder: folder); return }
        guard let remote else { throw StorageError.rootUnavailable }

        let source = manifest.entries[operation.sourcePath]?.file
        let target = manifest.entries[operation.destinationPath]?.file
        if source == nil, let target, try await isCompletedMove(operation, target: target) {
            try acknowledgeMove(operation, result: target)
            return
        }
        guard var source, source.id == operation.source?.id else { throw StorageError.conflict(operation.sourcePath) }
        guard target == nil else { throw WorkspaceFileActionError.nameExists }
        if !operation.expected.isEmpty {
            let current = try baselineDocuments(under: operation.sourcePath)
            guard WorkspaceFileTransfer.matches(current, operation.expected) else { throw StorageError.conflict(operation.sourcePath) }
        }
        try await ensureRemoteParents(of: operation.destinationPath)
        if operation.kind == .restore {
            try await hydrateRestoredDocuments(operation)
            source = manifest.entries[operation.sourcePath]?.file ?? source
        }
        if operation.kind == .trash, let entry = operation.trashEntry {
            let metadataPath = entry.storageFolder + "/info.json"
            let bytes = try JSONEncoder().encode(entry)
            if let existing = manifest.entries[metadataPath]?.file {
                let saved = try await remote.download(existing, maxBytes: 1024 * 1024)
                guard (try? JSONDecoder().decode(WorkspaceTrashEntry.self, from: saved.data)) == entry else {
                    throw StorageError.conflict(metadataPath)
                }
            } else {
                let created = try await remote.upload(path: metadataPath, data: bytes, existing: nil, operationID: operation.id)
                var next = manifest
                next.entries[metadataPath] = SyncManifestEntry(file: created, blob: nil)
                try commit(next)
            }
        }
        let moved = try await remote.move(source, to: operation.destinationPath)
        guard moved.path == operation.destinationPath else { throw StorageError.invalidResponse }
        try acknowledgeMove(operation, result: moved)
    }

    func isCompletedMove(_ operation: SyncFileOperation, target: RemoteFile) async throws -> Bool {
        if let original = operation.source, target.id == original.id { return true }
        guard connection.provider == .webDAV || folder != nil,
              target.isDirectory == operation.source?.isDirectory else { return false }
        // Path-based providers have no stable ID across MOVE. Match the known
        // textual subtree, and never issue another mutation for this outcome.
        for expected in operation.expected {
            let path = operation.destinationPath + expected.path.dropFirst(operation.sourcePath.count)
            guard let current = manifest.entries[path] else { return false }
            if expected.kind == .folder {
                guard current.file.isDirectory else { return false }
            } else {
                if let blob = current.blob {
                    guard try data(blob) == Data(expected.contents.utf8) else { return false }
                } else if let remote {
                    let downloaded = try await remote.download(current.file, maxBytes: textLimit)
                    guard downloaded.data == Data(expected.contents.utf8) else { return false }
                } else { return false }
            }
        }
        return true
    }

    func acknowledgeMove(_ operation: SyncFileOperation, result: RemoteFile) throws {
        var next = manifest
        let moved = next.entries.filter { WorkspaceFileTransfer.contains($0.key, in: operation.sourcePath) }
        for (oldPath, var entry) in moved {
            next.entries.removeValue(forKey: oldPath)
            let path = operation.destinationPath + oldPath.dropFirst(operation.sourcePath.count)
            if entry.file.id == oldPath { entry.file.id = path }
            entry.file.path = path
            if oldPath == operation.sourcePath { entry.file = result }
            next.entries[path] = entry
        }
        // An edit may arrive while a MOVE request is in flight or while its
        // outcome is unknown. Keep that draft attached to the moved item. A
        // draft made during deletion stays at its original path as a recoverable
        // deletion conflict, never hidden inside the trash.
        if operation.kind == .move {
            let drafts = next.pending.filter { WorkspaceFileTransfer.contains($0.key, in: operation.sourcePath) }
            for (oldPath, var draft) in drafts {
                let path = operation.destinationPath + oldPath.dropFirst(operation.sourcePath.count)
                guard next.pending[path] == nil else { continue }
                next.pending.removeValue(forKey: oldPath)
                if var base = draft.base {
                    if base.id == oldPath { base.id = path }
                    base.path = path
                    if oldPath == operation.sourcePath { base = result }
                    draft.base = base
                }
                next.pending[path] = draft
                if var conflict = next.conflicts.removeValue(forKey: oldPath) {
                    conflict.path = path
                    next.conflicts[path] = conflict
                }
            }
        }
        let cached = next.attachments.filter { WorkspaceFileTransfer.contains($0.key, in: operation.sourcePath) }
        for (oldPath, value) in cached {
            next.attachments.removeValue(forKey: oldPath)
            next.attachments[operation.destinationPath + oldPath.dropFirst(operation.sourcePath.count)] = value
        }
        if operation.kind == .trash, let entry = operation.trashEntry {
            next.trash.removeAll { $0.id == entry.id }
            next.trash.insert(entry, at: 0)
        } else if operation.kind == .restore, let entry = operation.trashEntry {
            next.trash.removeAll { $0.id == entry.id }
        }
        next.fileOperation = nil
        next.lastSync = .now
        try commit(next)
    }

    func baselineDocuments(under root: String) throws -> [WorkspaceDocument] {
        try manifest.entries.compactMap { path, entry in
            guard WorkspaceFileTransfer.contains(path, in: root), Self.isVisible(path) else { return nil }
            if entry.file.isDirectory { return Self.document(path: path, contents: "", kind: .folder) }
            guard let kind = WorkspaceDocument.Kind(path: path), let blob = entry.blob else { return nil }
            return Self.document(path: path, contents: try text(blob), kind: kind)
        }
    }

    func finishFolderOperation(_ operation: SyncFileOperation, folder: WorkspaceFileStore) async throws {
        switch operation.kind {
        case .move:
            if manifest.entries[operation.sourcePath] == nil, let target = manifest.entries[operation.destinationPath]?.file,
               try await isCompletedMove(operation, target: target) {
                try acknowledgeMove(operation, result: target)
                return
            }
            try await folder.move(path: operation.sourcePath, to: operation.destinationPath, expected: operation.expected)
            var target = operation.source ?? RemoteFile(id: operation.destinationPath, path: operation.destinationPath,
                                                       isDirectory: false, revision: nil)
            target.id = operation.destinationPath
            target.path = operation.destinationPath
            try acknowledgeMove(operation, result: target)
        case .trash:
            let entry: WorkspaceTrashEntry
            if manifest.entries[operation.sourcePath] == nil {
                let entries = try await folder.deletedEntries()
                let matches = entries.filter { $0.originalPath == operation.sourcePath &&
                    $0.deletedAt >= (operation.trashEntry?.deletedAt ?? .distantFuture).addingTimeInterval(-1) }
                guard matches.count == 1, let found = matches.first else { throw StorageError.conflict(operation.sourcePath) }
                entry = found
            } else {
                guard let document = operation.expected.first(where: { $0.path == operation.sourcePath }) else {
                    throw StorageError.invalidResponse
                }
                entry = try await folder.trash(document: document, expected: operation.expected)
            }
            var completed = operation
            completed.trashEntry = entry
            completed.destinationPath = entry.storagePath
            let target = RemoteFile(id: entry.storagePath, path: entry.storagePath,
                                    isDirectory: entry.kind == .folder, revision: nil)
            try acknowledgeMove(completed, result: target)
        case .restore:
            guard let entry = operation.trashEntry else { throw StorageError.invalidResponse }
            let entries = try await folder.deletedEntries()
            if entries.contains(entry) { try await folder.restore(entry) }
            else if manifest.entries[entry.originalPath] == nil { throw StorageError.conflict(entry.originalPath) }
            var next = manifest
            next.trash.removeAll { $0.id == entry.id }
            next.fileOperation = nil
            try commit(next)
            try await refreshFromSource()
        case .refile: break
        }
    }

    func hydrateRestoredDocuments(_ operation: SyncFileOperation) async throws {
        guard let remote else { return }
        var hydrated: [String: SyncManifestEntry] = [:]
        for (path, entry) in manifest.entries where WorkspaceFileTransfer.contains(path, in: operation.sourcePath) {
            let restoredPath = operation.destinationPath + path.dropFirst(operation.sourcePath.count)
            guard !entry.file.isDirectory, Self.isVisible(restoredPath), WorkspaceDocument.Kind(path: restoredPath) != nil,
                  entry.blob == nil || entry.file.revision == nil else { continue }
            let result = try await remote.download(entry.file, maxBytes: textLimit)
            guard result.file.id == entry.file.id, result.file.path == path,
                  String(data: result.data, encoding: .utf8) != nil else { throw StorageError.invalidResponse }
            hydrated[path] = SyncManifestEntry(file: result.file, blob: try storeBlob(result.data))
        }
        if !hydrated.isEmpty {
            var next = manifest
            next.entries.merge(hydrated) { _, new in new }
            try commit(next)
        }
    }

    func finishRefile(_ operation: SyncFileOperation) async throws {
        guard let destinationContents = operation.destinationContents,
              let sourceContents = operation.sourceContents,
              let originalSource = operation.expected.first?.contents else { throw StorageError.invalidResponse }
        if operation.destinationCommitted,
           try manifest.entries[operation.destinationPath]?.blob.map({ try data($0) }) != Data(destinationContents.utf8) {
            var next = manifest
            next.fileOperation = nil
            try commit(next)
            throw StorageError.unsupported(String(localized: "The saved destination changed before the move finished. The source has been kept."))
        }
        if !operation.destinationCommitted {
            let current = try localData(operation.destinationPath)
            if current != Data(destinationContents.utf8) {
                guard current == operation.expectedDestination.map({ Data($0.utf8) }) else {
                    throw StorageError.conflict(operation.destinationPath)
                }
                try await writeOnline(path: operation.destinationPath, contents: destinationContents, operationID: operation.id)
            }
            var next = manifest
            next.fileOperation?.destinationCommitted = true
            try commit(next)
        }
        if operation.sourcePath != operation.destinationPath {
            let current = try localData(operation.sourcePath)
            if current != Data(sourceContents.utf8) {
                guard current == Data(originalSource.utf8) else {
                    var next = manifest
                    next.fileOperation = nil
                    try commit(next)
                    throw StorageError.unsupported(String(localized: "A copy was saved, but the source changed. Both copies have been kept."))
                }
                try await writeOnline(path: operation.sourcePath, contents: sourceContents, operationID: operation.id)
            }
        }
        var next = manifest
        next.fileOperation = nil
        next.lastSync = .now
        try commit(next)
    }

    func writeOnline(path: String, contents: String, operationID: UUID) async throws {
        let bytes = Data(contents.utf8)
        let original = manifest.entries[path]
        let file: RemoteFile
        if let remote {
            try await ensureRemoteParents(of: path)
            file = try await remote.upload(path: path, data: bytes, existing: original?.file, operationID: operationID)
        } else if let folder {
            try await folder.write(path: path, contents: contents, expectedContents: try original?.blob.map { try text($0) })
            file = RemoteFile(id: path, path: path, isDirectory: false, revision: Self.digest(bytes), size: Int64(bytes.count))
        } else { throw StorageError.rootUnavailable }
        guard file.path == path else { throw StorageError.invalidResponse }
        let blob = try storeBlob(bytes)
        var next = manifest
        next.entries[path] = SyncManifestEntry(file: file, blob: blob)
        try commit(next)
    }
}
