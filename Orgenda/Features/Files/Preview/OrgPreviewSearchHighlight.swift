import SwiftUI

extension EnvironmentValues {
    @Entry var orgPreviewSearchQuery = ""
}

enum OrgPreviewSearchHighlight {
    static func attributed(_ value: AttributedString, query: String) -> AttributedString {
        guard !query.isEmpty else { return value }
        var result = value
        var remaining = result.startIndex..<result.endIndex
        while let range = result[remaining].range(of: query, options: [.caseInsensitive, .diacriticInsensitive]),
              !range.isEmpty {
            result[range].backgroundColor = OrgendaTheme.searchHighlight
            remaining = range.upperBound..<result.endIndex
        }
        return result
    }

    /// Match across adjacent emphasis and link runs without losing their styles.
    static func fragments(_ fragments: [OrgPreviewInlineFragment], query: String) -> [OrgPreviewInlineFragment] {
        guard !query.isEmpty else { return fragments }
        var result: [OrgPreviewInlineFragment] = []
        var text = AttributedString()
        func flush() {
            guard !text.characters.isEmpty else { return }
            result.append(.text(attributed(text, query: query)))
            text = AttributedString()
        }
        for fragment in fragments {
            if case .text(let value) = fragment {
                text.append(value)
            } else {
                flush()
                result.append(fragment)
            }
        }
        flush()
        return result
    }
}

struct OrgPreviewSearchText: View {
    @Environment(\.orgPreviewSearchQuery) private var query
    let value: AttributedString

    init(_ text: some StringProtocol) {
        value = AttributedString(String(text))
    }

    init(_ value: AttributedString) {
        self.value = value
    }

    var body: some View {
        Text(OrgPreviewSearchHighlight.attributed(value, query: query))
    }
}
