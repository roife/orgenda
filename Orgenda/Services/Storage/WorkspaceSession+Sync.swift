import Foundation

extension WorkspaceSession {
    func synchronize() async throws {
        guard !isSynchronizing, !isPerformingFileOperation else { throw StorageError.busy }
        isSynchronizing = true
        defer { isSynchronizing = false }
        try await refreshFromSource()
        if manifest.fileOperation != nil {
            isPerformingFileOperation = true
            defer { isPerformingFileOperation = false }
            do { try await finishFileOperation() }
            catch {
                if Self.isConflict(error) || error is WorkspaceFileActionError {
                    var next = manifest
                    next.fileOperation = nil
                    try commit(next)
                }
                throw error
            }
            try await refreshFromSource()
        }
        for path in manifest.pending.keys.sorted() {
            try Task.checkCancellation()
            guard manifest.conflicts[path] == nil, let pending = manifest.pending[path] else { continue }
            let bytes = try data(pending.blob)
            do {
                let uploaded: RemoteFile
                if let remote {
                    try await ensureRemoteParents(of: path)
                    uploaded = try await remote.upload(path: path, data: bytes, existing: pending.base,
                                                       operationID: pending.operationID)
                } else if let folder {
                    guard let contents = String(data: bytes, encoding: .utf8) else { throw StorageError.invalidResponse }
                    try await folder.write(path: path, contents: contents,
                                           expectedContents: try pending.baseBlob.map { try text($0) })
                    uploaded = RemoteFile(id: path, path: path, isDirectory: false,
                                          revision: Self.digest(bytes), size: Int64(bytes.count))
                } else { throw StorageError.rootUnavailable }
                guard uploaded.path == path, !uploaded.isDirectory else { throw StorageError.invalidResponse }
                var next = manifest
                next.entries[path] = SyncManifestEntry(file: uploaded, blob: pending.blob)
                if var latest = next.pending[path] {
                    if latest.generation == pending.generation {
                        next.pending.removeValue(forKey: path)
                        next.conflicts.removeValue(forKey: path)
                    } else {
                        // A newer edit arrived during upload. Its next upload is
                        // conditional on the exact bytes just acknowledged.
                        latest.base = uploaded
                        latest.baseBlob = pending.blob
                        latest.operationID = UUID()
                        next.pending[path] = latest
                    }
                }
                try commit(next)
            } catch {
                if Self.isConflict(error) {
                    // A precondition may fail after the initial scan. Refresh
                    // the conflict's remote side without replacing the draft.
                    try? await refreshFromSource()
                }
                throw error
            }
        }
        var next = manifest
        next.lastSync = .now
        try commit(next)
        if let conflict = manifest.conflicts.keys.sorted().first { throw StorageError.conflict(conflict) }
        // Cleanup cannot turn an acknowledged save into a reported failure.
        try? collectUnreferencedBlobsIfNeeded()
    }

    /// Stage a complete, readable snapshot before changing the manifest. Any
    /// enumeration/download error leaves the previous complete snapshot intact.
    func refreshFromSource() async throws {
        var staged: [String: SyncManifestEntry] = [:]
        var cursor: String?
        if let remote {
            let scan = try await remote.scan(cursor: manifest.cursor)
            guard scan.isFullSnapshot || manifest.initialized else { throw StorageError.invalidResponse }
            var files = scan.isFullSnapshot ? [:] : manifest.entries.mapValues(\.file)
            if !scan.isFullSnapshot {
                let removedFolders = manifest.entries.values.filter {
                    $0.file.isDirectory && scan.deletedIDs.contains($0.file.id)
                }.map { $0.file.path }
                files = files.filter { path, _ in
                    !removedFolders.contains { WorkspaceFileTransfer.contains(path, in: $0) }
                }
                // Delta APIs can report only the renamed directory. Child IDs
                // remain stable, but every descendant's relative path changes.
                for changed in scan.files where changed.isDirectory {
                    guard let previous = manifest.entries.values.first(where: { $0.file.id == changed.id })?.file,
                          previous.path != changed.path else { continue }
                    let descendants = files.filter { $0.key != previous.path && WorkspaceFileTransfer.contains($0.key, in: previous.path) }
                    for (path, var child) in descendants {
                        files.removeValue(forKey: path)
                        child.path = changed.path + path.dropFirst(previous.path.count)
                        guard files[child.path] == nil else { throw StorageError.conflict(child.path) }
                        files[child.path] = child
                    }
                }
                let changedIDs = Set(scan.files.map(\.id)).union(scan.deletedIDs)
                files = files.filter { !changedIDs.contains($0.value.id) }
            }
            try validateInventory(scan.files)
            for file in scan.files { files[file.path] = file }
            try validateInventory(Array(files.values), complete: true)
            for file in files.values.sorted(by: { $0.path < $1.path }) {
                try Task.checkCancellation()
                let old = manifest.entries[file.path]
                if !file.isDirectory, Self.isVisible(file.path), WorkspaceDocument.Kind(path: file.path) != nil {
                    if let old, let blob = old.blob, old.file.id == file.id,
                       file.revision != nil, old.file.revision == file.revision {
                        staged[file.path] = SyncManifestEntry(file: file, blob: blob)
                    } else {
                        let result = try await remote.download(file, maxBytes: textLimit)
                        guard result.file.id == file.id, result.file.path == file.path,
                              !result.file.isDirectory, result.data.count <= textLimit,
                              String(data: result.data, encoding: .utf8) != nil else {
                            throw StorageError.invalidResponse
                        }
                        staged[file.path] = SyncManifestEntry(file: result.file, blob: try storeBlob(result.data))
                    }
                } else {
                    // Keep bytes already cached before a trash operation. The
                    // hidden tree is not indexed or eagerly downloaded.
                    let retained = old?.file.id == file.id && file.revision != nil && old?.file.revision == file.revision
                        ? old?.blob : nil
                    staged[file.path] = SyncManifestEntry(file: file, blob: retained)
                }
            }
            cursor = scan.cursor
        } else if let folder {
            let documents = try await folder.load()
            let files = documents.map { document in
                RemoteFile(id: document.path, path: document.path, isDirectory: document.kind == .folder,
                    revision: document.kind == .folder ? nil : Self.digest(Data(document.contents.utf8)))
            }
            try validateInventory(files, complete: true)
            for (document, file) in zip(documents, files) {
                staged[file.path] = SyncManifestEntry(file: file,
                    blob: document.kind == .folder ? nil : try storeBlob(Data(document.contents.utf8)))
            }
        } else { throw StorageError.rootUnavailable }

        // An actor can accept writes while awaiting downloads. Reconcile with
        // the latest manifest, never the manifest captured before an await.
        var next = manifest
        next.entries = staged
        next.cursor = cursor
        next.initialized = true
        next.conflicts = next.conflicts.filter { next.pending[$0.key] != nil }
        for (path, pending) in next.pending {
            let incoming = staged[path]
            if pending.requiresResolution {
                next.conflicts[path] = WorkspaceConflict(path: path, localContents: try text(pending.blob),
                    remoteContents: try incoming?.blob.map { try text($0) }, remoteRevision: incoming?.file.revision,
                    detectedAt: next.conflicts[path]?.detectedAt ?? .now, remoteModifiedAt: incoming?.file.modifiedAt)
                continue
            }
            if let incoming, !incoming.file.isDirectory, incoming.blob == pending.blob,
               pending.base == nil || incoming.file.id == pending.base?.id {
                // Includes a successful upload whose response was lost.
                next.pending.removeValue(forKey: path)
                next.conflicts.removeValue(forKey: path)
                continue
            }
            let unchanged: Bool
            if let baseline = pending.base {
                unchanged = incoming?.file.id == baseline.id && incoming?.blob == pending.baseBlob
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
            } else {
                next.conflicts[path] = WorkspaceConflict(path: path, localContents: try text(pending.blob),
                    remoteContents: try incoming?.blob.map { try text($0) }, remoteRevision: incoming?.file.revision,
                    detectedAt: next.conflicts[path]?.detectedAt ?? .now, remoteModifiedAt: incoming?.file.modifiedAt)
            }
        }
        try commit(next)
    }

