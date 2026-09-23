import SwiftUI
import UIKit

struct OrgDocumentView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .subheadline) private var modePickerWidth: CGFloat = 190
    let store: WorkspaceStore
    let path: String
    var searchQuery: String? = nil
    var locationRequest: WorkspaceFileNavigationRequest? = nil
    var onBack: (() -> Void)? = nil
    @State private var mode: Mode = .preview
    @State private var isOutlinePresented = false
    @State private var requestedHeadingID: String?
    @State private var editorSession = OrgEditorSession()
    @State private var requestedSourceByte: Int?
    @State private var handledLocationRequestID: UUID?
    @State private var outlineMove: OrgHeadingMove?
    @State private var handledSearchQuery: String?

    private enum Mode: Int {
        case edit
        case preview
    }

    var body: some View {
        ZStack {
            InteractiveOrgPreview(
                store: store,
                path: path,
                requestedHeadingID: $requestedHeadingID,
                isActive: mode == .preview,
                outlineMove: outlineMove
            )
            .opacity(mode == .preview ? 1 : 0)
            .zIndex(mode == .preview ? 1 : 0)
            .allowsHitTesting(mode == .preview)
            .accessibilityHidden(mode != .preview)
            HighlightedOrgEditor(
                    text: Binding(
                        get: {
                            store.documents.first { $0.path == path }?.contents ?? ""
                        },
                        set: { store.updateDocument(path: path, contents: $0) }
                    ),
                    session: editorSession,
                    isActive: mode == .edit,
                    externalRevision: store.externalDocumentRevisions[path, default: 0]
                )
                .scrollEdgeEffectStyle(.soft, for: [.top, .bottom])
                .ignoresSafeArea(.container, edges: [.top, .bottom])
                .frame(maxWidth: mode == .edit ? .infinity : 0,
                       maxHeight: mode == .edit ? .infinity : 0)
                .opacity(mode == .edit ? 1 : 0)
                .zIndex(mode == .edit ? 1 : 0)
                .allowsHitTesting(mode == .edit)
                .accessibilityHidden(mode != .edit)
        }
            .scrollEdgeEffectStyle(.soft, for: [.top, .bottom])
            .modifier(DocumentSaveFailureFeedback(store: store, path: path))
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            // Pushed pages keep the system back button and interactive edge pop.
            // Only an expanded iPad detail column needs a selection-clearing action.
            .navigationBarBackButtonHidden(showsSelectionBackButton)
            .toolbarRole(.editor)
            .toolbar(mode == .edit && editorSession.isKeyboardFocused ? .hidden : .visible, for: .tabBar)
            .toolbar {
                if showsSelectionBackButton {
                    ToolbarItem(placement: .topBarLeading) {
                        backButton
                    }
                }
                ToolbarItem(placement: .principal) {
                    ViewThatFits(in: .horizontal) {
                        modePicker
                        modeMenu
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("org.document.header")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    outlineButton
                }
            }
            .task(id: mode == .edit ? searchQuery : nil) {
                guard mode == .edit,
                      let query = searchQuery?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !query.isEmpty, handledSearchQuery != query,
                      let contents = store.documents.first(where: { $0.path == path })?.contents,
                      contents.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil else { return }
                handledSearchQuery = query
                await Task.yield()
                guard !Task.isCancelled else { return }
                editorSession.selectSearchMatch(query)
            }
            .task(id: locationRequest?.id) {
                guard let request = locationRequest, handledLocationRequestID != request.id else { return }
                await store.waitForWorkspaceIndex()
                let current = store.items.first { $0.id == request.itemID && $0.source.file == path }
                let startByte = current?.source.startByte ?? request.source.startByte
                guard !Task.isCancelled,
                      let heading = store.parsedDocuments[path]?.root.children.first(where: {
                          $0.type == "heading" && $0.startByte == startByte
                      }) else { return }
                handledLocationRequestID = request.id
                if mode == .edit {
                    editorSession.selectHeading(startByte: startByte)
                } else {
                    requestedHeadingID = heading.id
                }
            }
            .onChange(of: mode) { _, newMode in
                if newMode == .preview {
                    store.refreshDocumentIndex(path: path)
                } else {
                    Task { @MainActor in
                        await Task.yield()
                        editorSession.restorePosition()
                    }
                }
            }
            .onDisappear {
                editorSession.suspendEditing()
                store.refreshDocumentIndex(path: path)
            }
            .sheet(isPresented: $editorSession.isDatePresented, onDismiss: {
                if mode == .edit { editorSession.textView?.becomeFirstResponder() }
            }) {
                OrgInsertDateSheet(session: editorSession)
                    .presentationDetents([.large])
            }
            .sheet(isPresented: $isOutlinePresented, onDismiss: {
                if let byte = requestedSourceByte {
                    requestedSourceByte = nil
                    editorSession.selectHeading(startByte: byte)
                }
            }) {
                DocumentOutlineSheet(
                    store: store,
                    path: path,
                    isEditing: mode == .edit,
                    onSelect: navigateToHeading,
                    onMove: { outlineMove = $0 }
                )
                .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium, .large])
                .presentationDragIndicator(.visible)
            }
    }

    private var showsSelectionBackButton: Bool {
        onBack != nil && horizontalSizeClass == .regular
    }

    private var backButton: some View {
        Button {
            if let onBack {
                onBack()
            } else {
                dismiss()
            }
        } label: {
            Label("Back to Files", systemImage: "chevron.left")
        }
        .accessibilityLabel("Back to Files")
        .accessibilityIdentifier("org.document.back")
    }

    @ViewBuilder
    private var modePicker: some View {
        if dynamicTypeSize.isAccessibilitySize {
            modeMenu
        } else {
            NativeModePicker(selection: modeBinding)
                .frame(width: modePickerWidth, height: 44)
        }
    }

    private var modeMenu: some View {
        Picker("Document mode", selection: modeBinding) {
            Text("Edit").tag(Mode.edit)
            Text("Preview").tag(Mode.preview)
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .font(.subheadline.weight(.semibold))
        .frame(minHeight: 44)
        .accessibilityIdentifier("org.document.mode")
    }

    private var outlineButton: some View {
        Button {
            editorSession.suspendEditing()
            Task { @MainActor in
                store.refreshDocumentIndex(path: path)
                await store.waitForWorkspaceIndex()
                isOutlinePresented = true
            }
        } label: {
            Label("Show document outline", systemImage: "list.bullet")
        }
        .accessibilityLabel("Show document outline")
        .accessibilityIdentifier("org.document.outline")
    }

    private struct NativeModePicker: UIViewRepresentable {
        @Binding var selection: Mode

        func makeUIView(context _: Context) -> UISegmentedControl {
            let control = UISegmentedControl(items: [String(localized: "Edit"), String(localized: "Preview")])
            control.selectedSegmentIndex = selection.rawValue
            control.accessibilityLabel = String(localized: "Document mode")
            control.accessibilityIdentifier = "org.document.mode"
            let selection = $selection
            control.addAction(
                UIAction { action in
                    let control = action.sender as! UISegmentedControl
                    selection.wrappedValue = control.selectedSegmentIndex == 0
                        ? .edit
                        : .preview
                },
                for: .valueChanged
            )
            return control
        }

        func updateUIView(
            _ control: UISegmentedControl,
            context _: Context
        ) {
            control.selectedSegmentIndex = selection.rawValue
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.preferredFont(forTextStyle: .subheadline)
            ]
            control.setTitleTextAttributes(attributes, for: .normal)
            control.setTitleTextAttributes(attributes, for: .selected)
        }
    }

    private var modeBinding: Binding<Mode> {
        Binding(get: { mode }, set: { next in
            guard next != mode else { return }
            if mode == .edit { editorSession.suspendEditing() }
            mode = next
        })
    }

    private func navigateToHeading(_ node: DocumentOutlineNode) {
        if mode == .edit {
            requestedSourceByte = node.startByte
        } else {
            requestedHeadingID = node.id
        }
    }
}
