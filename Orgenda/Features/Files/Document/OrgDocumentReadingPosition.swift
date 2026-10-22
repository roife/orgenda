import Foundation

/// A source anchor shared by Preview and Edit. Scroll frames never publish
/// SwiftUI state; only the debounced checkpoint is written to local defaults.
@MainActor
final class OrgDocumentReadingPosition {
    private(set) var sourceByte: Int
    private let defaults: UserDefaults
    private let key: String
    private var saveTask: Task<Void, Never>?

    init(store: WorkspaceStore, path: String) {
        defaults = store.connectionDefaults
        let workspace = store.storageConnection?.id.uuidString ?? "demo"
        let document = store.documentsByPath[path]?.id ?? path
        key = "workspaceReadingPosition.\(workspace).\(document)"
        sourceByte = max(0, defaults.integer(forKey: key))
    }

    func record(_ byte: Int) {
        let byte = max(0, byte)
        guard byte != sourceByte else { return }
        sourceByte = byte
        saveTask?.cancel()
        saveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    func save() {
        saveTask?.cancel()
        saveTask = nil
        defaults.set(sourceByte, forKey: key)
    }
}
