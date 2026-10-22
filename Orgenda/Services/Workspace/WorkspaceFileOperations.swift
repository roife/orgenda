import Foundation

extension WorkspaceStore {
    func fileTransfer(_ document: WorkspaceDocument) -> WorkspaceFileTransfer {
        WorkspaceFileTransfer(workspaceID: workspaceFileSessionID, document: document,
            snapshot: documents.filter { WorkspaceFileTransfer.contains($0.path, in: document.path) })
    }

    func canMoveFile(_ transfer: WorkspaceFileTransfer, to folder: String) -> Bool {
        let source = transfer.document.path
        let parent = (source as NSString).deletingLastPathComponent
        return transfer.workspaceID == workspaceFileSessionID && folder != parent
            && (folder.isEmpty || documents.contains { $0.path == folder && $0.kind == .folder })
            && !WorkspaceFileTransfer.contains(folder, in: source)
    }

    @discardableResult
    func moveFile(_ transfer: WorkspaceFileTransfer, to folder: String) async -> Bool {
        await performFileAction { session in
            try self.validateFileTransfer(transfer)
            guard self.canMoveFile(transfer, to: folder) else { throw WorkspaceFileActionError.invalidDestination }
            let source = transfer.document.path
            let destination = (folder.isEmpty ? "" : folder + "/") + (source as NSString).lastPathComponent
            guard !self.documents.contains(where: { WorkspaceFileTransfer.contains($0.path, in: destination) }) else {
                throw WorkspaceFileActionError.nameExists
            }
            try await session.move(path: source, to: destination, expected: transfer.snapshot)
            var movedPaths: [String: String] = [:]
            let moved = self.documents.map { document in
                var result = document
                if WorkspaceFileTransfer.contains(document.path, in: source) {
                    result.path = destination + document.path.dropFirst(source.count)
                    movedPaths[document.id] = result.path
                }
                return result
            }
            self.items = self.items.map { item in
                var item = item
                if WorkspaceFileTransfer.contains(item.source.file, in: source) {
                    item.source.file = destination + item.source.file.dropFirst(source.count)
                }
                return item
            }
            for index in self.journalEntries.indices where WorkspaceFileTransfer.contains(self.journalEntries[index].source.file, in: source) {
                self.journalEntries[index].source.file = destination + self.journalEntries[index].source.file.dropFirst(source.count)
            }
            // Edits can finish while the provider is moving an item. Keep
            // those unsaved bytes and their original baseline at its new
            // path; a later save must never recreate the old source path.
            let dirty = self.dirtyFilePaths
            for path in dirty where WorkspaceFileTransfer.contains(path, in: source) {
                let target = destination + path.dropFirst(source.count)
                self.dirtyFilePaths.remove(path)
                self.dirtyFilePaths.insert(target)
                self.persistedBlobs[target] = self.persistedBlobs.removeValue(forKey: path)
                self.fileSaveErrors[target] = self.fileSaveErrors.removeValue(forKey: path)
            }
            self.documents = moved
            self.applyStorageSnapshot(try await session.snapshot())
            self.scheduleWorkspaceParse()
            let movedIDs = movedPaths.mapValues { self.documentsByPath[$0]?.id ?? $0 }
            self.pinnedDocumentIDs = self.pinnedDocumentIDs.map { movedIDs[$0] ?? $0 }
            self.recentDocumentIDs = self.recentDocumentIDs.map { movedIDs[$0] ?? $0 }
            self.saveFileShortcuts()
            if let document = self.documentsByPath[destination] {
                self.fileUndo = .move(self.fileTransfer(document), originalFolder: (source as NSString).deletingLastPathComponent)
            }
        }
    }

    @discardableResult
    func deleteFile(_ transfer: WorkspaceFileTransfer) async -> Bool {
        await performFileAction { session in
            try self.validateFileTransfer(transfer)
            let entry = try await session.trash(document: transfer.document, expected: transfer.snapshot)
            // A draft that arrived during deletion keeps its old baseline.
            // Committing it against the now-missing item records a deletion
            // conflict instead of silently resurrecting the source file.
            self.applyStorageSnapshot(try await session.snapshot())
            self.scheduleWorkspaceParse()
            self.recentlyDeleted.insert(entry, at: 0)
            self.fileUndo = .delete(entry)
        }
    }

    @discardableResult
    func restoreFile(_ entry: WorkspaceTrashEntry) async -> Bool {
        await performFileAction { session in
            guard self.recentlyDeleted.contains(entry) else { throw WorkspaceFileActionError.changed }
            guard !self.documents.contains(where: { WorkspaceFileTransfer.contains($0.path, in: entry.originalPath) }) else {
                throw WorkspaceFileActionError.nameExists
            }
            try await session.restore(entry)
            // The move already succeeded. Even if the next provider read fails,
            // do not offer a second restore or report the payload as deleted.
            self.recentlyDeleted.removeAll { $0.id == entry.id }
            self.fileUndo = nil
            self.applyStorageSnapshot(try await session.snapshot())
            self.scheduleWorkspaceParse()
        }
    }

    func undoFileAction() async {
        guard let action = fileUndo else { return }
        let succeeded: Bool
        switch action {
        case .move(let file, let parent): succeeded = await moveFile(file, to: parent)
        case .delete(let entry): succeeded = await restoreFile(entry)
        }
        if succeeded { fileUndo = nil }
    }

    func reloadDeletedFiles() async {
        guard let disk = localStore else { return }
        let session = workspaceFileSessionID
        do {
            let entries = try await disk.deletedEntries()
            if session == workspaceFileSessionID { recentlyDeleted = entries }
        } catch { fileActionError = error.localizedDescription }
    }

    private func validateFileTransfer(_ transfer: WorkspaceFileTransfer) throws {
        guard transfer.workspaceID == workspaceFileSessionID,
              documents.contains(where: { $0.path == transfer.document.path && $0.kind == transfer.document.kind }),
              WorkspaceFileTransfer.matches(transfer.snapshot, documents.filter {
                  WorkspaceFileTransfer.contains($0.path, in: transfer.document.path)
              }) else { throw WorkspaceFileActionError.changed }
    }

    private func performFileAction(_ operation: (LocalStore) async throws -> Void) async -> Bool {
        guard !isPerformingFileAction else { return false }
        isPerformingFileAction = true
        defer { isPerformingFileAction = false }
        fileActionError = nil
        await persistFileEdits()
        guard dirtyFilePaths.isEmpty, fileSaveErrors.isEmpty, !Task.isCancelled else {
            fileActionError = WorkspaceFileActionError.busy.localizedDescription
            return false
        }
        do {
            guard let localStore else { throw StorageError.rootUnavailable }
            try await operation(localStore)
            await persistFileEdits()
            await waitForWorkspaceIndex()
            Task { await self.synchronizeFiles(automatic: true, pushOnly: true) }
            return true
        } catch {
            fileActionError = error.localizedDescription
            return false
        }
    }
}
