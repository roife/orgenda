import Foundation

extension LocalStore {
    enum SyncMode: Sendable { case push, full }

    func synchronize(mode: SyncMode = .full, paths: Set<String>? = nil) async throws {
        guard !isSynchronizing, !isPerformingFileOperation else { throw StorageError.busy }
        isSynchronizing = true
        defer { isSynchronizing = false }
        if mode == .full || !state.initialized || state.fileOperation != nil {
            try await refreshFromSource(paths: state.fileOperation == nil ? paths : nil)
        }
        while let operation = state.fileOperation {
            let uploaded = try await pushPending(under: operation.sourcePath)
            if !uploaded.isEmpty {
                var next = state
                let source = next.entries[operation.sourcePath]?.file
                next.fileOperation?.expected = try baselineDocuments(under: operation.sourcePath)
                next.fileOperation?.source = source
                try commit(next)
            }
            isPerformingFileOperation = true
            do { try await finishFileOperation(); isPerformingFileOperation = false }
            catch { isPerformingFileOperation = false; throw error }
        }
        _ = try await pushPending()
        if let path = sourceErrors.keys.sorted().first { throw StorageError.configuration(path + ": " + (sourceErrors[path] ?? "")) }
        var next = state
        next.lastSync = .now
        try commit(next, changedPaths: [])
        if let conflict = state.conflicts.keys.min() { throw StorageError.conflict(conflict) }
        try? collectUnreferencedBlobsIfNeeded()
    }

    @discardableResult
    func pushPending(under root: String? = nil) async throws -> Set<String> {
        var uploadedPaths = Set<String>()
        var firstFailure: Error?
        var needsRefresh = false
        for path in try uploadOrder(under: root) {
            try Task.checkCancellation()
            guard state.conflicts[path] == nil, !Self.isQuarantined(path, roots: Set(sourceErrors.keys)),
                  let pending = state.pending[path] else { continue }
            do {
                if let destinationID = pending.destinationFileID {
                    guard let destination = filePathsByID[destinationID], state.pending[destination] == nil,
                          state.entries[destination]?.blob == pending.requiredDestinationBlob else { throw StorageError.conflict(path) }
                    if case .remote(let remote) = source, let file = state.entries[destination]?.file {
                        let verified = try await remote.download(file, maxBytes: textLimit)
                        guard Self.digest(verified.data) == pending.requiredDestinationBlob else { throw StorageError.conflict(path) }
                    }
                }
                let bytes = try data(pending.blob)
                let uploaded = try await upload(path: path, data: bytes, baseline: pending.base,
                    baselineBlob: pending.baseBlob)
                let file = WorkspaceFileRecord(file: uploaded, blob: pending.blob, fileID: pending.fileID)
                var latest = state.pending[path]
                if latest?.generation == pending.generation { latest = nil }
                else {
                    // New edits retain their generation and advance only to
                    // the bytes acknowledged by this conditional upload.
                    latest?.base = uploaded
                    latest?.baseBlob = pending.blob
                }
                try commitFile(path: path, file: file, draft: latest, conflict: latest == nil ? nil : state.conflicts[path])
                uploadErrors.removeValue(forKey: path)
                uploadedPaths.insert(path)
            } catch {
                if error is CancellationError { throw error }
                uploadErrors[path] = error.localizedDescription
                if firstFailure == nil { firstFailure = error }
                if Self.isConflict(error) {
                    // A precondition may fail after the initial scan. Refresh
                    // the conflict's remote side without replacing the draft.
                    needsRefresh = true
                    if pending.destinationFileID != nil {
                        var next = state
                        next.pending[path]?.requiresResolution = true
                        next.conflicts[path] = WorkspaceConflict(path: path, localContents: try text(pending.blob),
                            remoteContents: try next.entries[path]?.blob.map { try text($0) },
                            remoteRevision: next.entries[path]?.file.revision, detectedAt: .now,
                            remoteModifiedAt: next.entries[path]?.file.modifiedAt)
                        try commit(next, changedPaths: [path])
                    }
                }
                // Server-wide backoff and unavailable credentials apply to
                // every path. Other failures must not starve unrelated files.
                if Self.isUnavailable(error) { break }
                if case StorageError.throttled = error { break }
            }
        }
        if needsRefresh { try await refreshFromSource() }
        if let firstFailure { throw firstFailure }
        return uploadedPaths
    }