    func validateInventory(_ files: [RemoteFile], complete: Bool = false) throws {
        var seenPaths: [String: String] = [:]
        var seenIDs: Set<String> = []
        for file in files {
            try StorageError.validate(path: file.path)
            let key = file.path.precomposedStringWithCanonicalMapping.lowercased()
            if seenPaths[key] != nil || !seenIDs.insert(file.id).inserted {
                var next = manifest
                let draft = try localData(file.path).flatMap { String(data: $0, encoding: .utf8) } ?? ""
                next.conflicts[file.path] = WorkspaceConflict(path: file.path, localContents: draft,
                    remoteContents: nil, remoteRevision: nil, detectedAt: .now, remoteModifiedAt: nil)
                try commit(next)
                throw StorageError.conflict(file.path)
            }
            seenPaths[key] = file.path
        }
        let paths = Dictionary(uniqueKeysWithValues: files.map { ($0.path, $0) })
        for file in files {
            var parent = (file.path as NSString).deletingLastPathComponent
            while !parent.isEmpty {
                if paths[parent]?.isDirectory == false { throw StorageError.conflict(parent) }
                if complete, paths[parent] == nil { throw StorageError.invalidResponse }
                parent = (parent as NSString).deletingLastPathComponent
            }
        }
    }

    func ensureRemoteParents(of path: String) async throws {
        guard let remote else { return }
        let components = path.split(separator: "/").dropLast()
        var parent = ""
        for component in components {
            parent = parent.isEmpty ? String(component) : parent + "/" + component
            if let existing = manifest.entries[parent] {
                guard existing.file.isDirectory else { throw StorageError.conflict(parent) }
            } else {
                let created = try await remote.createDirectory(path: parent)
                guard created.path == parent, created.isDirectory else { throw StorageError.invalidResponse }
                var next = manifest
                next.entries[parent] = SyncManifestEntry(file: created, blob: nil)
                try commit(next)
            }
        }
    }

    func resolveConflict(path: String, resolution: WorkspaceConflictResolution) async throws {
        guard !isSynchronizing, !isPerformingFileOperation else { throw StorageError.busy }
        guard let presented = manifest.conflicts[path] else { return }
        let presentedID = manifest.entries[path]?.file.id
        isSynchronizing = true
        do {
            defer { isSynchronizing = false }
            try await refreshFromSource()
            guard let pending = manifest.pending[path], let latest = manifest.conflicts[path] else {
                return
            }
            guard latest.remoteRevision == presented.remoteRevision,
                  latest.remoteContents.map({ Data($0.utf8) }) == presented.remoteContents.map({ Data($0.utf8) }),
                  Data(latest.localContents.utf8) == Data(presented.localContents.utf8),
                  manifest.entries[path]?.file.id == presentedID else { throw StorageError.conflict(path) }
            try archiveUnsynced(to: recoveryDirectory)
            var next = manifest
            switch resolution {
            case .useRemote:
                next.pending.removeValue(forKey: path)
            case .useLocal:
                var rebased = pending
                rebased.base = next.entries[path]?.file
                rebased.baseBlob = next.entries[path]?.blob
                rebased.operationID = UUID()
                rebased.generation = UUID()
                rebased.requiresResolution = false
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
                next.pending[duplicate] = SyncPendingWrite(blob: pending.blob, base: nil, baseBlob: nil)
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
