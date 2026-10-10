import SwiftUI
import UIKit
import CoreTransferable
import UniformTypeIdentifiers

struct WorkspaceBrowserRow: View {
    let store: WorkspaceStore
    let document: WorkspaceDocument
    var showsPath = false
    let onOpen: () -> Void
    @State private var dropTargeted = false
    @State private var deletion: WorkspaceFileTransfer?
    @State private var moveRequest: WorkspaceFileTransfer?

    var body: some View {
        NavigationLink(value: document.path) {
            WorkspaceFileRow(
                document: document, showsPath: showsPath,
                headingCount: store.parsedDocuments[document.path]?.headings.count
            )
        }
        .accessibilityIdentifier("files.open.\(document.path)")
        .contextMenu {
            Button("Open", systemImage: document.kind == .folder ? "folder" : "doc.text") {
                onOpen()
            }
            .accessibilityIdentifier("files.context.open")
            Button("Move", systemImage: "folder") {
                moveRequest = store.fileTransfer(document)
            }
            .accessibilityIdentifier("files.context.move")
            Button("Delete", systemImage: "trash", role: .destructive) {
                deletion = store.fileTransfer(document)
            }
            .accessibilityIdentifier("files.context.delete")
        } preview: {
            WorkspaceDocumentContextPreview(document: document, store: store)
        }
        .draggable(containerItemID: document.path)
        .dragConfiguration(DragConfiguration(
            operationsWithinApp: .init(allowMove: true),
            operationsOutsideApp: .init(allowCopy: false)
        ))
        .contentShape(Rectangle())
        .overlay {
            if dropTargeted && document.kind == .folder {
                RoundedRectangle(cornerRadius: 12)
                    .fill(OrgendaTheme.accent.opacity(0.10))
                    .stroke(OrgendaTheme.accent, lineWidth: 2)
                    .allowsHitTesting(false)
            }
        }
        .overlay {
            if document.kind == .folder {
                WorkspaceFolderDropTarget(store: store, path: document.path,
                                          isTargeted: $dropTargeted, onOpen: onOpen)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityActions {
            Button("Move") { moveRequest = store.fileTransfer(document) }
            Button("Delete") { deletion = store.fileTransfer(document) }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button("Delete", systemImage: "trash") {
                deletion = store.fileTransfer(document)
            }
            .tint(.red)
            .accessibilityIdentifier("files.swipe.delete")
            Button("Move", systemImage: "folder") {
                moveRequest = store.fileTransfer(document)
            }
            .tint(OrgendaTheme.accent)
            .accessibilityIdentifier("files.swipe.move")
        }
        .alert("Delete \(document.title)?", item: $deletion) { file in
            Button("Delete", role: .destructive) {
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
            .alert("Couldn't Move Item", item: $error) { _ in
                Button("OK", role: .cancel) {}
            } message: { message in Text(message) }
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
                        .orgendaEmptyState()
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
            .alert("Couldn't Restore Item", item: $error) { _ in
                Button("OK", role: .cancel) {}
            } message: { message in Text(message) }
        }
        .interactiveDismissDisabled(store.isPerformingFileAction)
    }
}

struct WorkspaceFileFeedback: ViewModifier {
    @Bindable var store: WorkspaceStore

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
            .alert("Couldn't Update Files", item: $store.fileActionError) { _ in
                Button("OK", role: .cancel) {}
            } message: { Text($0) }
    }
}

/// List owns its collection view's drop interaction, so SwiftUI row destinations
/// do not receive in-list drops. A public UIKit interaction on the folder's own
/// view preserves folder drops without inspecting or replacing List internals.
private struct WorkspaceFolderDropTarget: UIViewRepresentable {
    let store: WorkspaceStore
    let path: String
    @Binding var isTargeted: Bool
    let onOpen: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.addInteraction(UIDropInteraction(delegate: context.coordinator))
        view.addGestureRecognizer(UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.open)))
        return view
    }

    func updateUIView(_ view: UIView, context: Context) { context.coordinator.parent = self }

    final class Coordinator: NSObject, UIDropInteractionDelegate {
        var parent: WorkspaceFolderDropTarget
        init(_ parent: WorkspaceFolderDropTarget) { self.parent = parent }
        @objc func open() { parent.onOpen() }

        func dropInteraction(_ interaction: UIDropInteraction, canHandle session: UIDropSession) -> Bool {
            session.localDragSession != nil && session.items.count == 1
                && session.hasItemsConforming(toTypeIdentifiers: [UTType.orgendaWorkspaceFile.identifier])
        }

        func dropInteraction(_ interaction: UIDropInteraction, sessionDidEnter session: UIDropSession) {
            parent.isTargeted = true
        }

        func dropInteraction(_ interaction: UIDropInteraction, sessionDidUpdate session: UIDropSession) -> UIDropProposal {
            UIDropProposal(operation: dropInteraction(interaction, canHandle: session) ? .move : .forbidden)
        }

        func dropInteraction(_ interaction: UIDropInteraction, sessionDidExit session: UIDropSession) {
            parent.isTargeted = false
        }

        func dropInteraction(_ interaction: UIDropInteraction, sessionDidEnd session: UIDropSession) {
            parent.isTargeted = false
        }

        func dropInteraction(_ interaction: UIDropInteraction, performDrop session: UIDropSession) {
            parent.isTargeted = false
            guard dropInteraction(interaction, canHandle: session),
                  let provider = session.items.first?.itemProvider else { return }
            let store = parent.store
            let path = parent.path
            _ = provider.loadTransferable(type: WorkspaceFileTransfer.self) { result in
                guard case .success(let file) = result else { return }
                Task { @MainActor in
                    guard store.canMoveFile(file, to: path) else { return }
                    OrgendaHaptics.result(await store.moveFile(file, to: path))
                }
            }
        }
    }
}