    private func uploadOrder(under root: String?) throws -> [String] {
        var result: [String] = [], visited = Set<String>(), visiting = Set<String>()
        func visit(_ path: String) throws {
            guard !visited.contains(path) else { return }
            guard visiting.insert(path).inserted else { throw StorageError.conflict(path) }
            if let id = state.pending[path]?.destinationFileID {
                guard let dependency = filePathsByID[id] else { throw StorageError.conflict(path) }
                if state.pending[dependency] != nil { try visit(dependency) }
            }
            visiting.remove(path)
            visited.insert(path)
            result.append(path)
        }
        for path in state.pending.keys.sorted() where root == nil || WorkspaceFileTransfer.contains(path, in: root!) { try visit(path) }
        return result
    }

    /// Stage a complete, readable snapshot before changing the state. Any
    /// enumeration/download error leaves the previous complete snapshot intact.
    func refreshFromSource(paths: Set<String>? = nil) async throws {
        var staged: [String: WorkspaceFileRecord] = [:]
        var quarantined = Set<String>()
        sourceErrors = [:]
        switch source {
        case .remote(let remote):
            let scan = try await remote.scan()
            quarantined = try validateInventory(scan.files).union(scan.unavailablePaths.keys)
            sourceErrors.merge(scan.unavailablePaths) { _, new in new }
            var downloads: [RemoteFile] = []
            for file in scan.files.sorted(by: { $0.path < $1.path }) where !Self.isQuarantined(file.path, roots: quarantined) {
                try Task.checkCancellation()
                let old = state.entries[file.path]
                if !file.isDirectory, Self.isVisible(file.path), WorkspaceDocument.Kind(path: file.path) != nil {
                    if let old, let blob = old.blob, old.file.id == file.id,
                       file.revision != nil, old.file.revision == file.revision {
                        staged[file.path] = WorkspaceFileRecord(file: file, blob: blob, fileID: old.fileID)
                    } else {
                        downloads.append(file)
                    }
                } else {
                    // Keep bytes already cached before a trash operation. The
                    // hidden tree is not indexed or eagerly downloaded.
                    let retained = old?.file.id == file.id && file.revision != nil && old?.file.revision == file.revision
                        ? old?.blob : nil
                    staged[file.path] = WorkspaceFileRecord(file: file, blob: retained, fileID: old?.fileID ?? UUID())
                }
            }
            let limit = textLimit
            try await withThrowingTaskGroup(of: (RemoteFile, RemoteDownload).self) { group in
                var iterator = downloads.makeIterator()
                for _ in 0..<4 {
                    if let file = iterator.next() { group.addTask { (file, try await remote.download(file, maxBytes: limit)) } }
                }
                while let (file, result) = try await group.next() {
                    guard result.file.id == file.id, result.file.path == file.path,
                          !result.file.isDirectory, result.data.count <= limit,
                          String(data: result.data, encoding: .utf8) != nil else { throw StorageError.invalidResponse }
                    staged[file.path] = WorkspaceFileRecord(file: result.file, blob: try storeBlob(result.data), fileID: state.entries[file.path]?.fileID ?? state.pending[file.path]?.fileID ?? UUID())
                    if let file = iterator.next() { group.addTask { (file, try await remote.download(file, maxBytes: limit)) } }
                }
            }
        case .folder(let folder):
            let inventory = try await folder.scan(known: state.entries, changedPaths: paths)
            quarantined = try validateInventory(Array(inventory.entries.values.map(\.file)))
            for bytes in inventory.changedContents.values { _ = try storeBlob(bytes) }
            staged = inventory.entries.filter { !Self.isQuarantined($0.key, roots: quarantined) }
            for (path, entry) in state.entries where path.hasPrefix(".orgenda-trash/") { staged[path] = entry }
        }

        for (path, entry) in state.entries where Self.isQuarantined(path, roots: quarantined) { staged[path] = entry }

        // Hydrate uncertain hidden MOVE destinations before taking the latest
        // local state. UI writes arriving during these awaits must be retained.
        let operations = state.operations
        for operation in operations where staged[operation.sourcePath] == nil {
            for expected in operation.expected where expected.kind != .folder {
                let path = operation.destinationPath + expected.path.dropFirst(operation.sourcePath.count)
                guard let observed = staged[path], observed.blob == nil else { continue }
                let bytes: Data
                switch source {
                case .remote(let remote): bytes = try await remote.download(observed.file, maxBytes: textLimit).data
                case .folder(let folder): bytes = try await folder.readImageData(path: path, maxBytes: textLimit)
                }
                staged[path]?.blob = try storeBlob(bytes)
            }
        }

        // An actor can accept writes while awaiting downloads. Reconcile with
        // the latest state, never the state captured before an await.
        var next = state
        reconcileRenames(staged: &staged, next: &next)
        next.entries = staged
        try reconcileObservedOperations(in: &next)
        staged = next.entries
        next.initialized = true
        next.conflicts = next.conflicts.filter { next.pending[$0.key] != nil || $0.value.isOperation }
        for (path, pending) in next.pending {
            let incoming = staged[path]
            let sameIdentity: Bool
            if case .folder = source { sameIdentity = true }
            else { sameIdentity = incoming?.file.id == pending.base?.id }
            if !pending.requiresResolution, let incoming, !incoming.file.isDirectory, incoming.blob == pending.blob,
               pending.base == nil || sameIdentity {
                // Includes a successful upload whose response was lost.
                next.pending.removeValue(forKey: path)
                next.conflicts.removeValue(forKey: path)
                continue
            }
            let unchanged: Bool
            if pending.requiresResolution {
                unchanged = false
            } else if let baseline = pending.base {
                unchanged = (sameIdentity || incoming?.file.id == baseline.id) && incoming?.blob == pending.baseBlob
                    && incoming?.file.isDirectory == false
            } else {
                unchanged = incoming == nil
            }
            if unchanged {
                var rebased = pending
                rebased.base = incoming?.file
                rebased.baseBlob = incoming?.blob
                next.pending[path] = rebased
                next.conflicts.removeValue(forKey: path)
            } else if !pending.requiresResolution, pending.destinationFileID == nil,
                      let baseBlob = pending.baseBlob, let incomingBlob = incoming?.blob,
                      let merged = WorkspaceTextMerge.merge(base: try text(baseBlob), local: try text(pending.blob), remote: try text(incomingBlob)) {
                var rebased = pending
                rebased.blob = try storeBlob(Data(merged.utf8))
                rebased.base = incoming?.file
                rebased.baseBlob = incomingBlob
                rebased.generation = UUID()
                next.pending[path] = rebased
                next.conflicts.removeValue(forKey: path)
            } else {
                next.conflicts[path] = WorkspaceConflict(path: path, localContents: try text(pending.blob),
                    remoteContents: try incoming?.blob.map { try text($0) }, remoteRevision: incoming?.file.revision,
                    detectedAt: next.conflicts[path]?.detectedAt ?? .now, remoteModifiedAt: incoming?.file.modifiedAt)
            }
        }
        try commit(next)
    }

