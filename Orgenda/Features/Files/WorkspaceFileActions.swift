import SwiftUI

struct WorkspaceBrowserRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let store: WorkspaceStore
    let document: WorkspaceDocument
    var showsPath = false
    @Binding var revealedPath: String?
    let onOpen: () -> Void
    @State private var offset: CGFloat = 0
    @State private var start: CGFloat = 0
    @State private var dropTargeted = false
    @State private var deletion: WorkspaceFileTransfer?
    @State private var moveRequest: WorkspaceFileTransfer?

    var body: some View {
        ZStack {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: document.kind == .folder ? "folder.fill" : "doc.text")
                    .font(.system(size: 20))
                    .foregroundStyle(document.kind == .folder ? Color.orange : OrgendaTheme.accentText)
                    .frame(width: 24, height: 56)
                    .contentShape(Rectangle())
                    .draggable(store.fileTransfer(document))
                    .onTapGesture {
                        if offset != 0 { close() } else { onOpen() }
                    }
                    .accessibilityLabel(document.title)
                    .accessibilityIdentifier("files.drag.\(document.path)")
                Button {
                    if offset != 0 { close() } else { onOpen() }
                } label: {
                    HStack(spacing: 8) {
                        WorkspaceFileRow(
                            document: document,
                            showsPath: showsPath,
                            showsIcon: false,
                            headingCount: store.parsedDocuments[document.path]?.headings.count
                        )
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary).accessibilityHidden(true)
                    }
                    .padding(.vertical, 6)
                    .frame(minHeight: 56)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("files.open.\(document.path)")
                .contextMenu {
                    Button("Open", systemImage: document.kind == .folder ? "folder" : "doc.text") {
                        close()
                        onOpen()
                    }
                    .accessibilityIdentifier("files.context.open")
                    Button("Move", systemImage: "folder") {
                        close()
                        moveRequest = store.fileTransfer(document)
                    }
                    .accessibilityIdentifier("files.context.move")
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        close()
                        deletion = store.fileTransfer(document)
                    }
                    .accessibilityIdentifier("files.context.delete")
                } preview: {
                    WorkspaceDocumentContextPreview(document: document, store: store)
                }
            }
            .background(Color(uiColor: .systemBackground))
            .offset(x: offset)
            .gesture(OrgendaHorizontalPan(onChange: { translation, began in
                if began { start = offset; revealedPath = document.path }
                offset = min(0, max(-132, start + translation))
            }, onEnd: { translation, _, cancelled in
                withAnimation(OrgendaMotion.geometryAnimation(.selection, reduceMotion: reduceMotion)) {
                    offset = !cancelled && start + translation < -45 ? -132 : 0
                }
                if offset == 0 { revealedPath = nil }
            }))
            if offset < 0 { actions }
        }
        .clipped()
        .overlay {
            if dropTargeted && document.kind == .folder {
                RoundedRectangle(cornerRadius: 12)
                    .fill(OrgendaTheme.accent.opacity(0.10))
                    .stroke(OrgendaTheme.accent, lineWidth: 2)
                    .allowsHitTesting(false)
            }
        }
        .dropDestination(for: WorkspaceFileTransfer.self) { files, _ in
            guard document.kind == .folder, files.count == 1, let file = files.first,
                  store.canMoveFile(file, to: document.path) else { return false }
            close()
            Task { OrgendaHaptics.result(await store.moveFile(file, to: document.path)) }
            return true
        } isTargeted: { dropTargeted = $0 }
        .accessibilityActions {
            Button("Move") { moveRequest = store.fileTransfer(document) }
            Button("Delete") { deletion = store.fileTransfer(document) }
        }
        .onChange(of: revealedPath) { _, path in
            if path != document.path { withAnimation(OrgendaMotion.geometryAnimation(.selection, reduceMotion: reduceMotion)) { offset = 0 } }
        }
        .alert("Delete \(document.title)?", isPresented: Binding(
            get: { deletion != nil }, set: { if !$0 { deletion = nil } }
        ), presenting: deletion) { file in
            Button("Delete", role: .destructive) {
                close()
                Task { OrgendaHaptics.result(await store.deleteFile(file)) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text(document.kind == .folder
                 ? "This folder and everything inside will move to Recently Deleted. You can restore it later."
                 : "This file will move to Recently Deleted. You can restore it later.")
        }
        .sheet(item: $moveRequest) { file in
            WorkspaceMoveSheet(store: store, transfer: file)
                .presentationDragIndicator(.visible)
        }
    }

    private var actions: some View {
        HStack {
            Spacer(minLength: 0)
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 12) {
                    Button { close(); moveRequest = store.fileTransfer(document) } label: {
                        Image(systemName: "folder")
                            .font(.system(size: 20, weight: .medium)).foregroundStyle(.white)
                            .frame(width: 48, height: 48)
                            .glassEffect(.regular.tint(OrgendaTheme.accent).interactive(), in: .circle)
                            .contentShape(Circle())
                    }
                    .accessibilityLabel("Move")
                    .accessibilityIdentifier("files.swipe.move")
                    Button { deletion = store.fileTransfer(document) } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 20, weight: .medium)).foregroundStyle(.white)
                            .frame(width: 48, height: 48)
                            .glassEffect(.regular.tint(.red).interactive(), in: .circle)
                            .contentShape(Circle())
                    }
                    .accessibilityLabel("Delete")
                    .accessibilityIdentifier("files.swipe.delete")
                }
            }
            .opacity(min(-offset / 132, 1))
            .scaleEffect(reduceMotion ? 1 : 0.86 + 0.14 * min(-offset / 132, 1))
            .padding(.horizontal, 12)
        }
        .buttonStyle(.plain)
    }

    private func close() {
        revealedPath = nil
        withAnimation(OrgendaMotion.geometryAnimation(.selection, reduceMotion: reduceMotion)) { offset = 0 }
    }
}

