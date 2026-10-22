import Foundation
import OrgTreeSitter

struct ParsedOrgNode: Identifiable, Hashable, Sendable {
    var id: String
    let type: String
    let text: String
    let startByte: Int
    let endByte: Int
    let children: [ParsedOrgNode]
}

extension ParsedOrgNode {
    func shifted(by delta: Int) -> ParsedOrgNode {
        guard delta != 0 else { return self }
        return ParsedOrgNode(id: id, type: type, text: text, startByte: startByte + delta,
                             endByte: endByte + delta, children: children.map { $0.shifted(by: delta) })
    }

    init(_ node: OrgSyntaxNode, path: String) {
        self.init(
            id: "\(path):\(node.startByte):\(node.endByte):\(node.type)",
            type: node.type, text: node.text,
            startByte: Int(node.startByte), endByte: Int(node.endByte),
            children: node.namedChildren.map { ParsedOrgNode($0, path: path) }
        )
    }

    func child(ofType type: String) -> ParsedOrgNode? {
        children.first { $0.type == type }
    }

    var todoNode: ParsedOrgNode? { child(ofType: "todo_keyword") }
    var checkboxNode: ParsedOrgNode? { child(ofType: "checkbox") }

    var descendantsByID: [String: ParsedOrgNode] {
        var result = [id: self]
        for child in children {
            result.merge(child.descendantsByID) { current, _ in current }
        }
        return result
    }
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
    var source: SourceLocation
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
    let journalEntries: [JournalEntry]
    let hasError: Bool

    init(path: String, root: ParsedOrgNode, headings: [IndexedOrgHeading], hasError: Bool,
         journalEntries: [JournalEntry] = []) {
        self.path = path
        self.root = root
        self.headings = headings
        self.journalEntries = journalEntries
        self.hasError = hasError
    }
}
