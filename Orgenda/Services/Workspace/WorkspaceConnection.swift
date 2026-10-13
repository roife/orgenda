import CryptoKit
import Foundation

extension WorkspaceStore {
    nonisolated static var localWorkspaceURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Workspace", isDirectory: true)
    }

    func startWorkspace(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        defaults: UserDefaults = .standard,
        localWorkspaceURL: URL? = nil
    ) async {
        guard !hasStarted, !Task.isCancelled else { return }
        hasStarted = true
        isStartingWorkspace = true
        let isUITestWorkspace = Self.isUITestWorkspace(arguments: arguments)
        defer {
            if Task.isCancelled {
                hasStarted = false
            } else {
                isStartingWorkspace = false
                // A failed startup can be retried after the folder becomes available.
                hasStarted = isFolderConnected || isUITestWorkspace
            }
        }
        #if DEBUG
        if isUITestWorkspace {
            await configureLaunchFixtures(arguments: arguments)
            return
        }
        #endif
        await restoreConfiguredStorage(defaults: defaults, localURL: localWorkspaceURL ?? Self.localWorkspaceURL)
        await waitForWorkspaceIndex()
    }

    static func unsavedEditsFolder(for workspaceIdentity: String) -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Unsaved Edits", isDirectory: true)
            .appendingPathComponent(recoveryDigest(workspaceIdentity), isDirectory: true)
    }

    func waitForFileOperation() async -> Bool {
        while isSynchronizing {
            do { try await Task.sleep(for: .milliseconds(25)) }
            catch { return false }
        }
        return !Task.isCancelled
    }

    static func recoveryDigest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func preserveUnsaved(_ contents: String, path: String, workspaceIdentity: String) async throws {
        let recovery = unsavedEditsFolder(for: workspaceIdentity)
        // Content addressing keeps every distinct draft, without duplicating an
        // unchanged conflict on each refresh or colliding across workspaces.
        let name = recoveryDigest(path) + "-" + recoveryDigest(contents)
        try await Task.detached(priority: .utility) {
            try FileManager.default.createDirectory(at: recovery, withIntermediateDirectories: true)
            try Data(contents.utf8).write(to: recovery.appendingPathComponent(name + ".txt"), options: .atomic)
            let metadata = ["workspace": workspaceIdentity, "path": path]
            try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
                .write(to: recovery.appendingPathComponent(name + ".json"), options: .atomic)
        }.value
    }
}
