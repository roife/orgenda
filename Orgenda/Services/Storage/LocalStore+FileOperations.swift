import Foundation

extension LocalStore {
    func move(path: String, to destination: String, expected: [WorkspaceDocument]) async throws {
        try StorageError.validate(path: path)
        try StorageError.validate(path: destination)
        guard Self.isVisible(path), Self.isVisible(destination), path != destination,
              !WorkspaceFileTransfer.contains(destination, in: path) else { throw StorageError.unsafePath(destination) }
        let documents = try load().filter { WorkspaceFileTransfer.contains($0.path, in: path) }
        guard WorkspaceFileTransfer.matches(expected, documents), !documents.isEmpty else { throw StorageError.conflict(path) }
        guard view[destination] == nil else { throw WorkspaceFileActionError.nameExists }
        try enqueueOperation(WorkspaceOperation(kind: .move, sourcePath: path, destinationPath: destination,
            source: operationSource(at: path), expected: expected))
    }

    func trash(document: WorkspaceDocument, expected: [WorkspaceDocument]) async throws -> WorkspaceTrashEntry {
        try StorageError.validate(path: document.path)
        guard Self.isVisible(document.path), WorkspaceFileTransfer.matches(expected,
            try load().filter { WorkspaceFileTransfer.contains($0.path, in: document.path) }) else { throw StorageError.conflict(document.path) }
        let entry = WorkspaceTrashEntry(id: UUID(), originalPath: document.path, title: document.title,
            kind: document.kind, deletedAt: .now)
        try enqueueOperation(WorkspaceOperation(kind: .trash, sourcePath: document.path,
            destinationPath: entry.storagePath, source: operationSource(at: document.path), expected: expected,
            trashEntry: entry))
        return entry
    }

    func restore(_ entry: WorkspaceTrashEntry) async throws {
        try StorageError.validate(path: entry.originalPath)
        guard state.trash.contains(entry) else { throw WorkspaceFileActionError.changed }
        guard view[entry.originalPath] == nil else { throw WorkspaceFileActionError.nameExists }
        let records = Self.projectedRecords(state)
        let expected = try records.compactMap { path, record -> WorkspaceDocument? in
            guard WorkspaceFileTransfer.contains(path, in: entry.storagePath) else { return nil }
            guard record.kind == .folder || record.blob != nil else { throw StorageError.rootUnavailable }
            return try document(path: path, entry: record)
        }
        guard !expected.isEmpty || operationSource(at: entry.storagePath) != nil else { throw StorageError.rootUnavailable }
        try enqueueOperation(WorkspaceOperation(kind: .restore, sourcePath: entry.storagePath,
            destinationPath: entry.originalPath, source: operationSource(at: entry.storagePath), expected: expected,
            trashEntry: entry))
    }

    private func operationSource(at path: String) -> RemoteFile? {
        let underlying = underlyingPath(path)
        guard var file = state.entries[underlying]?.file else { return nil }
        if file.id == underlying { file.id = path }
        file.path = path
        return file
    }

    private func enqueueOperation(_ operation: WorkspaceOperation) throws {
        for document in operation.expected where document.kind != .folder { _ = try storeBlob(Data(document.contents.utf8)) }
        var next = state
        var queued = operation
        queued.sequence = state.commitSequence + 1
        next.operations.append(queued)
        if let entry = operation.trashEntry {
            if operation.kind == .trash { next.trash.insert(entry, at: 0) }
            if operation.kind == .restore { next.trash.removeAll { $0.id == entry.id } }
        }
        var folded = Set<String>()
        for path in Self.makeView(next).keys {
            guard folded.insert(Self.fold(path)).inserted else { throw StorageError.conflict(path) }
        }
        try commit(next)
    }

