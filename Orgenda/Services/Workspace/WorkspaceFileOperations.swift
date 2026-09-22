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
        await performFileAction {
            try self.validateFileTransfer(transfer)
            guard self.canMoveFile(transfer, to: folder) else { throw WorkspaceFileActionError.invalidDestination }
            let source = transfer.document.path
            let destination = (folder.isEmpty ? "" : folder + "/") + (source as NSString).lastPathComponent
            guard !self.documents.contains(where: { WorkspaceFileTransfer.contains($0.path, in: destination) }) else {
                throw WorkspaceFileActionError.nameExists
            }
            if let disk = self.fileStore {
                try await disk.move(path: source, to: destination, expected: transfer.snapshot)
            }
            var moved = self.documents.map { document in
                var result = document
                if WorkspaceFileTransfer.contains(document.path, in: source) {
                    result.path = destination + document.path.dropFirst(source.count)
                }
                return result
            }
            self.keepDemoParentFolders(of: source, in: &moved)
            for index in self.items.indices where WorkspaceFileTransfer.contains(self.items[index].source.file, in: source) {
                self.items[index].source.file = destination + self.items[index].source.file.dropFirst(source.count)
            }
            for index in self.journalEntries.indices where WorkspaceFileTransfer.contains(self.journalEntries[index].source.file, in: source) {
                self.journalEntries[index].source.file = destination + self.journalEntries[index].source.file.dropFirst(source.count)
            }
            self.acceptFileActionDocuments(moved)
            if let document = self.documents.first(where: { $0.path == destination }) {
                self.fileUndo = .move(self.fileTransfer(document), originalFolder: (source as NSString).deletingLastPathComponent)
            }
        }
    }

    @discardableResult
    func deleteFile(_ transfer: WorkspaceFileTransfer) async -> Bool {
        await performFileAction {
            try self.validateFileTransfer(transfer)
            let entry: WorkspaceTrashEntry
            if let disk = self.fileStore {
                entry = try await disk.trash(document: transfer.document, expected: transfer.snapshot)
            } else {
                entry = WorkspaceTrashEntry(id: UUID(), originalPath: transfer.document.path,
                    title: transfer.document.title, kind: transfer.document.kind, deletedAt: .now)
                self.demoDeletedFiles[entry.id] = transfer.snapshot
            }
            var remaining = self.documents.filter {
                !WorkspaceFileTransfer.contains($0.path, in: transfer.document.path)
            }
            self.keepDemoParentFolders(of: transfer.document.path, in: &remaining)
            self.acceptFileActionDocuments(remaining)
            self.recentlyDeleted.insert(entry, at: 0)
            self.fileUndo = .delete(entry)
        }
    }

    @discardableResult
    func restoreFile(_ entry: WorkspaceTrashEntry) async -> Bool {
        await performFileAction {
            guard self.recentlyDeleted.contains(entry) else { throw WorkspaceFileActionError.changed }
            guard !self.documents.contains(where: { WorkspaceFileTransfer.contains($0.path, in: entry.originalPath) }) else {
                throw WorkspaceFileActionError.nameExists
            }
            if let disk = self.fileStore {
                try await disk.restore(entry)
                // The move already succeeded. Even if the next provider read fails,
                // do not offer a second restore or report the payload as deleted.
                self.recentlyDeleted.removeAll { $0.id == entry.id }
                self.fileUndo = nil
                self.acceptFileActionDocuments(try await disk.load())
            } else {
                guard let restored = self.demoDeletedFiles.removeValue(forKey: entry.id) else {
                    throw WorkspaceFileActionError.changed
                }
                var next = self.documents + restored
                var parent = (entry.originalPath as NSString).deletingLastPathComponent
                while !parent.isEmpty {
                    if !next.contains(where: { $0.path == parent }) {
                        next.append(WorkspaceDocument(path: parent, title: (parent as NSString).lastPathComponent, contents: "", kind: .folder))
                    }
                    parent = (parent as NSString).deletingLastPathComponent
                }
                self.acceptFileActionDocuments(next)
                self.recentlyDeleted.removeAll { $0.id == entry.id }
                self.fileUndo = nil
            }
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
        guard let disk = fileStore else { return }
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

    private func performFileAction(_ operation: () async throws -> Void) async -> Bool {
        guard !isPerformingFileAction else { return false }
        isPerformingFileAction = true
        defer { isPerformingFileAction = false }
        fileActionError = nil
        await synchronizeFiles()
        guard !isSynchronizing, dirtyFilePaths.isEmpty, fileSyncError == nil, !Task.isCancelled else {
            fileActionError = WorkspaceFileActionError.busy.localizedDescription
            return false
        }
        isSynchronizing = true
        defer { isSynchronizing = false }
        do {
            try await operation()
            await waitForWorkspaceIndex()
            lastFileSync = .now
            return true
        } catch {
            fileActionError = error.localizedDescription
            return false
        }
    }

    private func acceptFileActionDocuments(_ next: [WorkspaceDocument]) {
        fileSaveTask?.cancel()
        fileSaveTask = nil
        persistedContents = Dictionary(uniqueKeysWithValues: next.filter { $0.kind != .folder }.map { ($0.path, $0.contents) })
        acceptDiskDocuments(next)
        scheduleWorkspaceParse()
    }

    /// Demo documents may start in implicit directories. A filesystem move or
    /// deletion leaves those parents in place, even when their last child leaves.
    private func keepDemoParentFolders(of path: String, in next: inout [WorkspaceDocument]) {
        guard fileStore == nil else { return }
        var parent = (path as NSString).deletingLastPathComponent
        while !parent.isEmpty {
            if !next.contains(where: { $0.path == parent }) {
                next.append(WorkspaceDocument(path: parent, title: (parent as NSString).lastPathComponent,
                                              contents: "", kind: .folder))
            }
            parent = (parent as NSString).deletingLastPathComponent
        }
    }
}
