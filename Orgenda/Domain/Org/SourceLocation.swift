import Foundation

struct SourceLocation: Hashable, Codable, Sendable {
    var file: String
    var startByte: Int
    var endByte: Int
    var startLine: Int
}
