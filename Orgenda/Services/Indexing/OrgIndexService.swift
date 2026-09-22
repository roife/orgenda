import Foundation
import OrgTreeSitter

actor OrgIndexService {
    private let parser = OrgParser()

    func journalEntries(in documents: [WorkspaceDocument]) -> [JournalEntry] {
        JournalFileIndex.entries(in: documents)
    }

    func parse(_ documents: [WorkspaceDocument]) -> [ParsedOrgDocument] {
        var parsed: [ParsedOrgDocument] = []
        parsed.reserveCapacity(documents.count)

        for document in documents {
            guard !Task.isCancelled else { break }
            if let result = Self.parse(document, using: parser) {
                parsed.append(result)
            }
        }

        return parsed
    }

    nonisolated static func parseSynchronously(
        _ documents: [WorkspaceDocument]
    ) -> [ParsedOrgDocument] {
        let parser = OrgParser()
        return documents.compactMap { parse($0, using: parser) }
    }

    private static func parse(
        _ document: WorkspaceDocument,
        using parser: OrgParser
    ) -> ParsedOrgDocument? {
        guard document.kind == .org else { return nil }
        let tree = parser.parse(document.contents)
        let root = snapshot(tree.rootNode, path: document.path)
        return ParsedOrgDocument(
            path: document.path,
            root: root,
            headings: indexHeadings(tree.rootNode.namedChildren, path: document.path),
            hasError: tree.hasError
        )
    }

    private static func snapshot(_ node: OrgSyntaxNode, path: String) -> ParsedOrgNode {
        ParsedOrgNode(
            id: "\(path):\(node.startByte):\(node.endByte):\(node.type)",
            type: node.type,
            text: node.text,
            startByte: Int(node.startByte),
            endByte: Int(node.endByte),
            children: node.namedChildren.map { snapshot($0, path: path) }
        )
    }

    private static func indexHeadings(_ blocks: [OrgSyntaxNode], path: String) -> [IndexedOrgHeading] {
        var headings: [IndexedOrgHeading] = []

        for (index, node) in blocks.enumerated() where node.type == "heading" {
            let following = blocks.dropFirst(index + 1).prefix { $0.type != "heading" }
            let bodyBlocks = following.map { snapshot($0, path: path) }
            let planning = following.filter { $0.type == "planning" }.map(\.text).joined(separator: "\n")
            let body = OrgHeadingBody.editableNodes(in: bodyBlocks)
                .map(\.text)
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            let rawState = node.child(named: "todo")?.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let state = rawState.flatMap(OrgWorkflowState.init(rawValue:))
            let priority = parsePriority(node.child(named: "priority")?.text)
            let title = (node.child(named: "title")?.text ?? String(localized: "Untitled"))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let tags = parseTags(node.child(named: "tags")?.text)
            let scheduledMatch = planningLine(named: "SCHEDULED", in: planning)
            let deadlineMatch = planningLine(named: "DEADLINE", in: planning)
            let closedMatch = planningLine(named: "CLOSED", in: planning)
            let scheduled = scheduledMatch.flatMap(parseTimestamp)
            let deadline = deadlineMatch.flatMap(parseTimestamp)
            let closed = closedMatch.flatMap(parseTimestamp)
            let eventMatch = OrgHeadingBody.firstActiveTimestamp(in: bodyBlocks)?.text
            let eventDate = eventMatch.flatMap(parseTimestamp)
            let primaryTimestamp = scheduledMatch ?? deadlineMatch ?? eventMatch ?? ""
            let recurrence = parseRecurrence(primaryTimestamp)
            let hasTime = clockTimeExpression?
                .firstMatch(in: primaryTimestamp, range: NSRange(primaryTimestamp.startIndex..., in: primaryTimestamp)) != nil
            let properties = following.filter { $0.type == "property_drawer" }
                .flatMap(\.namedChildren).filter { $0.type == "property" }
                .reduce(into: [String: String]()) { result, property in
                    guard let name = property.child(named: "name")?.text else { return }
                    result[name.uppercased()] = property.child(named: "value")?.text
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
                    source: SourceLocation(
                        file: path,
                        startByte: Int(node.startByte),
                        endByte: Int(following.last?.endByte ?? node.endByte),
                        startLine: Int(node.startPoint.row) + 1
                    ),
                    durationMinutes: timestampDuration(primaryTimestamp, hasTime: hasTime),
                    properties: properties
                )
            )
        }

        return headings
    }

    private static func parsePriority(_ text: String?) -> OrgPriority {
        guard let text else { return .none }
        if text.contains("#A") { return .high }
        if text.contains("#B") { return .medium }
        if text.contains("#C") { return .low }
        return .none
    }

    private static func parseTags(_ text: String?) -> [String] {
        guard let text else { return [] }
        return text
            .split(separator: ":")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static let planningLineExpressions: [String: NSRegularExpression] = {
        ["SCHEDULED", "DEADLINE", "CLOSED"].reduce(into: [:]) { result, name in
            let pattern = "\(name):[ \\t]*(<[^>\\r\\n]+>|\\[[^]\\r\\n]+\\])(?:--(<[^>\\r\\n]+>|\\[[^]\\r\\n]+\\]))?"
            result[name] = try? NSRegularExpression(pattern: pattern)
        }
    }()

    private static let timestampExpression = try? NSRegularExpression(
        pattern: #"(\d{4})-(\d{2})-(\d{2})(?:\s+[[:alpha:]]+)?(?:\s+(\d{2}):(\d{2}))?"#
    )

    private static let timeRangeEndExpression = try? NSRegularExpression(
        pattern: #"\d{2}:\d{2}-(\d{2}):(\d{2})"#
    )

    private static let recurrenceExpression = try? NSRegularExpression(
        pattern: #"(?:\+\+|\.\+|\+)\d+[hdwmy](?:/\d+[hdwmy])?"#
    )

    private static let clockTimeExpression = try? NSRegularExpression(pattern: #"\d{2}:\d{2}"#)

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
            let regex = timestampExpression,
            let match = regex.firstMatch(in: timestamp, range: NSRange(timestamp.startIndex..., in: timestamp))
        else { return nil }

        func integer(_ capture: Int) -> Int? {
            guard match.range(at: capture).location != NSNotFound,
                  let range = Range(match.range(at: capture), in: timestamp)
            else { return nil }
            return Int(timestamp[range])
        }

        var components = DateComponents()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        components.calendar = calendar
        components.timeZone = .autoupdatingCurrent
        components.year = integer(1)
        components.month = integer(2)
        components.day = integer(3)
        components.hour = integer(4) ?? 0
        components.minute = integer(5) ?? 0
        guard let date = components.date else { return nil }
        let validated = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        guard validated.year == components.year, validated.month == components.month,
              validated.day == components.day, validated.hour == components.hour,
              validated.minute == components.minute else { return nil }
        return date
    }

    private static func timestampDuration(_ timestamp: String, hasTime: Bool) -> Int {
        guard let start = parseTimestamp(timestamp) else { return 0 }
        if let separator = timestamp.range(of: "--"),
           let end = parseTimestamp(String(timestamp[separator.upperBound...])), end >= start {
            return Int(end.timeIntervalSince(start) / 60)
        }
        guard hasTime else { return 0 }
        guard let expression = timeRangeEndExpression,
              let match = expression.firstMatch(in: timestamp, range: NSRange(timestamp.startIndex..., in: timestamp)),
              let hourRange = Range(match.range(at: 1), in: timestamp),
              let minuteRange = Range(match.range(at: 2), in: timestamp),
              let hour = Int(timestamp[hourRange]), let minute = Int(timestamp[minuteRange]),
              (0...23).contains(hour), (0...59).contains(minute) else { return 30 }
        let calendar = Calendar.current
        let startMinutes = calendar.component(.hour, from: start) * 60 + calendar.component(.minute, from: start)
        let difference = hour * 60 + minute - startMinutes
        return difference >= 0 ? difference : difference + 24 * 60
    }

    private static func parseRecurrence(_ timestamp: String) -> String? {
        guard
            let regex = recurrenceExpression,
            let match = regex.firstMatch(in: timestamp, range: NSRange(timestamp.startIndex..., in: timestamp)),
            let range = Range(match.range, in: timestamp)
        else { return nil }
        return String(timestamp[range])
    }
}
