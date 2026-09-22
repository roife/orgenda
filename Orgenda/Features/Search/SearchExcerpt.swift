import Foundation

func searchExcerpt(_ source: String, matching query: String) -> String {
    let text = source.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    guard !query.isEmpty,
          let match = text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) else {
        return String(text.prefix(160))
    }
    let start = text.index(match.lowerBound, offsetBy: -45, limitedBy: text.startIndex) ?? text.startIndex
    let end = text.index(match.upperBound, offsetBy: 110, limitedBy: text.endIndex) ?? text.endIndex
    return (start == text.startIndex ? "" : "…")
        + String(text[start..<end])
        + (end == text.endIndex ? "" : "…")
}
