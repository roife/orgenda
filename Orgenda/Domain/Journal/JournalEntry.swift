import Foundation

struct JournalEntry: Identifiable, Hashable, Codable, Sendable {
    var id: UUID
    var date: Date
    var title: String
    var body: String
    var source: SourceLocation
}
