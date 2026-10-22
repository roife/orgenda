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
    let onEditHeading: (ParsedOrgNode) -> Void
    let onCycleTODO: (ParsedOrgNode) -> Void
    let onSetTODO: (ParsedOrgNode, OrgWorkflowState) -> Void
    let onToggleCheckbox: (ParsedOrgNode) -> Void
    let onEditPlanning: (ParsedOrgNode, OrgPlanningEntryDraft) -> Void
    let drag: OrgHeadingDrag?
    @Binding var dropTarget: OrgHeadingDrop?
    let onBeginDrag: (String) -> String?
    let onEndDrag: () -> Void
    let onMoveHeading: (String, String, OrgHeadingPlacement) -> Bool
    let onRowGeometryChange: (OrgPreviewRow, CGRect?) -> Void

    var body: some View {
        let visibleRows = rows.filter {
            $0.node.type != "blank_line" && $0.parentHeadingIDs.allSatisfy {
                !collapsedHeadingIDs.contains($0)
            }
        }
        let targetRow = rows.first { $0.id == dropTarget?.headingID }
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
                    onEditHeading: onEditHeading,
                    onCycleTODO: onCycleTODO,
                    onSetTODO: onSetTODO,
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
                .padding(.top, row.id == rows.first(where: { $0.node.type != "blank_line" })?.id
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
                .onGeometryChange(for: CGRect.self) { geometry in
                    geometry.frame(in: .named("org.preview.content"))
                } action: { frame in
                    onRowGeometryChange(row, frame)
                }
                .onDisappear { onRowGeometryChange(row, nil) }
                .id(row.id)
            }
        }
        .lineSpacing(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 20)
        .frame(maxWidth: 900, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .center)
        .coordinateSpace(name: "org.preview.content")
    }

}

private struct OrgPreviewRowView: View {
    let row: OrgPreviewRow
    let isCollapsed: Bool
    let pendingReplacements: [String: PendingSourceReplacement]
    let onToggleHeading: (String) -> Void
    let onEditHeading: (ParsedOrgNode) -> Void
    let onCycleTODO: (ParsedOrgNode) -> Void
    let onSetTODO: (ParsedOrgNode, OrgWorkflowState) -> Void
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
                onEdit: { onEditHeading(row.node) },
                onCycleTODO: onCycleTODO,
                onSetTODO: onSetTODO,
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
        case "paragraph", "paragraph_group":
            OrgPreviewParagraph(
                node: row.node,
                pendingReplacements: pendingReplacements,
                onEdit: onEditPlanning
            )
        case "latex_block":
            OrgPreviewMathBlock(expression: OrgMathExpression(row.node))
                .accessibilityIdentifier("org.preview.math.\(row.node.startByte)")
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
            OrgPreviewSearchText(row.node.text.trimmingCharacters(in: .newlines))
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }

    private var customBlock: some View {
        let children = OrgPreviewOutline.rows(from: row.node.children)
            .filter { $0.node.type != "blank_line" }
        return VStack(alignment: .leading, spacing: 4) {
            OrgPreviewSearchText(OrgPreviewCustomBlocks.title(for: row.node))
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            ForEach(children) { child in
                OrgPreviewRowView(
                    row: child,
                    isCollapsed: false,
                    pendingReplacements: pendingReplacements,
                    onToggleHeading: onToggleHeading,
                    onEditHeading: onEditHeading,
                    onCycleTODO: onCycleTODO,
                    onSetTODO: onSetTODO,
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
