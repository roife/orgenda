import Foundation

struct SourceLocation: Hashable, Codable, Sendable {
    var file: String
    var startByte: Int
    var endByte: Int
    var startLine: Int
    /// Parent headings, from outermost to innermost, excluding this heading.
    var ancestorTitles: [String] = []
}

extension SourceLocation {
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        file = try values.decode(String.self, forKey: .file)
        startByte = try values.decode(Int.self, forKey: .startByte)
        endByte = try values.decode(Int.self, forKey: .endByte)
        startLine = try values.decode(Int.self, forKey: .startLine)
        ancestorTitles = try values.decodeIfPresent([String].self, forKey: .ancestorTitles) ?? []
    }
}
