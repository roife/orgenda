import Foundation

extension WorkspaceStore {
    func toggleDocumentPin(_ document: WorkspaceDocument) {
        if let index = pinnedDocumentIDs.firstIndex(of: document.id) {
            pinnedDocumentIDs.remove(at: index)
        } else {
            pinnedDocumentIDs.insert(document.id, at: 0)
        }
        saveFileShortcuts()
    }

    func recordDocumentOpened(path: String) {
        guard let document = documentsByPath[path] else { return }
        recentDocumentIDs.removeAll { $0 == document.id }
        recentDocumentIDs.insert(document.id, at: 0)
        recentDocumentIDs = Array(recentDocumentIDs.prefix(10))
        saveFileShortcuts()
    }

    func saveFileShortcuts() {
        guard let connection = storageConnection else { return }
        connectionDefaults.set(["pinned": pinnedDocumentIDs, "recent": recentDocumentIDs],
                               forKey: "workspaceFileShortcuts.\(connection.id)")
    }
}
