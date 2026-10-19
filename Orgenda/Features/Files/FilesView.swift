import SwiftUI
import UIKit

struct WorkspaceFileNavigationRequest: Identifiable, Equatable {
    let id = UUID()
    let source: SourceLocation
    let itemID: UUID

    var paths: [String] {
        let components = source.file.split(separator: "/")
        return components.indices.map { components.prefix($0 + 1).joined(separator: "/") }
    }
}

struct FilesView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let store: WorkspaceStore
    @Binding var navigationRequest: WorkspaceFileNavigationRequest?
    @State private var activeLocationRequest: WorkspaceFileNavigationRequest?
    @State private var selectedPath: String?
    @State private var isSettingsPresented = false
    @State private var isTrashPresented = false
    @State private var navigationPath: [String] = []
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var preferredCompactColumn: NavigationSplitViewColumn = .sidebar

    var body: some View {
        Group {
            if UIDevice.current.userInterfaceIdiom == .phone {
                // Keep phone push/pop transitions under one navigation stack.
                // iPad retains its split view when its window changes size.
                NavigationStack(path: $navigationPath) {
                    workspaceList(selection: nil)
                        .navigationDestination(for: String.self) { path in
                            documentDestination(path: path)
                        }
                }
            } else {
                NavigationSplitView(
                    columnVisibility: $columnVisibility,
                    preferredCompactColumn: $preferredCompactColumn
                ) {
                    workspaceList(selection: Binding(get: { selectedPath }, set: { path in
                        navigationPath = []
                        activeLocationRequest = nil
                        selectedPath = path
                    }).animation(OrgendaMotion.geometryAnimation(.selection, reduceMotion: reduceMotion)))
                        .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 400)
                } detail: {
                    NavigationStack(path: $navigationPath) {
                        Group {
                            if let selectedPath {
                                documentDestination(path: selectedPath, onBack: clearSelection)
                            } else {
                                ContentUnavailableView("Select an Org file", systemImage: "doc.text.magnifyingglass")
                                    .orgendaEmptyState()
                            }
                        }
                        .navigationDestination(for: String.self) { path in
                            documentDestination(path: path)
                        }
                    }
                }
                .navigationSplitViewStyle(.balanced)
            }
        }
        .modifier(WorkspaceFileFeedback(store: store))
        .task(id: navigationRequest?.id) {
            guard let request = navigationRequest else { return }
            // Let this tab's NavigationStack become active before applying a
            // route received while another tab's context menu was presented.
            await Task.yield()
            guard !Task.isCancelled else { return }
            isSettingsPresented = false
            isTrashPresented = false
            activeLocationRequest = request
            if UIDevice.current.userInterfaceIdiom == .phone {
                navigationPath = request.paths
            } else {
                selectedPath = request.paths.first
                navigationPath = Array(request.paths.dropFirst())
                preferredCompactColumn = .detail
            }
            navigationRequest = nil
        }
        .onChange(of: navigationPath.last ?? selectedPath) { _, path in
            if activeLocationRequest?.source.file != path { activeLocationRequest = nil }
        }
        .onChange(of: store.workspaceFileSessionID) { _, _ in
            navigationRequest = nil
            isTrashPresented = false
            clearSelection()
        }
        .onChange(of: store.documents.map(\.path)) { _, paths in
            // Implicit folders are valid routes while any descendant remains.
            func containsPath(_ path: String) -> Bool {
                paths.contains(path) || paths.contains { $0.hasPrefix(path + "/") }
            }
            if let selectedPath, !containsPath(selectedPath) {
                clearSelection()
            } else if let invalidIndex = navigationPath.firstIndex(where: { !containsPath($0) }) {
                navigationPath.removeSubrange(invalidIndex...)
            }
        }
        .sheet(isPresented: $isSettingsPresented) {
            SettingsView(store: store)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isTrashPresented) {
            WorkspaceRecentlyDeleted(store: store).presentationDragIndicator(.visible)
        }
    }

    private func workspaceList(selection: Binding<String?>?) -> some View {
        let documents = visibleFolderDocuments(store.documents, folderPath: "")
        let documentsByID = Dictionary(uniqueKeysWithValues: store.documents.map { ($0.id, $0) })
        let pinnedDocuments = store.pinnedDocumentIDs.compactMap { documentsByID[$0] }
        let recentDocuments = store.recentDocumentIDs.compactMap { documentsByID[$0] }
        let list = List(selection: selection) {
            Section {
                if pinnedDocuments.isEmpty {
                    Text("Touch and hold a file or folder to pin it here.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    browserRows(pinnedDocuments, selection: selection, showsPath: true)
                }
            } header: {
                Label("Pinned", systemImage: "pin")
            }
            Section {
                if recentDocuments.isEmpty {
                    Text("Files you open will appear here.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    browserRows(recentDocuments, selection: selection, showsPath: true)
                }
            } header: {
                Label("Recently Used", systemImage: "clock")
            }
            Section("All Files") {
                browserRows(documents, selection: selection)
                    .dropDestination(for: WorkspaceFileTransfer.self) { files, _ in
                        guard files.count == 1, let file = files.first,
                              store.canMoveFile(file, to: "") else { return }
                        Task { OrgendaHaptics.result(await store.moveFile(file, to: "")) }
                    }
            }
        }
        .dragContainer(for: WorkspaceFileTransfer.self) { (path: String) -> [WorkspaceFileTransfer] in
            return store.documents.first { $0.path == path }.map { [store.fileTransfer($0)] } ?? []
        }
        .accessibilityIdentifier("files.browser")
        return Group {
            if selection == nil { list.listStyle(.plain) }
            else { list.listStyle(.sidebar) }
        }
        .overlay {
            if documents.isEmpty {
                ContentUnavailableView("This folder is empty", systemImage: "folder",
                    description: Text("Files in this folder will appear here."))
                    .orgendaEmptyState()
            }
        }
        .background(Color.clear)
        .scrollEdgeEffectStyle(.soft, for: [.top, .bottom])
        .navigationTitle("Files")
        .refreshable { await store.synchronizeFiles() }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Recently Deleted", systemImage: "trash") { isTrashPresented = true }
                    .labelStyle(.iconOnly)
                    .accessibilityIdentifier("files.recentlyDeleted")
            }
            ToolbarItem(placement: .principal) {
                HStack(spacing: 6) {
                    Text("Files")
                        .font(.headline)
                    Image(systemName: workspaceStatusIcon)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(workspaceStatusColor)
                        .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace))
                        .accessibilityLabel(workspaceStatusLabel)
                        .accessibilityIdentifier("files.syncStatus")
                }
                .accessibilityElement(children: .contain)
                .accessibilityAddTraits(.isHeader)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isSettingsPresented = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                .accessibilityLabel("Settings")
                .accessibilityIdentifier("files.settings")
            }
        }
    }

    private func browserRows(
        _ documents: [WorkspaceDocument], selection: Binding<String?>?, showsPath: Bool = false
    ) -> some View {
        ForEach(documents) { document in
            WorkspaceBrowserRow(store: store, document: document, showsPath: showsPath) {
                if let selection {
                    selection.wrappedValue = document.path
                    preferredCompactColumn = .detail
                } else {
                    navigationPath.append(document.path)
                }
            }
            .tag(document.path)
        }
    }

    private var workspaceStatusIcon: String {
        if store.syncState == .offline { return "icloud.slash" }
        if store.fileSyncError != nil { return "exclamationmark.triangle.fill" }
        if store.pendingFileCount > 0 { return "arrow.trianglehead.2.clockwise.rotate.90" }
        return store.isFolderConnected ? "checkmark.circle.fill" : "info.circle"
    }

    private var workspaceStatusColor: Color {
        if store.fileSyncError != nil { return OrgendaTheme.overdue }
        if store.pendingFileCount > 0 { return OrgendaTheme.accentText }
        return store.isFolderConnected ? OrgendaTheme.habit : .secondary
    }

    private var workspaceStatusLabel: String {
        if store.storageConnection != nil { return store.syncState.title }
        if store.fileSyncError != nil { return String(localized: "Changes need attention") }
        if store.pendingFileCount > 0 { return String(localized: "Saving changes") }
        return store.isFolderConnected ? String(localized: "All changes saved to folder") : String(localized: "Workspace unavailable")
    }

    private func clearSelection() {
        withAnimation(OrgendaMotion.geometryAnimation(.selection, reduceMotion: reduceMotion)) {
            navigationPath = []
            activeLocationRequest = nil
            selectedPath = nil
            preferredCompactColumn = .sidebar
            columnVisibility = .all
        }
    }

    @ViewBuilder
    private func documentDestination(path: String, onBack: (() -> Void)? = nil) -> some View {
        if let document = store.documents.first(where: { $0.path == path }),
           document.kind == .folder {
            WorkspaceFolderView(store: store, folder: document) { navigationPath.append($0) }
                .id(path)
        } else if store.documents.contains(where: { $0.path.hasPrefix(path + "/") }) {
            // Imported/demo files can have implicit parents. Include those
            // folders in the same navigation hierarchy as disk-backed folders.
            WorkspaceFolderView(store: store, folder: WorkspaceDocument(
                path: path, title: (path as NSString).lastPathComponent,
                contents: "", kind: .folder
            )) { navigationPath.append($0) }
                .id(path)
        } else {
            OrgDocumentView(
                store: store,
                path: path,
                locationRequest: activeLocationRequest?.source.file == path ? activeLocationRequest : nil,
                onBack: onBack
            )
            .id(path)
        }
    }
}
