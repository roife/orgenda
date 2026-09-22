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
                NavigationSplitView {
                    workspaceList(selection: Binding(get: { selectedPath }, set: { path in
                        navigationPath = []
                        activeLocationRequest = nil
                        selectedPath = path
                    }).animation(OrgendaMotion.geometryAnimation(.selection, reduceMotion: reduceMotion)))
                        .navigationDestination(for: String.self) { path in
                            documentDestination(path: path)
                        }
                } detail: {
                    if let selectedPath {
                        NavigationStack(path: $navigationPath) {
                            documentDestination(path: selectedPath, onBack: clearSelection)
                                .navigationDestination(for: String.self) { path in
                                    documentDestination(path: path)
                                }
                        }
                        .id(selectedPath)
                    } else {
                        ContentUnavailableView("Select an Org file", systemImage: "doc.text.magnifyingglass")
                    }
                }
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
            }
            navigationRequest = nil
        }
        .onChange(of: navigationPath.last ?? selectedPath) { _, path in
            if activeLocationRequest?.source.file != path { activeLocationRequest = nil }
        }
        .onChange(of: store.documents.map(\.path)) { _, paths in
            if let selectedPath, !paths.contains(selectedPath) { self.selectedPath = nil }
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
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                LazyVStack(spacing: 0) {
                    ForEach(visibleFolderDocuments(store.documents, folderPath: "")) { document in
                        WorkspaceBrowserRow(store: store, document: document, revealedPath: $revealedPath) {
                            if let selection { selection.wrappedValue = document.path }
                            else { navigationPath.append(document.path) }
                        }
                        Divider().padding(.leading, 38)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            .contentShape(Rectangle())
            .dropDestination(for: WorkspaceFileTransfer.self) { files, _ in
                guard files.count == 1, let file = files.first,
                      store.canMoveFile(file, to: "") else { return false }
                Task { await store.moveFile(file, to: "") }
                return true
            }
        }
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
        if store.fileSyncError != nil { return String(localized: "Changes need attention") }
        if store.pendingFileCount > 0 { return String(localized: "Saving changes") }
        return store.isFolderConnected ? String(localized: "All changes saved to folder") : String(localized: "Workspace unavailable")
    }

    private func clearSelection() {
        withAnimation(OrgendaMotion.geometryAnimation(.selection, reduceMotion: reduceMotion)) {
            navigationPath = []
            activeLocationRequest = nil
            selectedPath = nil
        }
    }

    @ViewBuilder
    private func documentDestination(path: String, onBack: (() -> Void)? = nil) -> some View {
        if let document = store.documents.first(where: { $0.path == path }),
           document.kind == .folder {
            WorkspaceFolderView(store: store, folder: document) { navigationPath.append($0) }
        } else if store.documents.contains(where: { $0.path.hasPrefix(path + "/") }) {
            // Imported/demo files can have implicit parents. Include those
            // folders in the same navigation hierarchy as disk-backed folders.
            WorkspaceFolderView(store: store, folder: WorkspaceDocument(
                path: path, title: (path as NSString).lastPathComponent,
                contents: "", kind: .folder
            )) { navigationPath.append($0) }
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
