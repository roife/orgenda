import SwiftUI

struct OrgPreviewSourceBlock: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let node: ParsedOrgNode

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(label, systemImage: node.type == "source_block" ? "chevron.left.forwardslash.chevron.right" : "text.alignleft")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ScrollView(.horizontal) {
                Text(renderedCode)
                    .fixedSize(horizontal: true, vertical: false)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("org.preview.source.content.\(node.startByte)")
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemFill), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityIdentifier("org.preview.source.\(node.startByte)")
    }

    private var renderedCode: AttributedString {
        let source = OrgPreviewMarkup.literalText(node)
        guard node.type == "source_block" else {
            var plain = AttributedString(source)
            plain.font = .system(.footnote, design: .monospaced)
            return plain
        }
        return OrgCodeHighlighting.attributed(
            source,
            language: sourceLanguage,
            colorScheme: colorScheme,
            dynamicTypeSize: dynamicTypeSize
        )
    }

    private var sourceLanguage: String? {
        node.child(ofType: "source_block_begin")?.child(ofType: "source_language")?.text
    }

    private var label: String {
        switch node.type {
        case "example_block": return String(localized: "Example")
        case "export_block":
            let format = node.children.first?.text.split(whereSeparator: \.isWhitespace).dropFirst().first.map(String.init)
            return format.map { String(localized: "\($0.uppercased()) export") } ?? String(localized: "Export")
        case "fixed_width": return String(localized: "Fixed width")
        default:
            return sourceLanguage ?? String(localized: "Code")
        }
    }
}
