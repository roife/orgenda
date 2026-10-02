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
    @State private var revealedPath: String?
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
                        // Custom browser buttons need to reveal the detail
                        // explicitly when an iPad window collapses the split.
                        preferredCompactColumn = path == nil ? .sidebar : .detail
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
            revealedPath = nil
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
            revealedPath = nil
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
        return ScrollView {
            if documents.isEmpty {
                ContentUnavailableView("This folder is empty", systemImage: "folder",
                    description: Text("Files in this folder will appear here."))
                    .frame(maxWidth: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    LazyVStack(spacing: selection == nil ? 0 : 4) {
                        ForEach(documents) { document in
                            WorkspaceBrowserRow(
                                store: store,
                                document: document,
                                isSelected: selection?.wrappedValue == document.path,
                                revealedPath: $revealedPath
                            ) {
                                if let selection { selection.wrappedValue = document.path }
                                else { navigationPath.append(document.path) }
                            }
                            if selection == nil {
                                Divider().padding(.leading, 38)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
                .contentShape(Rectangle())
                .dropDestination(for: WorkspaceFileTransfer.self) { files, _ in
                    guard files.count == 1, let file = files.first,
                          store.canMoveFile(file, to: "") else { return false }
                    Task { OrgendaHaptics.result(await store.moveFile(file, to: "")) }
                    return true
                }
            }
        }
        .defaultScrollAnchor(documents.isEmpty ? .center : .top, for: .alignment)
        .background(Color.clear)
        .accessibilityIdentifier("files.browser")
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