    func deletedEntries() async throws -> [WorkspaceTrashEntry] {
        switch source {
        case .folder(let folder):
            do {
                let entries = try await folder.deletedEntries()
                var next = state
                next.trash = projectedTrashEntries(entries)
                for entry in entries where next.entries[entry.storagePath] == nil {
                    next.entries[entry.storagePath] = WorkspaceFileRecord(file: RemoteFile(id: entry.storagePath,
                        path: entry.storagePath, isDirectory: entry.kind == .folder), blob: nil)
                }
                try commit(next)
                return next.trash
            } catch {
                if state.initialized, Self.isUnavailable(error) { return state.trash }
                throw error
            }
        case .remote(let remote):
            return try await remoteDeletedEntries(using: remote)
        }
    }

    private func remoteDeletedEntries(using remote: any RemoteWorkspaceBackend) async throws -> [WorkspaceTrashEntry] {
        var entries: [WorkspaceTrashEntry] = []
        do {
            for metadata in state.entries.values where metadata.file.path.hasPrefix(".orgenda-trash/")
                && metadata.file.path.hasSuffix("/info.json") {
                let parts = metadata.file.path.split(separator: "/")
                guard parts.count == 3, let id = UUID(uuidString: String(parts[1])) else { continue }
                let result = try await remote.download(metadata.file, maxBytes: 1024 * 1024)
                guard let entry = try? JSONDecoder().decode(WorkspaceTrashEntry.self, from: result.data), entry.id == id else { continue }
                try StorageError.validate(path: entry.originalPath)
                guard Self.isVisible(entry.originalPath), state.entries[entry.storagePath] != nil else { continue }
                entries.append(entry)
            }
            var next = state
            next.trash = projectedTrashEntries(entries)
            try commit(next)
            return next.trash
        } catch {
            if Self.isUnavailable(error) { return state.trash }
            throw error
        }
    }

    private func projectedTrashEntries(_ entries: [WorkspaceTrashEntry]) -> [WorkspaceTrashEntry] {
        var projected = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        // A backend listing describes physical files. The local trash view must
        // retain ordered intents that have not reached the backend yet.
        for operation in state.operations {
            guard let entry = operation.trashEntry else { continue }
            if operation.kind == .trash { projected[entry.id] = entry }
            if operation.kind == .restore { projected.removeValue(forKey: entry.id) }
        }
        return projected.values.sorted { $0.deletedAt > $1.deletedAt }
    }

    /// Commit both drafts atomically. The source draft records the exact
    /// destination blob that must be acknowledged before it can upload.
    func refile(source: WorkspaceDocument, destination: WorkspaceDocument,
                          expectedSource: String, expectedDestination: String?) async throws {
        try Self.validateVisibleDocument(source.path)
        try Self.validateVisibleDocument(destination.path)
        let sourcePath = underlyingPath(source.path)
        let destinationPath = underlyingPath(destination.path)
        guard try localData(sourcePath) == Data(expectedSource.utf8),
              try localData(destinationPath) == expectedDestination.map({ Data($0.utf8) }) else {
            throw StorageError.conflict(source.path)
        }
        let destinationBlob = try storeBlob(Data(destination.contents.utf8))
        let sourceBlob = try storeBlob(Data(source.contents.utf8))
        var next = state
        func draft(path: String, blob: String) -> WorkspaceDraft {
            var value = next.pending[path] ?? WorkspaceDraft(blob: blob, base: next.entries[path]?.file, baseBlob: next.entries[path]?.blob)
            value.blob = blob
            value.fileID = next.pending[path]?.fileID ?? next.entries[path]?.fileID ?? UUID()
            value.generation = UUID()
            return value
        }
        next.pending[destinationPath] = draft(path: destinationPath, blob: destinationBlob)
        if sourcePath != destinationPath {
            var sourceDraft = draft(path: sourcePath, blob: sourceBlob)
            sourceDraft.destinationFileID = next.pending[destinationPath]?.fileID ?? next.entries[destinationPath]?.fileID
            sourceDraft.requiredDestinationBlob = destinationBlob
            next.pending[sourcePath] = sourceDraft
        }
        try commit(next, changedPaths: [sourcePath, destinationPath])
    }