    private static func isQuarantined(_ path: String, roots: Set<String>) -> Bool {
        let folded = fold(path)
        return roots.contains { WorkspaceFileTransfer.contains(folded, in: fold($0)) }
    }

    /// A lost MOVE response can make both the observed destination and the
    /// still-queued draft refer to one logical file. Reconcile that identity in
    /// the same transaction as the pull, before publishing or indexing paths.
    private func reconcileObservedOperations(in next: inout WorkspaceState) throws {
        while let operation = next.fileOperation, let target = next.entries[operation.destinationPath] {
            var completed = next.entries[operation.sourcePath] == nil && !operation.expected.isEmpty
            if completed {
                for expected in operation.expected {
                    let path = operation.destinationPath + expected.path.dropFirst(operation.sourcePath.count)
                    guard let observed = next.entries[path] else { completed = false; break }
                    if expected.kind == .folder {
                        if !observed.file.isDirectory { completed = false; break }
                    } else {
                        let blob = observed.blob
                        if blob != Self.digest(Data(expected.contents.utf8)) { completed = false; break }
                    }
                }
            }
            if completed { try applyAcknowledgedMove(operation, result: target.file, to: &next) }
            else { try recordOperationConflict(operation, in: &next) }
        }
    }

    @discardableResult
    func validateInventory(_ files: [RemoteFile]) throws -> Set<String> {
        var seenPaths: [String: String] = [:], seenIDs: [String: String] = [:], rejected = Set<String>()
        for file in files {
            try StorageError.validate(path: file.path)
            let key = Self.fold(file.path)
            if let previous = seenPaths[key] { rejected.formUnion([previous, file.path]) }
            if let previous = seenIDs[file.id] { rejected.formUnion([previous, file.path]) }
            seenPaths[key] = file.path
            seenIDs[file.id] = file.path
        }
        let paths = Dictionary(files.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
        for file in files {
            var parent = (file.path as NSString).deletingLastPathComponent
            while !parent.isEmpty {
                if paths[parent]?.isDirectory != true { rejected.insert(parent) }
                parent = (parent as NSString).deletingLastPathComponent
            }
        }
        for path in rejected { sourceErrors[path] = StorageError.invalidResponse.localizedDescription }
        return rejected
    }

    /// Path-based DAV servers cannot prove every rename. Preserve identity only
    /// for an unambiguous unchanged revision/blob, or a backend's stable ID.
    private func reconcileRenames(staged: inout [String: WorkspaceFileRecord], next: inout WorkspaceState) {
        guard next.operations.isEmpty else { return }
        func key(_ entry: WorkspaceFileRecord) -> String? {
            if entry.file.id != entry.file.path { return "id:" + entry.file.id }
            guard !entry.file.isDirectory, let revision = entry.file.revision, let blob = entry.blob else { return nil }
            return "version:" + revision + ":" + blob
        }
        let oldGroups = Dictionary(grouping: state.entries.compactMap { path, entry in key(entry).map { ($0, path) } }, by: { $0.0 })
        let newGroups = Dictionary(grouping: staged.compactMap { path, entry in key(entry).map { ($0, path) } }, by: { $0.0 })
        for (identity, old) in oldGroups where old.count == 1 {
            guard let incoming = newGroups[identity], incoming.count == 1 else { continue }
            let source = old[0].1, target = incoming[0].1
            guard source != target, staged[source] == nil, state.entries[target] == nil,
                  next.pending[target] == nil, let entry = state.entries[source] else { continue }
            staged[target]?.fileID = entry.fileID
            if var draft = next.pending.removeValue(forKey: source) {
                draft.base = staged[target]?.file
                next.pending[target] = draft
            }
            if var conflict = next.conflicts.removeValue(forKey: source) {
                conflict.path = target
                next.conflicts[target] = conflict
            }
        }
    }

    func upload(path: String, data bytes: Data, baseline: RemoteFile?, baselineBlob: String?) async throws -> RemoteFile {
        switch source {
        case .remote(let remote):
            try await ensureRemoteParents(of: path, using: remote)
            let file = try await remote.upload(path: path, data: bytes, existing: baseline)
            guard file.path == path, !file.isDirectory else { throw StorageError.invalidResponse }
            return file
        case .folder(let folder):
            guard let contents = String(data: bytes, encoding: .utf8) else { throw StorageError.invalidResponse }
            return try await folder.write(path: path, contents: contents,
                expectedContents: try baselineBlob.map { try text($0) })
        }
    }

    func ensureRemoteParents(of path: String, using remote: any RemoteWorkspaceBackend) async throws {
        let components = path.split(separator: "/").dropLast()
        var parent = ""
        for component in components {
            parent = parent.isEmpty ? String(component) : parent + "/" + component
            if let existing = state.entries[parent] {
                guard existing.file.isDirectory else { throw StorageError.conflict(parent) }
            } else {
                let created = try await remote.createDirectory(path: parent)
                guard created.path == parent, created.isDirectory else { throw StorageError.invalidResponse }
                var next = state
                next.entries[parent] = WorkspaceFileRecord(file: created, blob: nil)
                try commit(next)
            }
        }
    }

    func resolveConflict(path visiblePath: String, resolution: WorkspaceConflictResolution) async throws {
        guard !isSynchronizing, !isPerformingFileOperation else { throw StorageError.busy }
        let path = underlyingPath(visiblePath)
        guard let presented = state.conflicts[path] else { return }
        if presented.isOperation {
            guard resolution == .useRemote else {
                throw StorageError.unsupported(String(localized: "The folder operation could not be completed. Keep the existing folders, then choose another destination and try again."))
            }
            var next = state
            next.conflicts.removeValue(forKey: path)
            try commit(next)
            return
        }
        let presentedID = state.entries[path]?.file.id
        isSynchronizing = true
        do {
            defer { isSynchronizing = false }
            try await refreshFromSource()
            guard let pending = state.pending[path], let latest = state.conflicts[path] else {
                return
            }
            guard latest.remoteRevision == presented.remoteRevision,
                  latest.remoteContents.map({ Data($0.utf8) }) == presented.remoteContents.map({ Data($0.utf8) }),
                  Data(latest.localContents.utf8) == Data(presented.localContents.utf8),
                  state.entries[path]?.file.id == presentedID else { throw StorageError.conflict(path) }
            try archiveUnsynced(to: recoveryDirectory)
            var next = state
            switch resolution {
            case .useRemote:
                next.pending.removeValue(forKey: path)
            case .useLocal:
                var rebased = pending
                rebased.base = next.entries[path]?.file
                rebased.baseBlob = next.entries[path]?.blob
                rebased.generation = UUID()
                rebased.requiresResolution = false
                rebased.destinationFileID = nil
                rebased.requiredDestinationBlob = nil
                next.pending[path] = rebased
            case .keepBoth:
                let ext = (path as NSString).pathExtension
                let stem = (path as NSString).deletingPathExtension
                var duplicate = stem + " (conflict " + String(UUID().uuidString.prefix(8)) + ")" + (ext.isEmpty ? "" : "." + ext)
                while next.entries[duplicate] != nil || next.pending[duplicate] != nil {
                    duplicate = stem + " (conflict " + UUID().uuidString + ")" + (ext.isEmpty ? "" : "." + ext)
                }
                // Recovery JSON must remain readable/uploadable through the
                // existing text pipeline without becoming another config.
                if path == "config.json" {
                    duplicate = "orgenda/Unsaved Edits/config-" + UUID().uuidString + ".md"
                }
                next.pending[duplicate] = WorkspaceDraft(blob: pending.blob, base: nil, baseBlob: nil)
                next.pending.removeValue(forKey: path)
            }
            next.conflicts.removeValue(forKey: path)
            try commit(next)
        }
        try await synchronize()
    }

    static func isConflict(_ error: Error) -> Bool {
        if case .conflict = error as? StorageError { return true }
        if case .conflict = error as? WorkspaceFileStore.Failure { return true }
        return false
    }
}
