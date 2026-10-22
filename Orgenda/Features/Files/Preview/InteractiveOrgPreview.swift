import SwiftUI

/// A tree-sitter-backed Org preview whose controls write their changes back to
/// the exact source ranges represented by the syntax tree.
struct InteractiveOrgPreview: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let store: WorkspaceStore
    let path: String
    @Binding var requestedHeadingID: String?
    @Binding var requestedSourceByte: Int?
    let onReadingPositionChange: (Int) -> Void
    var isActive = true
    var outlineMove: OrgHeadingMove?
    var searchQuery: String?

    @State private var handledSearchQuery: String?
    @State private var highlightedSearchQuery = ""
    @State private var collapsedHeadingIDs: Set<String> = []
    @State private var pendingReplacements: [String: PendingSourceReplacement] = [:]
    @State private var planningEditor: OrgPlanningEditorPresentation?
    @State private var interactionFeedback = 0
    @State private var editorItem: OrgItem?
    @State private var proposedState: OrgWorkflowState?
    @State private var scrollPosition = ScrollPosition(y: 0)
    /// Final presentation rows, including math grouping, rebuilt only when
    /// the parsed document changes rather than on disclosure or drag updates.
    @State private var previewRows: [OrgPreviewRow] = []
    @State private var outlineCache = OrgPreviewOutline.Cache()
    /// Scroll offset kept outside SwiftUI state: per-frame scroll updates must
    /// not re-evaluate this body.
    @State private var readingTracker = OrgPreviewReadingTracker()
    @State private var headingDrag: OrgHeadingDrag?
    @State private var headingDropTarget: OrgHeadingDrop?
    @State private var pendingHeadingMove: OrgHeadingMove?
    @State private var moveError: String?

    init(
        store: WorkspaceStore,
        path: String,
        requestedHeadingID: Binding<String?>,
        requestedSourceByte: Binding<Int?>,
        onReadingPositionChange: @escaping (Int) -> Void,
        isActive: Bool = true,
        outlineMove: OrgHeadingMove? = nil,
        searchQuery: String? = nil
    ) {
        self.store = store
        self.path = path
        _requestedHeadingID = requestedHeadingID
        _requestedSourceByte = requestedSourceByte
        self.onReadingPositionChange = onReadingPositionChange
        self.isActive = isActive
        self.outlineMove = outlineMove
        self.searchQuery = searchQuery
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
                        onMoveHeading: moveHeading,
                        onRowGeometryChange: updateRowGeometry
                    )
                    .environment(\.orgWorkflow, store.workflow(for: path))
                } else if let source = store.documents.first(where: { $0.path == path })?.contents {
                    OrgPreviewFallback(source: source)
                } else {
                    ContentUnavailableView(
                        "Preview unavailable",
                        systemImage: "doc.questionmark",
                        description: Text("The source file could not be found.")
                    )
                }
            }
            .defaultScrollAnchor(
                store.parsedDocuments[path] == nil && !store.documents.contains(where: { $0.path == path })
                    ? .center : .top,
                for: .alignment
            )
            .scrollIndicators(.hidden)
            .environment(\.orgPreviewImageContext, OrgPreviewImageContext(store: store, documentPath: path))
            .environment(\.orgPreviewSearchQuery, highlightedSearchQuery)
            .background(Color.clear)
            .scrollEdgeEffectStyle(.soft, for: [.top, .bottom])
            .accessibilityIdentifier("org.preview.scroll")
            .scrollPosition($scrollPosition)
            .onScrollGeometryChange(for: ReadingGeometry.self) { geometry in
                ReadingGeometry(offset: geometry.contentOffset.y + geometry.contentInsets.top,
                                height: geometry.containerSize.height)
            } action: { _, geometry in
                readingTracker.offset = max(0, geometry.offset)
                readingTracker.viewportHeight = geometry.height
                recordReadingPosition()
            }
            .onScrollPhaseChange { _, phase in
                if phase == .tracking || phase == .interacting {
                    requestedSourceByte = nil
                    readingTracker.isTracking = true
                }
            }
            .task(id: ReadingRequest(byte: requestedSourceByte, active: isActive)) {
                guard isActive, requestedSourceByte != nil else { return }
                readingTracker.isTracking = false
                await store.waitForWorkspaceIndex()
                guard !Task.isCancelled, requestedHeadingID == nil else { return }
                restoreReadingPosition(using: proxy)
            }
            .task(id: SearchRequest(query: searchQuery, ready: isActive && !previewRows.isEmpty)) {
                revealSearchMatch()
            }
            .task(id: SearchRequest(query: highlightedSearchQuery, ready: isActive && requestedSourceByte == nil)) {
                guard isActive, requestedSourceByte == nil, !highlightedSearchQuery.isEmpty else { return }
                do { try await Task.sleep(for: .seconds(2)) }
                catch { return }
                highlightedSearchQuery = ""
            }
            .onChange(of: previewRows.map(\.id)) { _, _ in
                if let headingID = requestedHeadingID {
                    revealHeading(headingID, using: proxy)
                } else if isActive, requestedSourceByte != nil {
                    restoreReadingPosition(using: proxy)
                }
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
        .onChange(of: store.parsedDocuments[path], initial: true) { previous, document in
            previewRows = outlineCache.rows(from: document?.root.children ?? [])
            // Stable row IDs can retain their geometry when only source offsets move.
            // Refresh the associated source nodes even if no geometry callback fires.
            readingTracker.rows = Dictionary(uniqueKeysWithValues: previewRows.compactMap { row in
                readingTracker.rows[row.id].map { (row.id, OrgPreviewReadingTracker.Row(node: row.node, frame: $0.frame)) }
            })
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
            OrgItemEditor(store: store, draft: item, proposedState: proposedState)
                .onDisappear { proposedState = nil }
        }
        .alert("Could not move heading", item: $moveError) { _ in
            Button("OK", role: .cancel) { moveError = nil }
        } message: { message in
            Text(message)
        }
        .onChange(of: isActive) { _, active in
            if !active {
                endHeadingDrag()
                highlightedSearchQuery = ""
            }
        }
        .onDisappear {
            endHeadingDrag()
            highlightedSearchQuery = ""
        }
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

        requestedSourceByte = nil
        readingTracker.isTracking = false
        onReadingPositionChange(row.node.startByte)

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

    private struct ReadingRequest: Equatable {
        let byte: Int?
        let active: Bool
    }

    private struct ReadingGeometry: Equatable {
        let offset: CGFloat
        let height: CGFloat
    }

    private struct SearchRequest: Equatable {
        let query: String?
        let ready: Bool
    }

    private func revealSearchMatch() {
        guard isActive, !previewRows.isEmpty,
              let query = searchQuery?.trimmingCharacters(in: .whitespacesAndNewlines),
              !query.isEmpty, handledSearchQuery != query,
              let source = store.parsedDocuments[path]?.root.text,
              let match = source.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) else { return }
        let byte = source[..<match.lowerBound].utf8.count
        guard let row = readingRow(for: byte) else { return }
        handledSearchQuery = query
        readingTracker.isTracking = false
        collapsedHeadingIDs.subtract(row.parentHeadingIDs)
        requestedHeadingID = nil
        requestedSourceByte = byte
        highlightedSearchQuery = query
        onReadingPositionChange(byte)
    }

    private func readingRow(for byte: Int) -> OrgPreviewRow? {
        let rows = previewRows.filter { $0.node.type != "blank_line" }
        return rows.first { $0.node.startByte <= byte && byte < $0.node.endByte }
            ?? rows.filter { $0.node.startByte <= byte }.max { $0.node.startByte < $1.node.startByte }
            ?? rows.first
    }

    private func restoreReadingPosition(using proxy: ScrollViewProxy) {
        guard let byte = requestedSourceByte, let row = readingRow(for: byte) else { return }
        readingTracker.isTracking = false
        readingTracker.restoreRowID = row.id
        collapsedHeadingIDs.subtract(row.parentHeadingIDs)
        // Resolve the lazy row first, then use its measured height to restore
        // a position inside long paragraphs, tables, or source blocks.
        Task { @MainActor in
            await Task.yield()
            guard isActive, requestedSourceByte == byte, requestedHeadingID == nil else { return }
            proxy.scrollTo(row.id, anchor: .top)
            await Task.yield()
            finishReadingRestore(row)
        }
    }

    private func updateRowGeometry(_ row: OrgPreviewRow, _ frame: CGRect?) {
        if let frame {
            readingTracker.rows[row.id] = OrgPreviewReadingTracker.Row(node: row.node, frame: frame)
            if readingTracker.restoreRowID == row.id { finishReadingRestore(row) }
        } else {
            readingTracker.rows.removeValue(forKey: row.id)
        }
        recordReadingPosition()
    }

    private func finishReadingRestore(_ row: OrgPreviewRow) {
        guard isActive, let byte = requestedSourceByte,
              readingTracker.restoreRowID == row.id,
              let measured = readingTracker.rows[row.id], measured.frame.height > 0 else { return }
        let fraction = CGFloat(min(max(0, byte - row.node.startByte), max(0, row.node.endByte - row.node.startByte - 1)))
            / CGFloat(max(1, row.node.endByte - row.node.startByte))
        // Leave context above a search hit, clear of the floating toolbar.
        let searchInset = highlightedSearchQuery.isEmpty ? 0 : readingTracker.viewportHeight / 3
        scrollPosition.scrollTo(y: byte == 0 ? 0 : max(0, measured.frame.minY + measured.frame.height * fraction - searchInset))
        readingTracker.restoreRowID = nil
        requestedSourceByte = nil
    }

    private func recordReadingPosition() {
        guard isActive, readingTracker.isTracking, requestedSourceByte == nil,
              let byte = readingTracker.sourceByte else { return }
        onReadingPositionChange(byte)
    }

    private func toggleHeading(_ id: String) {
        withAnimation(OrgendaMotion.geometryAnimation(.content, reduceMotion: reduceMotion)) {
            collapsedHeadingIDs.formSymmetricDifference([id])
        }
        interactionFeedback += 1
    }

    private func cycleTODO(_ node: ParsedOrgNode) {
        let workflow = store.workflow(for: path)
        guard let state = workflow.state(node.text.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
        setTODO(node, to: workflow.toggled(state))
    }

    private func presentItemEditor(for heading: ParsedOrgNode) {
        proposedState = nil
        editorItem = store.items.first {
            $0.source.file == path && $0.source.startByte == heading.startByte
        }
    }

    private func setTODO(_ node: ParsedOrgNode, to state: OrgWorkflowState) {
        guard pendingReplacements[node.id] == nil else { return }
        guard var item = store.items.filter({ $0.source.file == path && $0.source.startByte <= node.startByte })
            .max(by: { $0.source.startByte < $1.source.startByte }) else { return }
        let original = item
        item.state = state
        if OrgWorkflowOperations.requiresNote(from: original.state, to: state)
            || (state.isTerminal && store.configuration.logging.done == .note) {
            proposedState = state
            editorItem = original
            return
        }
        _ = store.save(item, original: original)
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
        store.applyPlanningDraft(path: path, node: node, draft: draft)
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
private final class OrgPreviewReadingTracker {
    struct Row {
        let node: ParsedOrgNode
        let frame: CGRect
    }

    var offset: CGFloat = 0
    var viewportHeight: CGFloat = 0
    var rows: [String: Row] = [:]
    var isTracking = false
    var restoreRowID: String?

    var sourceByte: Int? {
        guard offset > 0 else { return 0 }
        guard let row = rows.values.filter({ $0.frame.maxY > offset })
            .min(by: { $0.frame.minY < $1.frame.minY }) else { return nil }
        let fraction = min(1, max(0, (offset - row.frame.minY) / max(1, row.frame.height)))
        let length = max(0, row.node.endByte - row.node.startByte - 1)
        return row.node.startByte + Int(fraction * CGFloat(length))
    }
}