private struct WorkspaceMoveSheet: View {
    @Environment(\.dismiss) private var dismiss
    let store: WorkspaceStore
    let transfer: WorkspaceFileTransfer
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    destination("", title: store.workspaceName)
                    ForEach(store.documents.filter { $0.kind == .folder }.sorted { $0.path < $1.path }) { folder in
                        destination(folder.path, title: folder.path)
                    }
                } header: { Text("Move \(transfer.document.title) to") }
            }
            .navigationTitle("Move")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark", role: .cancel) { dismiss() }
                        .labelStyle(.iconOnly)
                }
            }
            .disabled(store.isPerformingFileAction)
            .overlay { if store.isPerformingFileAction { ProgressView("Moving…").padding().background(.regularMaterial, in: Capsule()) } }
            .alert("Couldn't Move Item", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(error ?? "") }
        }
        .interactiveDismissDisabled(store.isPerformingFileAction)
    }

    private func destination(_ path: String, title: String) -> some View {
        Button {
            Task {
                let succeeded = await store.moveFile(transfer, to: path)
                OrgendaHaptics.result(succeeded)
                if succeeded { dismiss() }
                else { error = store.fileActionError; store.fileActionError = nil }
            }
        } label: { Label(title, systemImage: "folder") }
        .disabled(!store.canMoveFile(transfer, to: path))
        .accessibilityIdentifier("files.move.destination.\(path.isEmpty ? "root" : path)")
    }
}

struct WorkspaceRecentlyDeleted: View {
    @Environment(\.dismiss) private var dismiss
    let store: WorkspaceStore
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.recentlyDeleted) { entry in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.title).font(.headline)
                            Text(entry.originalPath).font(.footnote).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        Button("Restore") {
                            Task {
                                let succeeded = await store.restoreFile(entry)
                                OrgendaHaptics.result(succeeded)
                                if !succeeded { error = store.fileActionError; store.fileActionError = nil }
                            }
                        }
                        .buttonStyle(.borderless).frame(minHeight: 44)
                        .accessibilityIdentifier("files.restore.\(entry.originalPath)")
                    }
                }
            }
            .overlay {
                if store.recentlyDeleted.isEmpty {
                    ContentUnavailableView("No deleted items", systemImage: "trash", description: Text("Deleted files and folders appear here until you restore them."))
                }
            }
            .navigationTitle("Recently Deleted")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "xmark", role: .close) { dismiss() }
                        .labelStyle(.iconOnly)
                }
            }
            .task {
                await store.reloadDeletedFiles()
                if let failure = store.fileActionError { error = failure; store.fileActionError = nil }
            }
            .disabled(store.isPerformingFileAction)
            .alert("Couldn't Restore Item", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(error ?? "") }
        }
        .interactiveDismissDisabled(store.isPerformingFileAction)
    }
}

struct WorkspaceFileFeedback: ViewModifier {
    let store: WorkspaceStore

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let undo = store.fileUndo {
                    HStack(spacing: 12) {
                        Text(undo.message).font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
                        Button("Undo", systemImage: "arrow.uturn.backward") {
                            Task {
                                await store.undoFileAction()
                                OrgendaHaptics.result(store.fileActionError == nil)
                            }
                        }
                            .labelStyle(.iconOnly)
                            .font(.subheadline.bold()).frame(width: 44, height: 44)
                            .accessibilityIdentifier("files.action.undo")
                        Button("Dismiss", systemImage: "xmark") { store.fileUndo = nil }
                            .labelStyle(.iconOnly).frame(width: 44, height: 44)
                    }
                    .padding(.leading, 16).padding(.trailing, 6).background(.regularMaterial)
                }
            }
            .overlay {
                if store.isPerformingFileAction { ProgressView("Updating files…").padding().background(.regularMaterial, in: Capsule()) }
            }
            .alert("Couldn't Update Files", isPresented: Binding(
                get: { store.fileActionError != nil }, set: { if !$0 { store.fileActionError = nil } }
            )) { Button("OK", role: .cancel) {} } message: { Text(store.fileActionError ?? "") }
    }
}
