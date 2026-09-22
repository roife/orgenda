import SwiftUI

struct DocumentOutlineNode: Identifiable {
    let id: String
    let startByte: Int
    let title: String
    let level: Int
    var children: [DocumentOutlineNode]
    var state: OrgWorkflowState? = nil
    var scheduled: Date? = nil
    var deadline: Date? = nil

    var subtreeCount: Int { 1 + children.reduce(0) { $0 + $1.subtreeCount } }
    var flattened: [DocumentOutlineNode] { [self] + children.flatMap(\.flattened) }

    static func tree(from nodes: [ParsedOrgNode], items: [OrgItem] = []) -> [DocumentOutlineNode] {
        // The index only stores headings that carry a workflow state, a planning
        // date, or a tagged kind. Plain headings simply have nothing to filter on.
        var indexed: [Int: OrgItem] = [:]
        for item in items where indexed[item.source.startByte] == nil {
            indexed[item.source.startByte] = item
        }

        let headings = nodes.filter { $0.type == "heading" }
        var index = 0

        func buildChildren(of parentLevel: Int) -> [DocumentOutlineNode] {
            var result: [DocumentOutlineNode] = []

            while index < headings.count {
                let heading = headings[index]
                let marker = heading.children
                    .first { $0.type == "heading_marker" }?
                    .text ?? heading.text
                let level = max(1, marker.prefix { $0 == "*" }.count)
                guard level > parentLevel else { break }

                index += 1
                let children = buildChildren(of: level)
                let title = heading.children
                    .first(where: { $0.type == "heading_title" })?
                    .text.trimmingCharacters(in: .whitespacesAndNewlines)
                    ?? ""
                let item = indexed[heading.startByte]

                result.append(
                    DocumentOutlineNode(
                        id: heading.id,
                        startByte: heading.startByte,
                        title: title.isEmpty ? String(localized: "Untitled") : title,
                        level: level,
                        children: children,
                        state: heading.todoNode.flatMap {
                            OrgWorkflowState(rawValue: $0.text.trimmingCharacters(in: .whitespacesAndNewlines))
                        },
                        scheduled: item?.scheduled,
                        deadline: item?.deadline
                    )
                )
            }

            return result
        }

        return buildChildren(of: 0)
    }
}

/// View-only filter for the document outline. It never rewrites the source: a
/// heading stays when it matches, or when one of its descendants matches so the
/// match keeps its outline path. Empty criteria mean "match everything".
struct DocumentOutlineFilter: Equatable {
    var states: Set<OrgWorkflowState> = []
    var scheduledFrom: Date?
    var scheduledTo: Date?
    var deadlineFrom: Date?
    var deadlineTo: Date?

    var isActive: Bool {
        !states.isEmpty || scheduledFrom != nil || scheduledTo != nil
            || deadlineFrom != nil || deadlineTo != nil
    }

    mutating func reset() { self = DocumentOutlineFilter() }

    func matches(_ node: DocumentOutlineNode) -> Bool {
        matchesState(node) && matches(node.scheduled, from: scheduledFrom, to: scheduledTo)
            && matches(node.deadline, from: deadlineFrom, to: deadlineTo)
    }

    func apply(to nodes: [DocumentOutlineNode]) -> [DocumentOutlineNode] {
        guard isActive else { return nodes }
        return nodes.compactMap { node in
            var node = node
            node.children = apply(to: node.children)
            guard matches(node) || !node.children.isEmpty else { return nil }
            return node
        }
    }

    func matchCount(in nodes: [DocumentOutlineNode]) -> Int {
        guard isActive else { return nodes.reduce(0) { $0 + $1.subtreeCount } }
        return nodes.flatMap(\.flattened).filter(matches).count
    }

    private func matchesState(_ node: DocumentOutlineNode) -> Bool {
        states.isEmpty || node.state.map(states.contains) == true
    }

    private func matches(_ date: Date?, from: Date?, to: Date?) -> Bool {
        guard from != nil || to != nil else { return true }
        guard let date else { return false }
        let day = date.startOfDay
        if let from, day < from.startOfDay { return false }
        if let to, day > to.startOfDay { return false }
        return true
    }
}

