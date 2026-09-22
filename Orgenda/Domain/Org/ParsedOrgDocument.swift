import Foundation

struct ParsedOrgNode: Identifiable, Hashable, Sendable {
    let id: String
    let type: String
    let text: String
    let startByte: Int
    let endByte: Int
    let children: [ParsedOrgNode]
}

struct IndexedOrgHeading: Hashable, Sendable {
    let title: String
    let state: OrgWorkflowState?
    let priority: OrgPriority
    let tags: [String]
    let scheduled: Date?
    let deadline: Date?
    let closed: Date?
    var eventDate: Date? = nil
    let hasTime: Bool
    let recurrence: String?
    let body: String
    let source: SourceLocation
    var durationMinutes: Int = 30
    var properties: [String: String] = [:]

    var kind: OrgItemKind {
        if tags.contains("project") { return .project }
        if tags.contains("habit") || properties["STYLE"]?.lowercased() == "habit" { return .habit }
        if state == nil, scheduled != nil || deadline != nil || eventDate != nil { return .event }
        if tags.contains("note") { return .note }
        return .task
    }
}

struct ParsedOrgDocument: Identifiable, Hashable, Sendable {
    var id: String { path }
    let path: String
    let root: ParsedOrgNode
    let headings: [IndexedOrgHeading]
    let hasError: Bool
    /// Counted once during parsing so publishing never re-walks every tree.
    let nodeCount: Int

    init(path: String, root: ParsedOrgNode, headings: [IndexedOrgHeading], hasError: Bool) {
        self.path = path
        self.root = root
        self.headings = headings
        self.hasError = hasError
        func count(_ node: ParsedOrgNode) -> Int {
            1 + node.children.reduce(0) { $0 + count($1) }
        }
        nodeCount = count(root)
    }
}
