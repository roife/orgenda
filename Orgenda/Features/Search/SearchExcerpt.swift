import Foundation

func searchExcerpt(_ source: String, around match: Range<String.Index>? = nil) -> String {
    guard let match else {
        return source.prefix(160).split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
    let start = source.index(match.lowerBound, offsetBy: -45, limitedBy: source.startIndex) ?? source.startIndex
    let end = source.index(match.upperBound, offsetBy: 110, limitedBy: source.endIndex) ?? source.endIndex
    // Normalize only the small excerpt, never every line in a large file.
    let text = source[start..<end].split(whereSeparator: \.isWhitespace).joined(separator: " ")
    return (start == source.startIndex ? "" : "…") + text + (end == source.endIndex ? "" : "…")
}
