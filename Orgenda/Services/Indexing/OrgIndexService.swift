import Foundation
import OrgTreeSitter

actor OrgIndexService {
    private final class Entry {
        let syntax = OrgDocumentSyntaxCache()
        var result: ParsedOrgDocument?
        var configuration: WorkspaceConfiguration?
        var title: String?
        var headings: [String: IndexedOrgHeading] = [:]
        var accessed: UInt64 = 0
    }
    private var documents: [String: Entry] = [:]
    private var access: UInt64 = 0

    func remove(paths: Set<String>) {
        for path in paths { documents.removeValue(forKey: path) }
    }

    func parse(_ documents: [WorkspaceDocument], configuration: WorkspaceConfiguration = .standard) -> [ParsedOrgDocument] {
        var parsed: [ParsedOrgDocument] = []
        parsed.reserveCapacity(documents.count)

        for document in documents {
            guard !Task.isCancelled else { break }
            let entry = self.documents[document.path] ?? Entry()
            if let result = Self.parse(document, using: entry, configuration: configuration) {
                access &+= 1
                entry.accessed = access
                self.documents[document.path] = entry
                parsed.append(result)
                trimCache(keeping: document.path)
            }
        }

        return parsed
    }

    private func trimCache(keeping path: String) {
        var bytes = documents.values.reduce(0) { $0 + ($1.result?.root.endByte ?? 0) }
        guard documents.count > 128 || bytes > 32 * 1024 * 1024 else { return }
        for (key, entry) in documents.sorted(by: { $0.value.accessed < $1.value.accessed }) where key != path {
            guard documents.count > 128 || bytes > 32 * 1024 * 1024 else { break }
            bytes -= entry.result?.root.endByte ?? 0
            documents.removeValue(forKey: key)
        }
    }

    nonisolated static func parseSynchronously(
        _ documents: [WorkspaceDocument], configuration: WorkspaceConfiguration = .standard
    ) -> [ParsedOrgDocument] {
        return documents.compactMap { parse($0, using: Entry(), configuration: configuration) }
    }

    private static func parse(
        _ document: WorkspaceDocument,
        using entry: Entry, configuration: WorkspaceConfiguration
    ) -> ParsedOrgDocument? {
        guard document.kind == .org else { return nil }
        if let result = entry.result, entry.configuration == configuration, entry.title == document.title,
           result.root.text.utf8.elementsEqual(document.contents.utf8) { return result }
        let update = entry.syntax.update(document.contents, path: document.path, configuration: configuration)
        let tree = update.tree
        let workflow = entry.syntax.workflow!
        let root = entry.syntax.root!
        let headings = indexHeadings(tree.rootNode.namedChildren, path: document.path, root: root, workflow: workflow,
                                     previous: entry.headings, reused: entry.syntax.reusedBlockIDs)
        let result = ParsedOrgDocument(
            path: document.path,
            root: root,
            headings: headings,
            hasError: tree.hasError,
            journalEntries: JournalFileIndex.entries(in: document, directory: configuration.files.journal,
                                                     previous: entry.result?.journalEntries ?? [], update: update)
        )
        entry.headings = Dictionary(uniqueKeysWithValues: zip(root.children.filter { $0.type == "heading" }.map(\.id), headings))
        entry.result = result
        entry.configuration = configuration
        entry.title = document.title
        return result
    }

    private static func indexHeadings(_ blocks: [OrgSyntaxNode], path: String, root: ParsedOrgNode,
                                      workflow: WorkspaceConfiguration.Workflow,
                                      previous: [String: IndexedOrgHeading], reused: Set<String>) -> [IndexedOrgHeading] {
        var headings: [IndexedOrgHeading] = []
        var ancestors: [(level: Int, title: String)] = []

        for (index, node) in blocks.enumerated() where node.type == "heading" {
            // Normalization preserves the root's children and their order.
            let semantic = root.children[index]
            let level = semantic.text.prefix { $0 == "*" }.count
            while let ancestor = ancestors.last, ancestor.level >= level {
                ancestors.removeLast()
            }
            let following = Array(root.children.dropFirst(index + 1).prefix { $0.type != "heading" })
            let source = SourceLocation(file: path, startByte: Int(node.startByte),
                                        endByte: following.last?.endByte ?? Int(node.endByte),
                                        startLine: Int(node.startPoint.row) + 1,
                                        ancestorTitles: ancestors.map(\.title))
            if reused.contains(semantic.id), following.allSatisfy({ reused.contains($0.id) }),
               var cached = previous[semantic.id],
               cached.source.endByte - cached.source.startByte == source.endByte - source.startByte {
                cached.source = source
                headings.append(cached)
                ancestors.append((level, cached.title))
                continue
            }
            let planning = following.filter { $0.type == "planning" }.map(\.text).joined(separator: "\n")
            let body = OrgHeadingBody.editableNodes(in: following)
                .map(\.text)
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            let rawState = semantic.todoNode?.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let state = rawState.flatMap(workflow.state)
            let priority = parsePriority(semantic.child(ofType: "priority")?.text)
            let title = (semantic.child(ofType: "heading_title")?.text ?? String(localized: "Untitled"))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let tags = node.child(named: "tags")?.text.split(separator: ":")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty } ?? []
            let scheduledMatch = planningLine(named: "SCHEDULED", in: planning)
            let deadlineMatch = planningLine(named: "DEADLINE", in: planning)
            let closedMatch = planningLine(named: "CLOSED", in: planning)
            let scheduled = scheduledMatch.flatMap(parseTimestamp)
            let deadline = deadlineMatch.flatMap(parseTimestamp)
            let closed = closedMatch.flatMap(parseTimestamp)
            let eventMatch = OrgHeadingBody.firstActiveTimestamp(in: following)?.text
            let eventDate = eventMatch.flatMap(parseTimestamp)
            let primaryTimestamp = scheduledMatch ?? deadlineMatch ?? eventMatch ?? ""
            let recurrence = primaryTimestamp.firstMatch(of: #/(?:\+\+|\.\+|\+)\d+[hdwmy](?:/\d+[hdwmy])?/#)
                .map { String($0.output) }
            let hasTime = primaryTimestamp.contains(#/\d{2}:\d{2}/#)
            let properties = following.filter { $0.type == "property_drawer" }
                .flatMap(\.children).filter { $0.type == "property" }
                .reduce(into: [String: String]()) { result, property in
                    guard let name = property.child(ofType: "property_name")?.text else { return }
                    result[name.uppercased()] = property.child(ofType: "property_value")?.text
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                }

            headings.append(
                IndexedOrgHeading(
                    title: title,
                    state: state,
                    priority: priority,
                    tags: tags,
                    scheduled: scheduled,
                    deadline: deadline,
                    closed: closed,
                    eventDate: eventDate,
                    hasTime: hasTime,
                    recurrence: recurrence,
                    body: body,
                    source: source,
                    durationMinutes: timestampDuration(primaryTimestamp, hasTime: hasTime),
                    properties: properties
                )
            )
            ancestors.append((level, title))
        }

        return headings
    }

    private static func parsePriority(_ text: String?) -> OrgPriority {
        guard let text else { return .none }
        let token = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard token.hasPrefix("[#"), token.hasSuffix("]") else { return .none }
        return OrgPriority(rawValue: String(token.dropFirst(2).dropLast())) ?? .none
    }

    private static let planningLineExpressions: [String: NSRegularExpression] = {
        ["SCHEDULED", "DEADLINE", "CLOSED"].reduce(into: [:]) { result, name in
            let pattern = "\(name):[ \\t]*(<[^>\\r\\n]+>|\\[[^]\\r\\n]+\\])(?:--(<[^>\\r\\n]+>|\\[[^]\\r\\n]+\\]))?"
            result[name] = try! NSRegularExpression(pattern: pattern)
        }
    }()

    private static let timestampExpression = try! NSRegularExpression(
        pattern: #"(\d{4})-(\d{2})-(\d{2})(?:\s+[[:alpha:]]+)?(?:\s+(\d{2}):(\d{2}))?"#
    )

    private static let timeRangeEndExpression = try! NSRegularExpression(
        pattern: #"\d{2}:\d{2}-(\d{2}):(\d{2})"#
    )

    private static func planningLine(named name: String, in planning: String) -> String? {
        guard
            let regex = planningLineExpressions[name],
            let match = regex.firstMatch(in: planning, range: NSRange(planning.startIndex..., in: planning)),
            let firstRange = Range(match.range(at: 1), in: planning)
        else { return nil }
        if let secondRange = Range(match.range(at: 2), in: planning) {
            return String(planning[firstRange.lowerBound..<secondRange.upperBound])
        }
        return String(planning[firstRange])
    }

    private static func parseTimestamp(_ timestamp: String) -> Date? {
        guard
            let match = timestampExpression.firstMatch(in: timestamp, range: NSRange(timestamp.startIndex..., in: timestamp))
        else { return nil }

        func integer(_ capture: Int) -> Int? {
            guard let range = Range(match.range(at: capture), in: timestamp)
            else { return nil }
            return Int(timestamp[range])
        }

        guard let year = integer(1), let month = integer(2), let day = integer(3) else { return nil }
        return Date.orgTimestamp(year: year, month: month, day: day,
                                 hour: integer(4) ?? 0, minute: integer(5) ?? 0)
    }

    private static func timestampDuration(_ timestamp: String, hasTime: Bool) -> Int {
        guard let start = parseTimestamp(timestamp) else { return 0 }
        if let separator = timestamp.range(of: "--"),
           let end = parseTimestamp(String(timestamp[separator.upperBound...])), end >= start {
            return Int(end.timeIntervalSince(start) / 60)
        }
        guard hasTime else { return 0 }
        guard let match = timeRangeEndExpression.firstMatch(in: timestamp, range: NSRange(timestamp.startIndex..., in: timestamp)),
              let hourRange = Range(match.range(at: 1), in: timestamp),
              let minuteRange = Range(match.range(at: 2), in: timestamp),
              let hour = Int(timestamp[hourRange]), let minute = Int(timestamp[minuteRange]),
              (0...23).contains(hour), (0...59).contains(minute) else { return 30 }
        let calendar = Calendar.current
        let startMinutes = calendar.component(.hour, from: start) * 60 + calendar.component(.minute, from: start)
        let difference = hour * 60 + minute - startMinutes
        return difference >= 0 ? difference : difference + 24 * 60
    }

}
