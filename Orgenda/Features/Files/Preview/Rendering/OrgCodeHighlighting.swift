import SwiftUI
import Highlighter

@MainActor
enum OrgCodeHighlighting {
    private static let cache: NSCache<NSString, NSAttributedString> = {
        let cache = NSCache<NSString, NSAttributedString>()
        cache.countLimit = 128
        cache.totalCostLimit = 16 * 1_024 * 1_024
        return cache
    }()
    private static var highlighters: [String: Highlighter] = [:]

    static func attributed(
        _ source: String,
        language: String?,
        colorScheme: ColorScheme,
        dynamicTypeSize: DynamicTypeSize
    ) -> AttributedString {
        let fontSize = OrgPreviewFontMetrics.pointSize(for: .footnote, dynamicTypeSize: dynamicTypeSize)
        let theme = colorScheme == .dark ? "github-dark" : "github"
        let normalizedLanguage = language?.lowercased()
        let aliases = ["elisp": "lisp", "emacs-lisp": "lisp", "shell-script": "bash"]
        let highlightingLanguage = normalizedLanguage.map { aliases[$0] ?? $0 }
        let highlighterKey = "\(theme)\u{0}\(fontSize)"
        let key = "\(theme)\u{0}\(fontSize)\u{0}\(highlightingLanguage ?? "")\u{0}\(source)" as NSString
        if let cached = cache.object(forKey: key) { return AttributedString(cached) }

        if highlighters[highlighterKey] == nil, let created = Highlighter() {
            created.setTheme(theme, withFont: "Menlo-Regular", ofSize: fontSize)
            highlighters[highlighterKey] = created
        }

        guard let highlighted = highlighters[highlighterKey]?.highlight(source, as: highlightingLanguage) else {
            var value = AttributedString(source)
            value.font = .system(.footnote, design: .monospaced)
            return value
        }
        let mutable = NSMutableAttributedString(attributedString: highlighted)
        mutable.removeAttribute(.backgroundColor, range: NSRange(location: 0, length: mutable.length))
        cache.setObject(mutable, forKey: key, cost: mutable.length * 16)
        return AttributedString(mutable)
    }
}
