import Foundation

struct SourceLocation: Hashable, Codable, Sendable {
    var file: String
    var startByte: Int
    var endByte: Int
    var startLine: Int
    /// Parent headings, from outermost to innermost, excluding this heading.
    var ancestorTitles: [String] = []
}
