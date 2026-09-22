import SwiftUI

/// A tree-sitter-backed Org preview whose controls write their changes back to
/// the exact source ranges represented by the syntax tree.
struct InteractiveOrgPreview: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let store: WorkspaceStore
    let path: String
    @Binding var requestedHeadingID: String?
    var isActive = true
    var outlineMove: OrgHeadingMove?

    @State private var collapsedHeadingIDs: Set<String> = []
    @State private var pendingReplacements: [String: PendingSourceReplacement] = [:]
    @State private var planningEditor: OrgPlanningEditorPresentation?
    @State private var interactionFeedback = 0
    @State private var editorItem: OrgItem?
    @State private var scrollPosition = ScrollPosition(y: 0)
    /// Flattened outline rows, rebuilt only when the parsed document changes
    /// instead of on every body evaluation (scrolling included).
    @State private var previewRows: [OrgPreviewRow] = []
    /// Scroll offset kept outside SwiftUI state: per-frame scroll updates must
    /// not re-evaluate this body.
    @State private var readingOffset = ReadingOffsetStorage()
    @State private var headingDrag: OrgHeadingDrag?
    @State private var headingDropTarget: OrgHeadingDrop?
    @State private var pendingHeadingMove: OrgHeadingMove?
    @State private var moveError: String?

    init(
        store: WorkspaceStore,
        path: String,
        requestedHeadingID: Binding<String?>,
        isActive: Bool = true,
        outlineMove: OrgHeadingMove? = nil
    ) {
        self.store = store
        self.path = path
        _requestedHeadingID = requestedHeadingID
        self.isActive = isActive
        self.outlineMove = outlineMove
        _previewRows = State(initialValue: store.parsedDocuments[path]
            .map { OrgPreviewOutline.rows(from: $0.root.children) } ?? [])
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if store.parsedDocuments[path] != nil {
                    OrgPreviewContent(
                        rows: previewRows,
                        collapsedHeadingIDs: $collapsedHeadingIDs,
                        pendingReplacements: pendingReplacements,
                        onToggleHeading: toggleHeading,
                        onEditHeading: presentItemEditor,
                        onCycleTODO: cycleTODO,
                        onSetTODO: setTODO,
                        onToggleCheckbox: toggleCheckbox,
                        onEditPlanning: presentPlanningEditor,
                        drag: headingDrag,
                        dropTarget: $headingDropTarget,
                        onBeginDrag: beginHeadingDrag,
                        onEndDrag: endHeadingDrag,
                        onMoveHeading: moveHeading
                    )
                } else if let source = store.documents.first(where: { $0.path == path })?.contents {
                    OrgPreviewFallback(source: source)
                } else {
                    ContentUnavailableView(
                        "Preview unavailable",
                        systemImage: "doc.questionmark",
                        description: Text("The source file could not be found.")
                    )
                    .padding(.top, 64)
                }
            }
            .scrollIndicators(.hidden)
            .environment(\.orgPreviewImageContext, OrgPreviewImageContext(store: store, documentPath: path))
            .background(Color.clear)
            .scrollEdgeEffectStyle(.soft, for: [.top, .bottom])
            .accessibilityIdentifier("org.preview.scroll")
            .scrollPosition($scrollPosition)
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top
            } action: { _, offset in
                if isActive { readingOffset.value = max(0, offset) }
            }
            .onChange(of: isActive) { _, active in
                if active { scrollPosition.scrollTo(y: readingOffset.value) }
            }
            .sensoryFeedback(.selection, trigger: interactionFeedback)
            .onChange(of: requestedHeadingID, initial: true) { _, headingID in
                guard let headingID else { return }
                revealHeading(headingID, using: proxy)
            }
        }
        .sheet(item: $planningEditor) { presentation in
            OrgPlanningEditorSheet(draft: presentation.draft) { draft in
                updatePlanning(presentation.node, with: draft)
            }
            .presentationDetents(dynamicTypeSize.isAccessibilitySize
                || presentation.draft.timestamps.contains(where: { $0.recurrence != nil })
                ? [.large] : [.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .onChange(of: store.parsedDocuments[path]) { previous, document in
            previewRows = document.map { OrgPreviewOutline.rows(from: $0.root.children) } ?? []
            if let previous, let document {
                collapsedHeadingIDs = OrgHeadingContinuity.remap(
                    collapsedHeadingIDs, from: previous, to: document,
                    move: pendingHeadingMove ?? outlineMove
                )
            }
            pendingHeadingMove = nil
            endHeadingDrag()
            reconcilePendingReplacements(with: document)
        }
        .onChange(of: store.documents.first(where: { $0.path == path })?.contents) { _, source in
            // Undo can restore the original source before the parser publishes an
            // intermediate revision. Don't leave an optimistic toggle on screen.
            guard let source else { pendingReplacements.removeAll(); return }
            pendingReplacements = pendingReplacements.filter { _, pending in
                source.utf8.dropFirst(pending.startByte).prefix(pending.replacement.utf8.count)
                    .elementsEqual(pending.replacement.utf8)
            }
        }
        .sheet(item: $editorItem) { item in
            OrgItemEditor(store: store, draft: item)
        }
        .alert("Could not move heading", isPresented: Binding(
            get: { moveError != nil }, set: { if !$0 { moveError = nil } }
        )) {
            Button("OK", role: .cancel) { moveError = nil }
        } message: {
            Text(moveError ?? "")
        }
        .onChange(of: isActive) { _, active in
            if !active { endHeadingDrag() }
        }
        .onDisappear { endHeadingDrag() }
    }

    private func beginHeadingDrag(_ id: String) -> String? {
        guard isActive, pendingHeadingMove == nil, pendingReplacements.isEmpty,
              let document = store.parsedDocuments[path],
              let source = store.documents.first(where: { $0.path == path })?.contents,
              source.utf8.elementsEqual(document.root.text.utf8) else { return nil }
        let token = UUID().uuidString
        headingDrag = OrgHeadingDrag(token: token, headingID: id, document: document)
        interactionFeedback += 1
        return token
    }

    private func endHeadingDrag() {
        headingDrag = nil
        headingDropTarget = nil
    }

    private func moveHeading(_ id: String, to targetID: String, placement: OrgHeadingPlacement) -> Bool {
        guard pendingHeadingMove == nil,
              let document = headingDrag?.document ?? store.parsedDocuments[path] else { return false }
        defer { endHeadingDrag() }
        guard let move = store.moveHeading(in: document, headingID: id,
                                           targetID: targetID, placement: placement) else {
            moveError = store.operationError
            return false
        }
        pendingHeadingMove = move
        if let target = previewRows.first(where: { $0.id == targetID }) {
            collapsedHeadingIDs.subtract(target.parentHeadingIDs)
            if placement == .child { collapsedHeadingIDs.remove(targetID) }
        }
        interactionFeedback += 1
        return true
    }

    private func revealHeading(
        _ headingID: String,
        using proxy: ScrollViewProxy
    ) {
        guard store.parsedDocuments[path] != nil,
              let row = previewRows.first(where: { $0.id == headingID }) else {
            requestedHeadingID = nil
            return
        }

        withAnimation(OrgendaMotion.geometryAnimation(.content, reduceMotion: reduceMotion)) {
            collapsedHeadingIDs.subtract(Set(row.parentHeadingIDs))
        }

        Task { @MainActor in
            await Task.yield()
            withAnimation(OrgendaMotion.geometryAnimation(.content, reduceMotion: reduceMotion)) {
                proxy.scrollTo(headingID, anchor: .top)
            }
            requestedHeadingID = nil
        }
    }

    private func toggleHeading(_ id: String) {
        withAnimation(OrgendaMotion.geometryAnimation(.content, reduceMotion: reduceMotion)) {
            collapsedHeadingIDs.formSymmetricDifference([id])
        }
        interactionFeedback += 1
    }

    private func cycleTODO(_ node: ParsedOrgNode) {
        let currentText = pendingReplacements[node.id]?.replacement ?? node.text
        guard let mutation = try? OrgSourceMutation.workflowToggle(
            in: currentText,
            startByte: 0,
            endByte: currentText.utf8.count
        ) else {
            return
        }
        replace(node, with: mutation.replacement)
    }

    private func presentItemEditor(for heading: ParsedOrgNode) {
        editorItem = store.items.first {
            $0.source.file == path && $0.source.startByte == heading.startByte
        }
    }

    private func setTODO(_ node: ParsedOrgNode, to state: OrgWorkflowState) {
        guard pendingReplacements[node.id] == nil else { return }
        // The syntax node includes the spacing between the keyword and title.
        let trailingWhitespace = node.text.reversed().prefix { $0 == " " || $0 == "\t" }.reversed()
        replace(node, with: state.rawValue + String(trailingWhitespace))
    }

    private func toggleCheckbox(_ node: ParsedOrgNode) {
        let currentText = pendingReplacements[node.id]?.replacement ?? node.text
        guard let mutation = try? OrgSourceMutation.checkboxToggle(
            in: currentText,
            startByte: 0,
            endByte: currentText.utf8.count
        ) else {
            return
        }
        replace(node, with: mutation.replacement)
    }

    private func presentPlanningEditor(
        _ node: ParsedOrgNode,
        draft: OrgPlanningEntryDraft
    ) {
        planningEditor = OrgPlanningEditorPresentation(node: node, draft: draft)
    }

    private func updatePlanning(
        _ node: ParsedOrgNode,
        with draft: OrgPlanningEntryDraft
    ) -> Bool {
        if store.usesEmacsConfiguration {
            return store.applyPlanningDraft(path: path, node: node, draft: draft)
        }
        return replace(node, with: draft.source)
    }

    @discardableResult
    private func replace(_ node: ParsedOrgNode, with replacement: String) -> Bool {
        guard replacement != node.text else { return true }
        let previous = pendingReplacements[node.id]
        let pending = PendingSourceReplacement(
            startByte: node.startByte,
            expected: node.text,
            replacement: replacement
        )

        withAnimation(OrgendaMotion.animation(.selection, reduceMotion: reduceMotion)) {
            pendingReplacements[node.id] = pending
        }

        let applied = store.applySourceReplacement(
            path: path,
            startByte: node.startByte,
            endByte: node.endByte,
            expectedText: node.text,
            replacement: replacement
        )

        guard applied else {
            withAnimation(OrgendaMotion.animation(.selection, reduceMotion: reduceMotion)) {
                pendingReplacements[node.id] = previous
            }
            return false
        }

        interactionFeedback += 1
        return true
    }

    private func reconcilePendingReplacements(with document: ParsedOrgDocument?) {
        guard let document else {
            pendingReplacements.removeAll()
            return
        }

        let currentNodes = document.root.descendantsByID
        pendingReplacements = pendingReplacements.filter { id, pending in
            guard let node = currentNodes[id] else { return false }
            if node.text == pending.replacement { return false }
            return node.text == pending.expected
        }
    }

}

private struct OrgPlanningEditorPresentation: Identifiable {
    let node: ParsedOrgNode
    let draft: OrgPlanningEntryDraft

    var id: String { node.id }
}

/// Mutable scroll offset that lives outside SwiftUI's observation, so writing
/// it on every scroll frame does not schedule a body evaluation.
private final class ReadingOffsetStorage {
    var value: CGFloat = 0
}
