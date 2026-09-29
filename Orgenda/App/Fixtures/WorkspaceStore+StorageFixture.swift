import Foundation

#if DEBUG
extension WorkspaceStore {
    func configureStorageSyncFixture() {
        storageConnection = StorageConnection(provider: .webDAV, displayName: "Orgenda",
            accountName: "alice", rootID: "/Orgenda", endpoint: URL(string: "https://dav.example.com"))
        syncConflicts = [WorkspaceConflict(path: "notes.org", localContents: "* TODO Prepare weekly meeting\nAdd project progress.\n",
            remoteContents: "* TODO Prepare weekly meeting\nOutline discussion topics.\n", remoteRevision: "fixture-revision",
            detectedAt: .now, remoteModifiedAt: .now.addingTimeInterval(-120))]
        pendingUploadPaths = ["notes.org"]
        pendingFileCount = 1
        syncState = .conflict(1)
        fileSyncError = String(localized: "Resolve the conflicting files to finish syncing.")
        lastFileSync = .now.addingTimeInterval(-300)
    }
}
#endif
