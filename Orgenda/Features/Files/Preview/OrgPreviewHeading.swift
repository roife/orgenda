import SwiftUI

struct OrgPreviewHeading: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let node: ParsedOrgNode
    let level: Int
    let canCollapse: Bool
    let isCollapsed: Bool
    let todoOverride: String?
    let isTODOUpdating: Bool
    let onToggleDisclosure: () -> Void
    let onCycleTODO: (ParsedOrgNode) -> Void
    let onBeginDrag: () -> String?
    let onEndDrag: () -> Void

    var body: some View {
        HStack(alignment: .previewHeadingFirstLineCenter, spacing: 2) {
            disclosureControl
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .previewHeadingFirstLineCenter, spacing: 4) {
                    if let todoNode = node.todoNode {
                        todoControl(todoNode)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    OrgPreviewRichText(fragments: titleFragments, textStyle: titleTextStyle)
                        .font(headingFont)
                        .fixedSize(horizontal: false, vertical: true)
                        .layoutPriority(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .alignmentGuide(.previewHeadingFirstLineCenter) { dimensions in
                            // Remove the distance between baselines to measure
                            // one line, rather than centering against all lines.
                            (dimensions.height - dimensions[.lastTextBaseline]
                                + dimensions[.firstTextBaseline]) / 2
                        }
                        .accessibilityIdentifier("org.preview.heading.title.\(node.startByte)")
                        .background {
                            GeometryReader { geometry in
                                Color.clear.preference(
                                    key: OrgHeadingTitleBounds.self,
                                    value: geometry.frame(in: .named(node.id))
                                )
                            }
                        }
                        .overlay {
                            // Keep image buttons and their context menus interactive.
                            // Image headings can still be moved from the outline.
                            if !titleFragments.contains(where: { if case .image = $0 { return true }; return false }) {
                                OrgHeadingDragSource(title: title, onBegin: onBeginDrag, onEnd: onEndDrag)
                                    .accessibilityHidden(true)
                            }
                        }
                }
                .padding(.top, node.todoNode == nil ? 8 : 0)
                if priority != nil || !tags.isEmpty {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) {
                            priorityBadge
                            tagText.fixedSize()
                        }
                        VStack(alignment: .leading, spacing: 0) {
                            priorityBadge
                            tagText
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, level == 1 ? 0 : -8)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("org.preview.heading.\(node.startByte)")
    }

    @ViewBuilder
    private var tagText: some View {
        if !tags.isEmpty {
            Text(tags.map { "#\($0)" }.joined(separator: "  "))
                .font(.subheadline)
                .foregroundStyle(OrgendaTheme.previewMetadata)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("org.preview.tags.\(node.startByte)")
        }
    }

    @ViewBuilder
    private var priorityBadge: some View {
        if let priority {
            Text(priority)
                .font(.caption.weight(.medium))
                .foregroundStyle(OrgendaTheme.previewMetadata)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(OrgendaTheme.previewMetadata.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
                .accessibilityLabel("Priority \(priority)")
                .fixedSize()
        }
    }

    @ViewBuilder
    private var disclosureControl: some View {
        if canCollapse {
            Button(action: onToggleDisclosure) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                    .animation(
                        OrgendaMotion.geometryAnimation(.selection, reduceMotion: reduceMotion),
                        value: isCollapsed
                    )
                    .frame(width: 44, height: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, -22)
            .accessibilityLabel(isCollapsed ? "Expand \(title)" : "Collapse \(title)")
            .accessibilityValue(isCollapsed ? "Collapsed" : "Expanded")
            .accessibilityIdentifier("org.preview.heading.disclosure.\(node.startByte)")
        } else {
            Color.clear
                .frame(width: 44, height: 44, alignment: .leading)
                .padding(.trailing, -22)
                .accessibilityHidden(true)
        }
    }

    private func todoControl(_ todoNode: ParsedOrgNode) -> some View {
        let keyword = (todoOverride ?? todoNode.text)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let state = OrgWorkflowState(rawValue: keyword)

        return Button { onCycleTODO(todoNode) } label: {
            Image(systemName: state?.symbol ?? "questionmark.circle")
                .foregroundStyle(state.map(OrgendaTheme.workflowColor) ?? .secondary)
                .font(.title3.weight(.medium))
                .contentTransition(.interpolate)
                .frame(minWidth: 28, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isTODOUpdating)
        .accessibilityLabel("Change task state for \(title)")
        .accessibilityValue(isTODOUpdating ? String(localized: "\(state?.title ?? keyword), Updating") : (state?.title ?? keyword))
        .accessibilityHint("Change this item's workflow state")
        .accessibilityIdentifier("org.preview.todo.\(todoNode.startByte)")
    }

    private var title: String {
        String(attributedTitle.characters)
    }

    private var titleFragments: [OrgPreviewInlineFragment] {
        var fragments = node.child(ofType: "heading_title").map {
            OrgPreviewMarkup.fragments($0, trimSpaces: true)
        } ?? [.text(AttributedString(String(localized: "Untitled")))]
        if let keyword = todoOverride ?? node.todoNode?.text,
           let state = OrgWorkflowState(rawValue: keyword.trimmingCharacters(in: .whitespacesAndNewlines)) {
            fragments = fragments.map { fragment in
                guard case .text(var value) = fragment else { return fragment }
                value.foregroundColor = OrgendaTheme.workflowColor(state)
                return .text(value)
            }
        }
        return fragments
    }

    private var attributedTitle: AttributedString {
        var value = node.child(ofType: "heading_title").map { OrgPreviewMarkup.attributed($0, trimSpaces: true) }
            ?? AttributedString(String(localized: "Untitled"))
        if let keyword = todoOverride ?? node.todoNode?.text,
           let state = OrgWorkflowState(rawValue: keyword.trimmingCharacters(in: .whitespacesAndNewlines)) {
            value.foregroundColor = OrgendaTheme.workflowColor(state)
        }
        return value
    }

    private var tags: [String] {
        guard let source = node.child(ofType: "tag_list")?.text else { return [] }
        return source
            .split(separator: ":")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var priority: String? {
        guard let value = node.child(ofType: "priority")?.text
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value.trimmingCharacters(in: CharacterSet(charactersIn: "[#]"))
    }

    private var headingFont: Font {
        switch level {
        case 1: .title3.bold()
        case 2: .callout.weight(.semibold)
        default: .subheadline.weight(.semibold)
        }
    }

    private var titleTextStyle: UIFont.TextStyle {
        switch level {
        case 1: .title3
        case 2: .callout
        default: .subheadline
        }
    }

}

private extension VerticalAlignment {
    enum PreviewHeadingFirstLineCenter: AlignmentID {
        static func defaultValue(in dimensions: ViewDimensions) -> CGFloat {
            dimensions[VerticalAlignment.center]
        }
    }

    static let previewHeadingFirstLineCenter = VerticalAlignment(PreviewHeadingFirstLineCenter.self)
}

struct OrgPreviewListItem: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let node: ParsedOrgNode
    let checkboxOverride: String?
    let isCheckboxUpdating: Bool
    let onToggleCheckbox: (ParsedOrgNode) -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            if let checkboxNode = node.checkboxNode {
                checkboxControl(checkboxNode)
            } else {
                Text(marker)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 28, minHeight: 24)
                    .accessibilityHidden(true)
            }

            OrgPreviewRichText(fragments: contentFragments, textStyle: .subheadline)
                .font(.subheadline)
                .foregroundStyle(isComplete ? .secondary : .primary)
                .strikethrough(isComplete, color: .secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: node.checkboxNode == nil ? 24 : 44, alignment: .leading)
        }
        .padding(.leading, listIndentation)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("org.preview.list-item.\(node.startByte)")
    }

    private func checkboxControl(_ checkboxNode: ParsedOrgNode) -> some View {
        Button { onToggleCheckbox(checkboxNode) } label: {
            let image = Image(systemName: isComplete ? "checkmark.square.fill" : "square")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(isComplete ? OrgendaTheme.habit : .secondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())

            if reduceMotion {
                image.contentTransition(.opacity)
            } else {
                image.contentTransition(.symbolEffect(.replace))
            }
        }
        .buttonStyle(.plain)
        .disabled(isCheckboxUpdating)
        .accessibilityLabel(isComplete ? "Mark \(content) incomplete" : "Mark \(content) complete")
        .accessibilityValue(
            isCheckboxUpdating
                ? (isComplete ? "Checked, Updating" : "Unchecked, Updating")
                : (isComplete ? "Checked" : "Unchecked")
        )
        .accessibilityIdentifier("org.preview.checkbox.\(checkboxNode.startByte)")
    }

    private var content: String {
        String(attributedContent.characters)
    }

    private var attributedContent: AttributedString {
        OrgPreviewMarkup.listContent(node)
    }

    private var contentFragments: [OrgPreviewInlineFragment] {
        guard let content = node.children.first(where: { $0.type == "list_item_content" }) else { return [] }
        return OrgPreviewMarkup.fragments(content, trimSpaces: true)
    }

    private var marker: String {
        OrgPreviewMarkup.listMarker(node)
    }

    private var listIndentation: CGFloat {
        guard let markerNode = node.children.first(where: { $0.type.hasSuffix("list_marker") }) else {
            return 0
        }
        let spaces = markerNode.text.prefix { $0 == " " || $0 == "\t" }.count
        return CGFloat(min(spaces, 12)) * 4
    }

    private static let checkedCheckboxExpression = try? NSRegularExpression(pattern: #"\[[Xx]\]"#)

    private var isComplete: Bool {
        let source = checkboxOverride ?? node.checkboxNode?.text ?? ""
        return Self.checkedCheckboxExpression?
            .firstMatch(in: source, range: NSRange(source.startIndex..., in: source)) != nil
    }
}