    func finishFileOperation() async throws {
        guard let operation = state.operations.first else { return }
        do {
            switch source {
            case .folder(let folder): try await finishFolderOperation(operation, folder: folder)
            case .remote(let remote): try await finishRemoteOperation(operation, remote: remote)
            }
        } catch {
            // Definitive conflicts end an operation; uncertain outcomes remain
            // journaled for recovery, whether this is the first try or a retry.
            if Self.isConflict(error) || error is WorkspaceFileActionError {
                try conflictOperation(operation)
            }
            throw error
        }
    }

    private func finishRemoteOperation(_ operation: WorkspaceOperation, remote: any RemoteWorkspaceBackend) async throws {
        let source = state.entries[operation.sourcePath]?.file
        let target = state.entries[operation.destinationPath]?.file
        if source == nil, let target, try await isCompletedMove(operation, target: target) {
            try acknowledgeMove(operation, result: target)
            return
        }
        guard var source, operation.source == nil || source.id == operation.source?.id else { throw StorageError.conflict(operation.sourcePath) }
        guard target == nil else { throw WorkspaceFileActionError.nameExists }
        if !operation.expected.isEmpty {
            let current = try baselineDocuments(under: operation.sourcePath)
            guard WorkspaceFileTransfer.matches(current, operation.expected) else { throw StorageError.conflict(operation.sourcePath) }
        }
        try await ensureRemoteParents(of: operation.destinationPath, using: remote)
        if operation.kind == .restore {
            try await hydrateRestoredDocuments(operation, remote: remote)
            let expected = try baselineDocuments(under: operation.sourcePath)
            var next = state
            guard let operationIndex = next.operations.firstIndex(where: { $0.id == operation.id }) else { return }
            next.operations[operationIndex].expected = expected
            try commit(next)
            source = state.entries[operation.sourcePath]?.file ?? source
        }
        if operation.kind == .trash, let entry = operation.trashEntry {
            let metadataPath = entry.storageFolder + "/info.json"
            let bytes = try JSONEncoder().encode(entry)
            if let existing = state.entries[metadataPath]?.file {
                let saved = try await remote.download(existing, maxBytes: 1024 * 1024)
                guard (try? JSONDecoder().decode(WorkspaceTrashEntry.self, from: saved.data)) == entry else {
                    throw StorageError.conflict(metadataPath)
                }
            } else {
                let created = try await remote.upload(path: metadataPath, data: bytes, existing: nil)
                var next = state
                next.entries[metadataPath] = WorkspaceFileRecord(file: created, blob: nil)
                try commit(next)
            }
        }
        let moved = try await remote.move(source, to: operation.destinationPath)
        guard moved.path == operation.destinationPath else { throw StorageError.invalidResponse }
        try acknowledgeMove(operation, result: moved)
    }

    func isCompletedMove(_ operation: WorkspaceOperation, target: RemoteFile) async throws -> Bool {
        guard target.isDirectory == operation.source?.isDirectory else { return false }
        // Files and WebDAV identify entries by path. Match the known
        // textual subtree, and never issue another mutation for this outcome.
        for expected in operation.expected {
            let path = operation.destinationPath + expected.path.dropFirst(operation.sourcePath.count)
            guard let current = state.entries[path] else { return false }
            if expected.kind == .folder {
                guard current.file.isDirectory else { return false }
            } else {
                if let blob = current.blob {
                    guard try data(blob) == Data(expected.contents.utf8) else { return false }
                } else if case .remote(let remote) = source {
                    let downloaded = try await remote.download(current.file, maxBytes: textLimit)
                    guard downloaded.data == Data(expected.contents.utf8) else { return false }
                } else { return false }
            }
        }
        return true
    }

    func acknowledgeMove(_ operation: WorkspaceOperation, result: RemoteFile) throws {
        var next = state
        try applyAcknowledgedMove(operation, result: result, to: &next)
        try commit(next)
    }

