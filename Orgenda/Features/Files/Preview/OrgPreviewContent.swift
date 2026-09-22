import SwiftUI

struct PendingSourceReplacement {
    let startByte: Int
    let expected: String
    let replacement: String
}
struct OrgPreviewContent: View {
    let rows: [OrgPreviewRow]
    @Binding var collapsedHeadingIDs: Set<String>
    let pendingReplacements: [String: PendingSourceReplacement]
    let onToggleHeading: (String) -> Void
    let onCycleTODO: (ParsedOrgNode) -> Void
    let onToggleCheckbox: (ParsedOrgNode) -> Void
    let onEditPlanning: (ParsedOrgNode, OrgPlanningEntryDraft) -> Void
    let drag: OrgHeadingDrag?
    @Binding var dropTarget: OrgHeadingDrop?
    let onBeginDrag: (String) -> String?
    let onEndDrag: () -> Void
    let onMoveHeading: (String, String, OrgHeadingPlacement) -> Bool

    var body: some View {
        let presentationRows = OrgPreviewMathRows.group(rows)
        let visibleRows = presentationRows.filter {
            $0.node.type != "blank_line" && $0.parentHeadingIDs.allSatisfy {
                !collapsedHeadingIDs.contains($0)
            }
        }
        let targetRow = presentationRows.first { $0.id == dropTarget?.headingID }
        let afterTargetID = dropTarget.flatMap { target in
            visibleRows.last { row in
                (row.id == target.headingID || row.parentHeadingIDs.contains(target.headingID))
                    && row.id != drag?.headingID
                    && !(drag.map { row.parentHeadingIDs.contains($0.headingID) } ?? false)
            }?.id
        }
        LazyVStack(alignment: .leading, spacing: 4) {
            ForEach(visibleRows) { row in
                OrgPreviewRowView(
                    row: row,
                    isCollapsed: collapsedHeadingIDs.contains(row.id),
                    pendingReplacements: pendingReplacements,
                    onToggleHeading: onToggleHeading,
                    onCycleTODO: onCycleTODO,
                    onToggleCheckbox: onToggleCheckbox,
                    onEditPlanning: onEditPlanning,
                    onBeginDrag: { onBeginDrag(row.id) },
                    onEndDrag: onEndDrag
                )
                .modifier(OrgHeadingDropModifier(
                    headingID: row.headingLevel == nil ? nil : row.id,
                    parentHeadingIDs: row.parentHeadingIDs, drag: drag, target: $dropTarget,
                    onMove: { target, placement in
                        guard let drag else { return false }
                        return onMoveHeading(drag.headingID, target, placement)
                    }
                ))
                .accessibilityActions {
                    if row.headingLevel != nil {
                        let siblings = rows.filter {
                            $0.headingLevel == row.headingLevel && $0.parentHeadingIDs == row.parentHeadingIDs
                        }
                        if let index = siblings.firstIndex(where: { $0.id == row.id }) {
                            if index > 0 {
                                Button("Move up") { _ = onMoveHeading(row.id, siblings[index - 1].id, .before) }
                                Button("Indent") { _ = onMoveHeading(row.id, siblings[index - 1].id, .child) }
                            }
                            if index + 1 < siblings.count {
                                Button("Move down") { _ = onMoveHeading(row.id, siblings[index + 1].id, .after) }
                            }
                        }
                        if let parentID = row.parentHeadingIDs.last {
                            Button("Outdent") { _ = onMoveHeading(row.id, parentID, .after) }
                        }
                    }
                }
                .opacity(drag.map { row.id == $0.headingID || row.parentHeadingIDs.contains($0.headingID) } == true ? 0.4 : 1)
                .padding(.leading, row.indentation)
                .padding(.top, row.id == presentationRows.first(where: { $0.node.type != "blank_line" })?.id
                    ? 0 : row.spacingBefore)
                .background {
                    if dropTarget?.placement == .child && row.id == dropTarget?.headingID {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(OrgendaTheme.accentText.opacity(0.10))
                            .overlay {
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(OrgendaTheme.accentText.opacity(0.55), lineWidth: 1)
                            }
                            .padding(.leading, row.indentation)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                .overlay(alignment: dropTarget?.placement == .before ? .top : .bottom) {
                    if let target = dropTarget,
                       (target.placement == .before && row.id == target.headingID)
                        || (target.placement != .before && row.id == afterTargetID) {
                        Rectangle()
                            .fill(OrgendaTheme.accentText)
                            .frame(height: 2)
                            .padding(.leading, (targetRow?.indentation ?? 0)
                                + (target.placement == .child ? 12 : 0))
                            .allowsHitTesting(false)
                    }
                }
                .transition(.opacity)
                .id(row.id)
            }
        }
        .lineSpacing(4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 20)
    }

}

private struct OrgPreviewRowView: View {
    let row: OrgPreviewRow
    let isCollapsed: Bool
    let pendingReplacements: [String: PendingSourceReplacement]
    let onToggleHeading: (String) -> Void
    let onCycleTODO: (ParsedOrgNode) -> Void
    let onToggleCheckbox: (ParsedOrgNode) -> Void
    let onEditPlanning: (ParsedOrgNode, OrgPlanningEntryDraft) -> Void
    let onBeginDrag: () -> String?
    let onEndDrag: () -> Void

    @ViewBuilder
    var body: some View {
        switch row.node.type {
        case "heading":
            OrgPreviewHeading(
                node: row.node,
                level: row.headingLevel ?? 1,
                canCollapse: row.hasDescendants,
                isCollapsed: isCollapsed,
                todoOverride: row.node.todoNode.flatMap { pendingReplacements[$0.id]?.replacement },
                isTODOUpdating: row.node.todoNode.map { pendingReplacements[$0.id] != nil } ?? false,
                onToggleDisclosure: { onToggleHeading(row.id) },
                onCycleTODO: onCycleTODO,
                onBeginDrag: onBeginDrag,
                onEndDrag: onEndDrag
            )
        case "list_item":
            OrgPreviewListItem(
                node: row.node,
                checkboxOverride: row.node.checkboxNode.flatMap { pendingReplacements[$0.id]?.replacement },
                isCheckboxUpdating: row.node.checkboxNode.map { pendingReplacements[$0.id] != nil } ?? false,
                onToggleCheckbox: onToggleCheckbox
            )
        case "table":
            OrgPreviewTable(node: row.node)
        case "source_block", "example_block", "export_block", "fixed_width":
            OrgPreviewSourceBlock(node: row.node)
        case "custom_block":
            customBlock
        case "quote_block":
            OrgPreviewQuote(node: row.node)
        case "verse_block", "center_block", "dynamic_block":
            OrgPreviewTextBlock(node: row.node)
        case "horizontal_rule":
            Divider().padding(.vertical, 4)
        case "clock":
            OrgPreviewClock(node: row.node)
        case "planning":
            OrgPreviewPlanning(
                node: row.node,
                pendingReplacements: pendingReplacements,
                onEdit: onEditPlanning
            )
        case "paragraph":
            OrgPreviewParagraph(
                node: row.node,
                pendingReplacements: pendingReplacements,
                onEdit: onEditPlanning
            )
        case "math_block":
            if let expression = OrgMathParser.soleDisplayExpression(in: row.node.text) {
                OrgPreviewMathBlock(expression: expression)
                    .accessibilityIdentifier("org.preview.math.\(row.node.startByte)")
            } else {
                Text(row.node.text.trimmingCharacters(in: .newlines))
                    .font(.body.monospaced())
                    .textSelection(.enabled)
            }
        case "blank_line":
            Color.clear.frame(height: 2)
                .accessibilityHidden(true)
        case "property_drawer", "drawer":
            OrgPreviewDrawer(node: row.node)
        case "comment", "comment_block":
            OrgPreviewComment(node: row.node)
        case "footnote_definition":
            OrgPreviewRichText(fragments: OrgPreviewMarkup.fragments(row.node), textStyle: .footnote)
                .font(.footnote)
                .textSelection(.enabled)
        case "keyword":
            OrgPreviewKeyword(node: row.node)
        default:
            Text(row.node.text.trimmingCharacters(in: .newlines))
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }

    private var customBlock: some View {
        let children = OrgPreviewMathRows.group(OrgPreviewOutline.rows(from: row.node.children))
            .filter { $0.node.type != "blank_line" }
        return VStack(alignment: .leading, spacing: 4) {
            Text(OrgPreviewCustomBlocks.title(for: row.node))
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            ForEach(children) { child in
                OrgPreviewRowView(
                    row: child,
                    isCollapsed: false,
                    pendingReplacements: pendingReplacements,
                    onToggleHeading: onToggleHeading,
                    onCycleTODO: onCycleTODO,
                    onToggleCheckbox: onToggleCheckbox,
                    onEditPlanning: onEditPlanning,
                    onBeginDrag: { nil },
                    onEndDrag: onEndDrag
                )
                .padding(.top, child.id == children.first?.id ? 0 : child.spacingBefore)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(uiColor: .quaternarySystemFill), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("org.preview.custom-block.\(row.node.startByte)")
    }
}

enum OrgPreviewMathRows {
    static func group(_ rows: [OrgPreviewRow]) -> [OrgPreviewRow] {
        var result: [OrgPreviewRow] = []
        var index = rows.startIndex

        while index < rows.endIndex {
            let first = rows[index]
            guard isTextRow(first) else {
                result.append(first)
                index += 1
                continue
            }

            // Org paragraphs can split an environment at blank lines, or share
            // its opening/closing line with prose. Scan one contiguous text run
            // and extract complete display expressions before rendering rows.
            var endIndex = index + 1
            var endByte = first.node.endByte
            while endIndex < rows.endIndex {
                let candidate = rows[endIndex]
                guard isTextRow(candidate),
                      candidate.parentHeadingIDs == first.parentHeadingIDs,
                      candidate.node.startByte == endByte else { break }
                endByte = candidate.node.endByte
                endIndex += 1
            }
            let originalRun = rows[index..<endIndex]
            let source = originalRun.map(\.node.text).joined()
            let base = first.node.startByte
            let literals = originalRun.flatMap { OrgPreviewMarkup.mathLiteralRanges(in: $0.node) }
            // Ignore literal openers during discovery, rather than filtering a
            // completed match that may already have swallowed a later formula.
            let allMatches = OrgMathParser.matches(in: source, literalRanges: literals.map {
                ($0.lowerBound - base)..<($0.upperBound - base)
            })
            let run = ArraySlice(mergingInlineRows(originalRun, matches: allMatches, base: base))
            let matches = allMatches.filter { match in
                guard match.expression.mode == .display else { return false }
                // A formula wholly inside a real table/list stays in that
                // container. A table-like line *inside* an environment does not
                // break the surrounding formula into several Org rows.
                return !run.contains { row in
                    ["table", "list_item"].contains(row.node.type)
                        && row.node.startByte <= base + match.startByte
                        && base + match.endByte <= row.node.endByte
                }
            }
            guard !matches.isEmpty else {
                result.append(contentsOf: run)
                index = endIndex
                continue
            }

            var cursor = base
            var slicingRow = run.startIndex
            for match in matches {
                let start = base + match.startByte
                let end = base + match.endByte
                result.append(contentsOf: slices(of: run, in: cursor..<start, index: &slicingRow))
                let node = ParsedOrgNode(
                    id: "math:\(start):\(end)", type: "math_block",
                    text: match.expression.original, startByte: start, endByte: end, children: []
                )
                result.append(OrgPreviewRow(
                    node: node, parentHeadingIDs: first.parentHeadingIDs,
                    headingLevel: nil, parentHeadingLevel: first.parentHeadingLevel,
                    hasDescendants: false
                ))
                cursor = end
            }
            result.append(contentsOf: slices(of: run, in: cursor..<endByte, index: &slicingRow))
            index = endIndex
        }
        return result
    }

    private static func isTextRow(_ row: OrgPreviewRow) -> Bool {
        guard row.headingLevel == nil else { return false }
        return ["paragraph", "blank_line", "ERROR", "table", "list_item"].contains(row.node.type)
    }

    private static func mergingInlineRows(
        _ rows: ArraySlice<OrgPreviewRow>, matches: [OrgMathParser.Match], base: Int
    ) -> [OrgPreviewRow] {
        var spans: [Range<Int>] = []
        for match in matches where match.expression.mode == .inline {
            guard let first = rows.firstIndex(where: { $0.node.endByte > base + match.startByte }),
                  let last = rows.lastIndex(where: { $0.node.startByte < base + match.endByte }),
                  first <= last,
                  rows[first...last].allSatisfy({ ["paragraph", "blank_line", "ERROR"].contains($0.node.type) }),
                  first != last || rows[first].node.type == "ERROR" else { continue }
            if let previous = spans.last, first < previous.upperBound {
                spans[spans.count - 1] = previous.lowerBound..<max(previous.upperBound, last + 1)
            } else {
                spans.append(first..<(last + 1))
            }
        }
        guard !spans.isEmpty else { return Array(rows) }
        var result: [OrgPreviewRow] = []
        var cursor = rows.startIndex
        for span in spans {
            result.append(contentsOf: rows[cursor..<span.lowerBound])
            let parts = rows[span]
            let first = rows[span.lowerBound]
            let end = rows[span.upperBound - 1].node.endByte
            let node = ParsedOrgNode(
                id: "\(first.id):inline:\(end)", type: "paragraph",
                text: parts.map(\.node.text).joined(), startByte: first.node.startByte,
                endByte: end, children: parts.map(\.node)
            )
            result.append(OrgPreviewRow(
                node: node, parentHeadingIDs: first.parentHeadingIDs,
                headingLevel: nil, parentHeadingLevel: first.parentHeadingLevel, hasDescendants: false
            ))
            cursor = span.upperBound
        }
        result.append(contentsOf: rows[cursor..<rows.endIndex])
        return result
    }

    private static func slices(of rows: ArraySlice<OrgPreviewRow>, in range: Range<Int>, index: inout Int) -> [OrgPreviewRow] {
        var result: [OrgPreviewRow] = []
        while index < rows.endIndex, rows[index].node.endByte <= range.lowerBound { index += 1 }
        while index < rows.endIndex, rows[index].node.startByte < range.upperBound {
            let row = rows[index]
            if let node = slice(row.node, in: range, isRow: true) {
                result.append(OrgPreviewRow(
                    node: node, parentHeadingIDs: row.parentHeadingIDs,
                    headingLevel: row.headingLevel, parentHeadingLevel: row.parentHeadingLevel,
                    hasDescendants: row.hasDescendants
                ))
            }
            if row.node.endByte > range.upperBound { break }
            index += 1
        }
        return result
    }

    private static func slice(_ node: ParsedOrgNode, in range: Range<Int>, isRow: Bool = false) -> ParsedOrgNode? {
        let start = max(node.startByte, range.lowerBound)
        let end = min(node.endByte, range.upperBound)
        guard start < end else { return nil }
        if start == node.startByte && end == node.endByte { return node }
        let text = String(decoding: Array(node.text.utf8)[(start - node.startByte)..<(end - node.startByte)], as: UTF8.self)
        let type = isRow
            ? (text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "blank_line" : node.type)
            : (node.type == "list_item_content" ? node.type : "text")
        // Keep complete surrounding markup nodes and their source positions.
        // Partial inline nodes become text rather than dropping delimiters as if
        // they were still a complete bold/verbatim/link construct.
        return ParsedOrgNode(
            id: "\(node.id):slice:\(start):\(end)", type: type, text: text,
            startByte: start, endByte: end,
            children: node.children.compactMap { slice($0, in: start..<end) }
        )
    }
}
