import Foundation

struct WorkspaceDocument: Identifiable, Hashable, Codable, Sendable {
    var id: String { path }
    var path: String
    var title: String
    var contents: String
    var kind: Kind

    enum Kind: String, Codable, Sendable {
        case org
        case markdown
        case folder
    }
}
