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
        case configuration

        init?(path: String) {
            if path == "config.json" {
                self = .configuration
                return
            }
            switch (path as NSString).pathExtension.lowercased() {
            case "org", "org_archive": self = .org
            case "md", "markdown": self = .markdown
            default: return nil
            }
        }
    }
}
