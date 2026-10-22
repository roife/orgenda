import Foundation

extension WorkspaceStore {
    nonisolated static var localWorkspaceURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Workspace", isDirectory: true)
    }

    func startWorkspace(
        defaults: UserDefaults = .standard,
        localWorkspaceURL: URL? = nil
    ) async {
        guard !hasStarted, !Task.isCancelled else { return }
        hasStarted = true
        isStartingWorkspace = true
        defer {
            if Task.isCancelled {
                hasStarted = false
            } else {
                isStartingWorkspace = false
                // A failed startup can be retried after the folder becomes available.
                hasStarted = isFolderConnected
            }
        }
        await restoreConfiguredStorage(defaults: defaults, localURL: localWorkspaceURL ?? Self.localWorkspaceURL)
        await waitForWorkspaceIndex()
    }

    func waitForFileOperation() async -> Bool {
        if let syncEngine { try? await syncEngine.waitUntilIdle() }
        return !Task.isCancelled
    }
}