    func applyAcknowledgedMove(_ operation: WorkspaceOperation, result: RemoteFile, to next: inout WorkspaceState) throws {
        for expected in operation.expected {
            let path = operation.destinationPath + expected.path.dropFirst(operation.sourcePath.count)
            if next.entries[path] == nil {
                let blob = expected.kind == .folder ? nil : try storeBlob(Data(expected.contents.utf8))
                let file = path == operation.destinationPath ? result : RemoteFile(id: path, path: path,
                    isDirectory: expected.kind == .folder, revision: blob, size: Int64(expected.contents.utf8.count))
                next.entries[path] = WorkspaceFileRecord(file: file, blob: blob, fileID: expected.fileID ?? UUID())
            } else if let id = expected.fileID { next.entries[path]?.fileID = id }
        }
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
                draft.fileID = next.entries[path]?.fileID ?? draft.fileID
                if var base = draft.base {
                    if base.id == oldPath { base.id = path }
                    base.path = path
                    if oldPath == operation.sourcePath { base = result }
                    draft.base = base
                }
                next.pending[path] = draft
                if var conflict = next.conflicts.removeValue(forKey: oldPath) {
                    if !draft.requiresResolution, draft.baseBlob == next.entries[path]?.blob {
                        next.conflicts.removeValue(forKey: path)
                    } else {
                        conflict.path = path
                        conflict.remoteContents = try next.entries[path]?.blob.map { try text($0) }
                        conflict.remoteRevision = next.entries[path]?.file.revision
                        next.conflicts[path] = conflict
                    }
                }
            }
        }
        let cached = next.attachments.filter { WorkspaceFileTransfer.contains($0.key, in: operation.sourcePath) }
        for (oldPath, var value) in cached {
            next.attachments.removeValue(forKey: oldPath)
            let target = operation.destinationPath + oldPath.dropFirst(operation.sourcePath.count)
            if value.remoteID == oldPath { value.remoteID = target }
            next.attachments[target] = value
        }
        if operation.kind == .trash, let entry = operation.trashEntry {
            for path in next.pending.keys where WorkspaceFileTransfer.contains(path, in: operation.sourcePath) {
                next.pending[path]?.fileID = UUID()
                next.pending[path]?.requiresResolution = true
            }
            next.trash.removeAll { $0.id == entry.id }
            next.trash.insert(entry, at: 0)
        } else if operation.kind == .restore, let entry = operation.trashEntry {
            next.trash.removeAll { $0.id == entry.id }
        }
        next.operations.removeAll { $0.id == operation.id }
        next.lastSync = .now
    }

    func baselineDocuments(under root: String) throws -> [WorkspaceDocument] {
        try state.entries.compactMap { path, entry in
            guard WorkspaceFileTransfer.contains(path, in: root) else { return nil }
            if entry.file.isDirectory { return Self.document(path: path, contents: "", kind: .folder) }
            let trashKind = state.trash.first { $0.storagePath == path }?.kind ?? state.operations.compactMap(\.trashEntry).first { $0.storagePath == path }?.kind
            guard let kind = WorkspaceDocument.Kind(path: path) ?? trashKind, let blob = entry.blob else { return nil }
            var document = Self.document(path: path, contents: try text(blob), kind: kind)
            document.fileID = entry.fileID
            return document
        }
    }

    func finishFolderOperation(_ operation: WorkspaceOperation, folder: WorkspaceFileStore) async throws {
        switch operation.kind {
        case .move:
            if state.entries[operation.sourcePath] == nil, let target = state.entries[operation.destinationPath]?.file,
               try await isCompletedMove(operation, target: target) {
                try acknowledgeMove(operation, result: target)
                return
            }
            try await folder.move(path: operation.sourcePath, to: operation.destinationPath, expected: operation.expected)
            var target = operation.source ?? RemoteFile(id: operation.destinationPath, path: operation.destinationPath,
                                                       isDirectory: false, revision: nil)
            if target.id == operation.sourcePath { target.id = operation.destinationPath }
            target.path = operation.destinationPath
            try acknowledgeMove(operation, result: target)
        case .trash:
            let entry: WorkspaceTrashEntry
            if state.entries[operation.sourcePath] == nil {
                let entries = try await folder.deletedEntries()
                let matches = entries.filter { $0.originalPath == operation.sourcePath &&
                    $0.deletedAt >= (operation.trashEntry?.deletedAt ?? .distantFuture).addingTimeInterval(-1) }
                guard matches.count == 1, let found = matches.first else { throw StorageError.conflict(operation.sourcePath) }
                entry = found
            } else {
                guard let document = operation.expected.first(where: { $0.path == operation.sourcePath }) else {
                    throw StorageError.invalidResponse
                }
                entry = try await folder.trash(document: document, expected: operation.expected, entry: operation.trashEntry)
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
            else if state.entries[entry.originalPath] == nil { throw StorageError.conflict(entry.originalPath) }
            var target = operation.source ?? RemoteFile(id: entry.originalPath, path: entry.originalPath, isDirectory: entry.kind == .folder)
            if target.id == operation.sourcePath { target.id = entry.originalPath }
            target.path = entry.originalPath
            try acknowledgeMove(operation, result: target)
            try await refreshFromSource()
        }
    }

    private func hydrateRestoredDocuments(_ operation: WorkspaceOperation, remote: any RemoteWorkspaceBackend) async throws {
        var hydrated: [String: WorkspaceFileRecord] = [:]
        for (path, entry) in state.entries where WorkspaceFileTransfer.contains(path, in: operation.sourcePath) {
            let restoredPath = operation.destinationPath + path.dropFirst(operation.sourcePath.count)
            guard !entry.file.isDirectory, Self.isVisible(restoredPath), WorkspaceDocument.Kind(path: restoredPath) != nil,
                  entry.blob == nil || entry.file.revision == nil else { continue }
            let result = try await remote.download(entry.file, maxBytes: textLimit)
            guard result.file.id == entry.file.id, result.file.path == path,
                  String(data: result.data, encoding: .utf8) != nil else { throw StorageError.invalidResponse }
            hydrated[path] = WorkspaceFileRecord(file: result.file, blob: try storeBlob(result.data))
        }
        if !hydrated.isEmpty {
            var next = state
            next.entries.merge(hydrated) { _, new in new }
            try commit(next)
        }
    }

    private func conflictOperation(_ operation: WorkspaceOperation) throws {
        var next = state
        try recordOperationConflict(operation, in: &next)
        try commit(next)
    }

    func recordOperationConflict(_ operation: WorkspaceOperation, in next: inout WorkspaceState) throws {
        next.operations.removeAll { $0.id == operation.id }
        if !operation.expected.contains(where: { $0.kind != .folder }) {
            let path = operation.kind == .trash ? operation.sourcePath : operation.destinationPath
            next.conflicts[path] = WorkspaceConflict(path: path, localContents: "", remoteContents: nil,
                remoteRevision: next.entries[path]?.file.revision, detectedAt: .now,
                remoteModifiedAt: next.entries[path]?.file.modifiedAt, isOperation: true)
        }
        for document in operation.expected where document.kind != .folder {
            let path = operation.kind == .trash ? document.path : operation.destinationPath + document.path.dropFirst(operation.sourcePath.count)
            let blob = try next.pending[document.path]?.blob ?? storeBlob(Data(document.contents.utf8))
            let contents = try text(blob)
            if document.path != path {
                next.pending.removeValue(forKey: document.path)
                next.conflicts.removeValue(forKey: document.path)
            }
            let incoming = next.entries[path]
            var draft = next.pending[path] ?? WorkspaceDraft(blob: blob, base: incoming?.file, baseBlob: incoming?.blob)
            draft.blob = blob
            draft.fileID = incoming?.fileID ?? draft.fileID
            draft.requiresResolution = true
            next.pending[path] = draft
            next.conflicts[path] = WorkspaceConflict(path: path, localContents: contents,
                remoteContents: try incoming?.blob.map { try text($0) }, remoteRevision: incoming?.file.revision,
                detectedAt: .now, remoteModifiedAt: incoming?.file.modifiedAt)
        }
        if operation.kind == .trash, let entry = operation.trashEntry { next.trash.removeAll { $0.id == entry.id } }
        if operation.kind == .restore, let entry = operation.trashEntry, !next.trash.contains(entry) { next.trash.append(entry) }
    }
}