struct DocumentOutlineSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var expandedHeadingIDs: Set<String> = []
    @State private var filter = DocumentOutlineFilter()
    @State private var isFilterPresented = false
    @State private var headingDrag: OrgHeadingDrag?
    @State private var dropTarget: OrgHeadingDrop?
    @State private var pendingMove: OrgHeadingMove?
    @State private var moveError: String?
    @State private var interactionFeedback = 0

    let store: WorkspaceStore
    let path: String
    let isEditing: Bool
    let onSelect: (DocumentOutlineNode) -> Void
    let onMove: (OrgHeadingMove) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if nodes.isEmpty {
                    ContentUnavailableView(
                        "No headings",
                        systemImage: "list.bullet",
                        description: Text("This document does not contain an Org heading.")
                    )
                } else if filteredNodes.isEmpty {
                    ContentUnavailableView {
                        Label("No matching headings", systemImage: "line.3.horizontal.decrease.circle")
                    } description: {
                        Text("No heading matches the current filter.")
                    } actions: {
                        Button("Clear filters", action: clearFilter)
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .accessibilityIdentifier("org.outline.filter.clear")
                    }
                    .accessibilityElement(children: .contain)
                } else {
                    outline
                }
            }
            .navigationTitle("Outline")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    filterButton
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "xmark", role: .close) { dismiss() }
                        .labelStyle(.iconOnly)
                        .accessibilityIdentifier("org.document.outline.done")
                }
            }
            .sheet(isPresented: $isFilterPresented) {
                DocumentOutlineFilterSheet(filter: $filter)
                    .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
        .accessibilityIdentifier("org.document.outline.sheet")
        .sensoryFeedback(.selection, trigger: interactionFeedback)
        .onChange(of: store.parsedDocuments[path]) { previous, document in
            if let previous, let document {
                expandedHeadingIDs = OrgHeadingContinuity.remap(
                    expandedHeadingIDs, from: previous, to: document, move: pendingMove
                )
            } else {
                expandedHeadingIDs.removeAll()
            }
            pendingMove = nil
            endDrag()
        }
        .onChange(of: filter) { _, _ in endDrag() }
        .onDisappear { endDrag() }
        .alert("Could not move heading", isPresented: Binding(
            get: { moveError != nil }, set: { if !$0 { moveError = nil } }
        )) {
            Button("OK", role: .cancel) { moveError = nil }
        } message: {
            Text(moveError ?? "")
        }
    }

    private var nodes: [DocumentOutlineNode] {
        store.parsedDocuments[path].map {
            DocumentOutlineNode.tree(from: $0.root.children, items: store.items.filter { $0.source.file == path })
        } ?? []
    }

    private var filteredNodes: [DocumentOutlineNode] { filter.apply(to: nodes) }

    private var outline: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if filter.isActive {
                    filterSummary
                }
                ForEach(filteredNodes) { node in
                    DocumentOutlineBranch(
                        node: node,
                        expandedHeadingIDs: $expandedHeadingIDs,
                        isFiltering: filter.isActive,
                        isEditing: isEditing,
                        parentHeadingIDs: [],
                        drag: headingDrag,
                        dropTarget: $dropTarget,
                        onBeginDrag: beginDrag,
                        onEndDrag: endDrag,
                        onMove: moveHeading,
                        onSelect: selectHeading
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .scrollEdgeEffectStyle(.soft, for: [.top, .bottom])
        .accessibilityIdentifier("org.document.outline.scroll")
    }

    private func beginDrag(_ headingID: String) -> String? {
        guard pendingMove == nil, let document = store.parsedDocuments[path],
              document.root.children.contains(where: { $0.type == "heading" && $0.id == headingID }),
              let source = store.documents.first(where: { $0.path == path })?.contents,
              source.utf8.elementsEqual(document.root.text.utf8) else { return nil }
        let token = UUID().uuidString
        headingDrag = OrgHeadingDrag(token: token, headingID: headingID, document: document)
        interactionFeedback += 1
        return token
    }

    private func endDrag() {
        headingDrag = nil
        dropTarget = nil
    }

    private func moveHeading(_ targetID: String, _ placement: OrgHeadingPlacement) -> Bool {
        guard pendingMove == nil, let drag = headingDrag else { return false }
        defer { endDrag() }
        guard let move = store.moveHeading(in: drag.document, headingID: drag.headingID,
                                           targetID: targetID, placement: placement) else {
            moveError = store.operationError
            return false
        }
        pendingMove = move
        onMove(move)
        if let row = OrgPreviewOutline.rows(from: drag.document.root.children).first(where: { $0.id == targetID }) {
            expandedHeadingIDs.formUnion(row.parentHeadingIDs)
            if placement == .child { expandedHeadingIDs.insert(targetID) }
        }
        interactionFeedback += 1
        return true
    }

    private func selectHeading(_ node: DocumentOutlineNode) {
        // Wait for the new tree before exposing a byte offset to the editor.
        guard pendingMove == nil, headingDrag == nil,
              let document = store.parsedDocuments[path],
              let source = store.documents.first(where: { $0.path == path })?.contents,
              source.utf8.elementsEqual(document.root.text.utf8) else { return }
        onSelect(node)
        dismiss()
    }

    private var filterSummary: some View {
        HStack(spacing: 12) {
            Label("\(filter.matchCount(in: nodes)) matching", systemImage: "line.3.horizontal.decrease.circle.fill")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Button("Clear", systemImage: "xmark.circle", action: clearFilter)
                .labelStyle(.iconOnly)
                .font(.subheadline.weight(.semibold))
                .frame(width: 44, height: 44)
                .accessibilityLabel("Clear filters")
                .accessibilityIdentifier("org.outline.filter.clear")
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("org.outline.filter.summary")
    }

    private func clearFilter() {
        withAnimation(OrgendaMotion.geometryAnimation(.content, reduceMotion: reduceMotion)) {
            filter.reset()
        }
    }

    private var filterButton: some View {
        Button { isFilterPresented = true } label: {
            Label(
                "Filter",
                systemImage: filter.isActive
                    ? "line.3.horizontal.decrease.circle.fill"
                    : "line.3.horizontal.decrease.circle"
            )
        }
        .accessibilityLabel("Filter outline")
        .accessibilityValue(filter.isActive ? "Active" : "Inactive")
        .accessibilityIdentifier("org.document.outline.filter")
    }
}

struct DocumentOutlineFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var filter: DocumentOutlineFilter

    var body: some View {
        NavigationStack {
            Form {
                Section("Status") {
                    OrgendaFlowLayout(horizontalSpacing: 2, verticalSpacing: 8) {
                        ForEach(OrgWorkspaceConfiguration.taskStates) { state in
                            OrgWorkflowOption(state: state, isSelected: filter.states.contains(state)) {
                                if filter.states.contains(state) {
                                    filter.states.remove(state)
                                } else {
                                    filter.states.insert(state)
                                }
                            }
                            .accessibilityIdentifier("org.outline.filter.state.\(state.rawValue)")
                        }
                    }
                    .padding(.vertical, 4)
                }
                dateSection("Scheduled", from: $filter.scheduledFrom, to: $filter.scheduledTo)
                dateSection("Deadline", from: $filter.deadlineFrom, to: $filter.deadlineTo)
            }
            .navigationTitle("Filter Outline")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset", systemImage: "arrow.counterclockwise") { filter.reset() }
                        .labelStyle(.iconOnly)
                        .disabled(!filter.isActive)
                        .accessibilityIdentifier("org.outline.filter.reset")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "xmark", role: .close) { dismiss() }
                        .labelStyle(.iconOnly)
                        .accessibilityIdentifier("org.outline.filter.done")
                }
            }
        }
        .accessibilityIdentifier("org.outline.filter.sheet")
    }

    private func dateSection(_ title: String, from: Binding<Date?>, to: Binding<Date?>) -> some View {
        Section(LocalizedStringKey(title)) {
            dateRow(String(localized: "From"), value: from, identifier: "\(title.lowercased()).from")
            dateRow(String(localized: "To"), value: to, identifier: "\(title.lowercased()).to")
        }
    }

    private func dateRow(_ label: String, value: Binding<Date?>, identifier: String) -> some View {
        let enabled = Binding(
            get: { value.wrappedValue != nil },
            set: { value.wrappedValue = $0 ? (value.wrappedValue ?? Date.now.startOfDay) : nil }
        )
        return VStack(alignment: .leading, spacing: 4) {
            Toggle(label, isOn: enabled)
                .accessibilityIdentifier("org.outline.filter.\(identifier)")
            if let date = value.wrappedValue {
                DatePicker(
                    label,
                    selection: Binding(get: { date }, set: { value.wrappedValue = $0 }),
                    displayedComponents: .date
                )
                .labelsHidden()
                .datePickerStyle(.compact)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct DocumentOutlineBranch: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let node: DocumentOutlineNode
    @Binding var expandedHeadingIDs: Set<String>
    let isFiltering: Bool
    let isEditing: Bool
    let parentHeadingIDs: [String]
    let drag: OrgHeadingDrag?
    @Binding var dropTarget: OrgHeadingDrop?
    let onBeginDrag: (String) -> String?
    let onEndDrag: () -> Void
    let onMove: (String, OrgHeadingPlacement) -> Bool
    let onSelect: (DocumentOutlineNode) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                leadingControl

                Button {
                    onSelect(node)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        if let state = node.state { OrgWorkflowIcon(state) }
                        Text(node.title)
                            .foregroundStyle(node.state.map(OrgendaTheme.workflowColor) ?? .primary)
                    }
                        .font(.body.weight(node.level == 1 ? .semibold : .regular))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(node.title)
                .accessibilityValue("Heading level \(node.level)")
                .accessibilityHint(isEditing ? "Moves the cursor to this heading in Edit" : "Shows this heading in Preview")
                .accessibilityIdentifier("org.document.outline.heading.\(node.startByte)")
                .overlay {
                    OrgHeadingDragSource(
                        title: node.title,
                        onBegin: { onBeginDrag(node.id) },
                        onEnd: onEndDrag,
                        onTap: { onSelect(node) }
                    )
                    .accessibilityHidden(true)
                }
            }
            .modifier(OrgHeadingDropModifier(
                headingID: node.id, parentHeadingIDs: parentHeadingIDs,
                drag: drag, target: $dropTarget, onMove: onMove
            ))
            .opacity(drag.map { $0.headingID == node.id || parentHeadingIDs.contains($0.headingID) } == true ? 0.4 : 1)
            .background {
                if dropTarget?.headingID == node.id && dropTarget?.placement == .child {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(OrgendaTheme.accentText.opacity(0.10))
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(OrgendaTheme.accentText.opacity(0.55), lineWidth: 1)
                        }
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .overlay(alignment: .bottom) {
                Divider().opacity(0.45)
            }

            if isExpanded {
                ForEach(node.children) { child in
                    DocumentOutlineBranch(
                        node: child,
                        expandedHeadingIDs: $expandedHeadingIDs,
                        isFiltering: isFiltering,
                        isEditing: isEditing,
                        parentHeadingIDs: parentHeadingIDs + [node.id],
                        drag: drag,
                        dropTarget: $dropTarget,
                        onBeginDrag: onBeginDrag,
                        onEndDrag: onEndDrag,
                        onMove: onMove,
                        onSelect: onSelect
                    )
                    .padding(.leading, node.level < 4 ? 16 : 0)
                }
                .transition(.opacity)
            }
        }
        .overlay(alignment: dropTarget?.placement == .before ? .top : .bottom) {
            if let target = dropTarget, target.headingID == node.id {
                Rectangle()
                    .fill(OrgendaTheme.accentText)
                    .frame(height: 2)
                    .padding(.leading, target.placement == .child ? 16 : 0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }

    @ViewBuilder
    private var leadingControl: some View {
        // A filter always reveals matches, so folding is paused and the chevron
        // would be a no-op. Keep its width for a stable title alignment.
        if node.children.isEmpty || isFiltering {
            Color.clear
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)
        } else {
            Button {
                withAnimation(
                    OrgendaMotion.geometryAnimation(
                        .content,
                        reduceMotion: reduceMotion
                    )
                ) {
                    expandedHeadingIDs.formSymmetricDifference([node.id])
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? "Collapse \(node.title)" : "Expand \(node.title)")
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            .accessibilityIdentifier("org.document.outline.disclosure.\(node.startByte)")
        }
    }

    private var isExpanded: Bool {
        isFiltering || expandedHeadingIDs.contains(node.id)
    }
}
