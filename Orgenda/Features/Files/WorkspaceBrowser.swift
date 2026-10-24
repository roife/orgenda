import SwiftUI

struct WorkspaceFolderView: View {
    let store: WorkspaceStore
    let folder: WorkspaceDocument
    var onOpenDocument: ((String) -> Void)? = nil
    @State private var openedDocument: WorkspaceDocument?

    private var children: [WorkspaceDocument] {
        visibleFolderDocuments(store.documents, folderPath: folder.path)
    }

    var body: some View {
        Group {
            if onOpenDocument == nil {
                folderList.navigationDestination(for: String.self) { path in
                    destination(path)
                }
            } else {
                folderList
            }
        }
        .navigationDestination(item: $openedDocument) { document in
            destination(document.path)
        }
    }

    private var folderList: some View {
        List(children) { document in
            WorkspaceBrowserRow(store: store, document: document, showsPath: true) {
                if let onOpenDocument { onOpenDocument(document.path) }
                else { openedDocument = document }
            }
            .listRowInsets(.horizontal, OrgendaSpacing.pageMargin)
        }
        .dragContainer(for: WorkspaceFileTransfer.self) { (path: String) -> [WorkspaceFileTransfer] in
            return store.documents.first { $0.path == path }.map { [store.fileTransfer($0)] } ?? []
        }
        .listStyle(.plain)
        .contentMargins(.horizontal, 0, for: .scrollContent)
        .overlay {
            if children.isEmpty {
                ContentUnavailableView("This folder is empty", systemImage: "folder",
                    description: Text("Files in this folder will appear here."))
                    .orgendaEmptyState()
            }
        }
        .scrollEdgeEffectStyle(.soft, for: [.top, .bottom])
        .refreshable { await store.synchronizeFiles() }
        .accessibilityIdentifier("files.folder.browser")
        .navigationTitle(folder.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func destination(_ path: String) -> some View {
        if let document = store.documents.first(where: { $0.path == path }), document.kind == .folder {
            WorkspaceFolderView(store: store, folder: document)
        } else {
            OrgDocumentView(store: store, path: path)
        }
    }
}

struct WorkspaceFileRow: View {
    let document: WorkspaceDocument
    var showsPath = false
    var showsIcon = true
    var isPinned = false
    /// Heading count from the parsed index; when nil (not indexed yet or a
    /// non-Org file) the detail falls back to scanning the source.
    var headingCount: Int? = nil

    var body: some View {
        HStack(alignment: .top, spacing: OrgendaSpacing.contentInset) {
            if showsIcon {
                Image(systemName: document.kind == .folder ? "folder.fill" : "doc.text")
                    .font(.system(size: 20))
                    .foregroundStyle(document.kind == .folder ? OrgendaTheme.folder : OrgendaTheme.accentText)
                    .frame(width: 24, height: 26)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: OrgendaSpacing.compactInset) {
                Text(document.title)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if isPinned {
                Image(systemName: "pin.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Pinned")
            }
        }
        .padding(.vertical, OrgendaSpacing.compactInset)
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        if showsPath { return document.path }
        if document.kind == .folder { return String(localized: "Folder") }
        let count = headingCount
            ?? document.contents.split(separator: "\n").filter { $0.hasPrefix("*") }.count
        return String(localized: "\(count) headings")
    }
}

/// Keep files in implicit directories reachable while explicit subfolders own
/// their descendants. The workspace contains both flat and nested paths.
func visibleFolderDocuments(
    _ documents: [WorkspaceDocument],
    folderPath: String
) -> [WorkspaceDocument] {
    let prefix = folderPath.isEmpty ? "" : folderPath + "/"
    let descendants = documents.filter { $0.kind != .configuration && $0.path.hasPrefix(prefix) }
    let explicitFolders = Set(descendants.filter { $0.kind == .folder }.map(\.path))
    return descendants.filter { document in
        let components = document.path.dropFirst(prefix.count).split(separator: "/")
        var ancestorPath = folderPath
        for component in components.dropLast() {
            ancestorPath = ancestorPath.isEmpty ? String(component) : ancestorPath + "/\(component)"
            if explicitFolders.contains(ancestorPath) { return false }
        }
        return true
    }
}
