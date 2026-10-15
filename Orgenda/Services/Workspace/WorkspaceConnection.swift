import Foundation

extension WorkspaceStore {
    nonisolated static var localWorkspaceURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Workspace", isDirectory: true)
    }

    static func startup(arguments: [String] = ProcessInfo.processInfo.arguments) -> WorkspaceStore {
        #if DEBUG
        if isDemoWorkspace(arguments: arguments) { return preview() }
        #endif
        return WorkspaceStore()
    }

    nonisolated static func isDemoWorkspace(arguments: [String] = ProcessInfo.processInfo.arguments) -> Bool {
        #if DEBUG
        arguments.contains("--demo-workspace")
        #else
        false
        #endif
    }

    func startWorkspace(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        defaults: UserDefaults = .standard,
        localWorkspaceURL: URL? = nil
    ) async {
        guard !hasStarted, !Task.isCancelled else { return }
        hasStarted = true
        isStartingWorkspace = true
        let isDemoWorkspace = Self.isDemoWorkspace(arguments: arguments)
        defer {
            if Task.isCancelled {
                hasStarted = false
            } else {
                isStartingWorkspace = false
                // A failed startup can be retried after the folder becomes available.
                hasStarted = isFolderConnected || isDemoWorkspace
            }
        }
        #if DEBUG
        if isDemoWorkspace {
            scheduleWorkspaceParse()
            await waitForWorkspaceIndex()
            return
        }
        #endif
        await restoreConfiguredStorage(defaults: defaults, localURL: localWorkspaceURL ?? Self.localWorkspaceURL)
        await waitForWorkspaceIndex()
    }

    func waitForFileOperation() async -> Bool {
        if let syncEngine { try? await syncEngine.waitUntilIdle() }
        return !Task.isCancelled
    }
}
