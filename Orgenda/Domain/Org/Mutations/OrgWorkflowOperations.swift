import Foundation
import OrgTreeSitter

struct OrgArchiveDestination: Hashable, Sendable {
    let path: String
    /// Org's archive location names one heading, including its leading stars.
    let outline: String?
}

struct OrgRefileTarget: Identifiable, Hashable, Sendable {
    var id: String { "\(path):\(headingStartByte)" }
    let path: String
    let headingStartByte: Int
    let title: String
    let outline: String
    let level: Int
}

struct OrgMovePlan: Sendable {
    let source: WorkspaceDocument
    let destination: WorkspaceDocument
}

/// Pure source operations. Persistence must save the destination successfully
/// before removing source bytes, and compare both original snapshots first.
enum OrgWorkflowOperations {
    enum Failure: Error, Equatable, LocalizedError {
        case missingHeading
        case ambiguousStructure
        case noteRequired
        case unsafeArchivePath
        case invalidTarget
        case targetInsideSubtree

        var errorDescription: String? {
            switch self {
            case .missingHeading: String(localized: "The heading changed. Reload it before trying again.")
            case .ambiguousStructure: String(localized: "The Org structure is ambiguous. Check its drawers and blocks before trying again.")
            case .noteRequired: String(localized: "This state requires a reason in the logbook.")
            case .unsafeArchivePath: String(localized: "The archive location must be a supported file inside this workspace.")
            case .invalidTarget: String(localized: "The destination heading changed or is not an allowed refile target.")
            case .targetInsideSubtree: String(localized: "A subtree cannot be moved into itself or one of its children.")
            }
        }
    }

    static func requiresNote(from: OrgWorkflowState, to: OrgWorkflowState) -> Bool {
        from.rawValue != to.rawValue && (to.enterLog == .note || from.leaveLog == .note)
    }

    static func normalized(_ item: OrgItem, replacing original: OrgItem, now: Date = Date()) -> OrgItem {
        var item = item
        if original.state.rawValue != item.state.rawValue {
            if item.state.isTerminal { item.closed = now }
            else if original.state.isTerminal { item.closed = nil }
        }
        return item
    }

    /// Invoke after semantic item edits, using the unchanged start of the heading.
    /// Providing the old snapshot keeps repeater/warning/range text in date logs.
    static func applyingLogs(
        to source: String, headingStartByte: Int,
        replacing original: OrgItem, with item: OrgItem,
        note: String? = nil, now: Date = Date(), originalSource: String? = nil,
        logging: WorkspaceConfiguration.Logging
    ) throws -> String {
        let cleanNote = note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let doneLog = original.state.rawValue != item.state.rawValue && item.state.isTerminal ? logging.done : .none
        let dateNote = (original.scheduled != item.scheduled && logging.reschedule == .note)
            || (original.deadline != item.deadline && logging.redeadline == .note)
        if (requiresNote(from: original.state, to: item.state) || doneLog == .note || dateNote), cleanNote.isEmpty {
            throw Failure.noteRequired
        }
        var entries: [String] = []
        let stamp = now.orgTimestamp(active: false, includesTime: true)
        let escapedNote = cleanNote.components(separatedBy: .newlines).map {
            // An indented :END: still closes an Org drawer. Escape that
            // literal note line so the next edit sees the same logbook.
            let text = $0.trimmingCharacters(in: .whitespaces)
            return "  " + (text.uppercased() == ":END:" ? "," + $0 : $0)
        }.joined(separator: "\n")
        if original.state.rawValue != item.state.rawValue,
           item.state.enterLog != .none || original.state.leaveLog != .none || doneLog != .none {
            var entry = "- State \"\(item.state.rawValue)\" from \"\(original.state.rawValue)\" \(stamp)"
            if !cleanNote.isEmpty {
                entry += " \\\\\n" + escapedNote
            }
            entries.append(entry)
        }
        let oldPrimary: OrgPlanningKeyword = original.scheduled != nil ? .scheduled : .deadline
        let newPrimary: OrgPlanningKeyword = item.scheduled != nil ? .scheduled : .deadline
        let dateChanges = [OrgPlanningKeyword.scheduled, .deadline].compactMap { keyword -> (OrgPlanningKeyword, Date, Date?)? in
            guard (keyword == .scheduled ? logging.reschedule : logging.redeadline) != .none else { return nil }
            let oldDate = keyword == .scheduled ? original.scheduled : original.deadline
            let newDate = keyword == .scheduled ? item.scheduled : item.deadline
            let recurrenceChanged = oldPrimary == keyword && newPrimary == keyword && original.recurrence != item.recurrence
            guard let oldDate,
                  oldDate != newDate || original.hasTime != item.hasTime || recurrenceChanged else { return nil }
            return (keyword, oldDate, newDate)
        }
        let originalStructure = try dateChanges.isEmpty ? nil : originalSource.map(Structure.init)
        for (keyword, oldDate, newDate) in dateChanges {
            let oldStamp = try originalStructure.flatMap {
                try planningTimestamp(in: $0, headingStartByte: headingStartByte, keyword: keyword)
            } ?? oldDate.orgTimestamp(active: false, includesTime: original.hasTime,
                                     recurrence: oldPrimary == keyword ? original.recurrence : nil)
            let action: String
            switch (keyword, newDate == nil) {
            case (.scheduled, false): action = "Rescheduled from"
            case (.scheduled, true): action = "Not scheduled, was"
            case (.deadline, false): action = "New deadline from"
            default: action = "Removed deadline, was"
            }
            entries.append("- \(action) \"\(oldStamp)\" on \(stamp)" + (dateNote && !cleanNote.isEmpty ? " \\\\\n" + escapedNote : ""))
        }
        guard !entries.isEmpty else { return source }
        let structure = try Structure(source)
        let heading = try structure.heading(at: headingStartByte)
        let section = structure.section(of: heading)
        let drawers = section.filter {
            $0.type == "drawer" && $0.child(named: "begin")?.text.trimmingCharacters(in: .whitespaces)
                .dropFirst().dropLast().uppercased() == logging.drawer.uppercased()
        }
        guard drawers.count <= 1 else { throw Failure.ambiguousStructure }
        let newline = structure.newline
        let body = entries.joined(separator: "\n").replacingOccurrences(of: "\n", with: newline) + newline
        if let drawer = drawers.first {
            let contentStart = Int(drawer.startByte) + drawer.text.utf8.prefix { $0 != 10 }.count + 1
            return try OrgSourceMutation(startByte: contentStart, endByte: contentStart,
                                         replacement: body).applied(to: source)
        }
        // Keep planning and property metadata directly below the headline.
        var insertion = heading.end
        for node in section.prefix(while: { ["property_drawer", "planning", "blank_line"].contains($0.type) }) {
            insertion = Int(node.endByte)
        }
        let prefix = insertion > 0 && source.utf8.prefix(insertion).last != 10 ? newline : ""
        let log = logging.drawer.isEmpty ? body : ":\(logging.drawer):" + newline + body + ":END:" + newline
        return try OrgSourceMutation(startByte: insertion, endByte: insertion,
                                     replacement: prefix + log).applied(to: source)
    }

    static func archiveDestination(
        sourcePath: String, source: String, headingStartByte: Int, defaultLocation: String
    ) throws -> OrgArchiveDestination {
        let structure = try Structure(source)
        let heading = try structure.heading(at: headingStartByte)
        let ancestors = structure.ancestors(of: heading) + [heading]
        let preambleEnd = structure.headings.first?.start ?? structure.byteCount
        let fileProperties = structure.blocks.filter { Int($0.startByte) < preambleEnd && $0.type == "keyword" }
            .compactMap { capture(fileArchiveExpression, in: $0.text) }
        guard fileProperties.count <= 1 else { throw Failure.ambiguousStructure }
        var custom = fileProperties.first
        for ancestor in ancestors {
            let drawers = structure.section(of: ancestor).filter { $0.type == "property_drawer" }
            guard drawers.count <= 1 else { throw Failure.ambiguousStructure }
            if let drawer = drawers.first {
                let values = drawer.namedChildren.filter {
                    $0.type == "property" && $0.child(named: "name")?.text.uppercased() == "ARCHIVE"
                }.map { $0.child(named: "value")?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
                guard values.count <= 1 else { throw Failure.ambiguousStructure }
                if let value = values.first { custom = value }
            }
        }
        let filename = (sourcePath as NSString).lastPathComponent
        let directory = (sourcePath as NSString).deletingLastPathComponent
        let location = (custom ?? defaultLocation).replacingOccurrences(of: "%s", with: filename)
        let pieces = location.components(separatedBy: "::")
        guard pieces.count == 2 else { throw Failure.unsafeArchivePath }
        let relative = pieces[0].trimmingCharacters(in: .whitespaces)
        guard !relative.isEmpty, !relative.hasPrefix("/"), !relative.hasPrefix("~"),
              !relative.contains(":"), !relative.contains("\n"), !relative.contains("\\"),
              !relative.contains("%") else { throw Failure.unsafeArchivePath }
        var components = directory.isEmpty ? [] : directory.components(separatedBy: "/")
        for component in relative.components(separatedBy: "/") {
            if component == "." || component.isEmpty { continue }
            if component == ".." {
                guard !components.isEmpty else { throw Failure.unsafeArchivePath }
                components.removeLast()
            } else { components.append(component) }
        }
        let path = components.joined(separator: "/")
        guard path.hasSuffix(".org") || path.hasSuffix(".org_archive") else { throw Failure.unsafeArchivePath }
        let outline = pieces[1].trimmingCharacters(in: .whitespaces)
        if !outline.isEmpty {
            guard matches(archiveHeadingExpression, in: outline),
                  !outline.contains("\n"), !outline.contains("\r") else { throw Failure.invalidTarget }
        }
        return OrgArchiveDestination(path: path, outline: outline.isEmpty ? nil : outline)
    }

    static func refileTargets(in documents: [WorkspaceDocument], refilePaths: Set<String>,
                              maxLevel: Int = 3) -> [OrgRefileTarget] {
        documents.filter { $0.kind == .org && refilePaths.contains($0.path) }.flatMap { document -> [OrgRefileTarget] in
            guard let structure = try? Structure(document.contents) else { return [] }
            return structure.headings.filter { $0.level <= maxLevel }.map { heading in
                OrgRefileTarget(path: document.path, headingStartByte: heading.start, title: heading.title,
                                outline: (structure.ancestors(of: heading) + [heading]).map(\.title).joined(separator: "/"),
                                level: heading.level)
            }
        }.sorted { $0.path == $1.path ? $0.headingStartByte < $1.headingStartByte : $0.path < $1.path }
    }

    static func refile(
        source: WorkspaceDocument, headingStartByte: Int,
        destination: WorkspaceDocument, target: OrgRefileTarget,
        refilePaths: Set<String>, maxLevel: Int = 3
    ) throws -> OrgMovePlan {
        guard refilePaths.contains(destination.path), target.path == destination.path, target.level <= maxLevel else {
            throw Failure.invalidTarget
        }
        let structure = try Structure(destination.contents)
        let heading = try structure.heading(at: target.headingStartByte)
        guard heading.level == target.level, heading.title == target.title,
              (structure.ancestors(of: heading) + [heading]).map(\.title).joined(separator: "/") == target.outline else {
            throw Failure.invalidTarget
        }
        return try move(source: source, headingStartByte: headingStartByte,
                        destination: destination, targetHeadingStartByte: heading.start)
    }

    static func archive(
        source: WorkspaceDocument, headingStartByte: Int,
        destination: WorkspaceDocument, defaultLocation: String
    ) throws -> OrgMovePlan {
        let location = try archiveDestination(sourcePath: source.path, source: source.contents,
                                              headingStartByte: headingStartByte, defaultLocation: defaultLocation)
        guard destination.path == location.path else { throw Failure.invalidTarget }
        guard let outline = location.outline else {
            return try move(source: source, headingStartByte: headingStartByte, destination: destination,
                            targetHeadingStartByte: nil)
        }
        var destination = destination
        let structure = try Structure(destination.contents)
        let matching = structure.headings.filter { $0.rawTitle == outline }
        guard matching.count <= 1 else { throw Failure.ambiguousStructure }
        let targetStart: Int
        if let heading = matching.first { targetStart = heading.start }
        else {
            let separator = destination.contents.isEmpty || destination.contents.utf8.last == 10 ? "" : structure.newline
            targetStart = destination.contents.utf8.count + separator.utf8.count
            destination.contents += separator + outline + structure.newline
        }
        // Appending an archive heading in the same file would change the source
        // snapshot; pass the same prepared document through the combined move.
        let preparedSource = source.path == destination.path ? destination : source
        return try move(source: preparedSource, headingStartByte: headingStartByte,
                        destination: destination, targetHeadingStartByte: targetStart)
    }

    /// Only parsed structural headings are indented, never source/example blocks
    /// or drawer contents that happen to contain leading stars.
    static func move(
        source: WorkspaceDocument, headingStartByte: Int,
        destination: WorkspaceDocument, targetHeadingStartByte: Int?
    ) throws -> OrgMovePlan {
        guard source.kind == .org, destination.kind == .org else { throw Failure.invalidTarget }
        let sameFile = source.path == destination.path
        guard !sameFile || source.contents == destination.contents else { throw Failure.invalidTarget }
        let from = try Structure(source.contents)
        let heading = try from.heading(at: headingStartByte)
        let end = from.subtreeEnd(of: heading)
        let into = try sameFile ? from : Structure(destination.contents)
        let target = try targetHeadingStartByte.map { try into.heading(at: $0) }
        let insertion = target.map { into.subtreeEnd(of: $0) } ?? destination.contents.utf8.count
        if sameFile, let target, target.start >= heading.start && target.start < end { throw Failure.targetInsideSubtree }
        let levelChange = (target.map { $0.level + 1 } ?? 1) - heading.level
        var subtree = String(decoding: source.contents.utf8.dropFirst(heading.start).prefix(end - heading.start), as: UTF8.self)
        for child in from.headings.filter({ $0.start >= heading.start && $0.start < end }).reversed() {
            let newLevel = child.level + levelChange
            subtree = try OrgSourceMutation(startByte: child.start - heading.start,
                                            endByte: child.start - heading.start + child.level,
                                            replacement: String(repeating: "*", count: newLevel)).applied(to: subtree)
        }
        if subtree.utf8.last != 10 { subtree += into.newline }
        let prefix = insertion > 0 && destination.contents.utf8.prefix(insertion).last != 10 ? into.newline : ""
        let remove = OrgSourceMutation(startByte: heading.start, endByte: end, replacement: "")
        let insert = OrgSourceMutation(startByte: insertion, endByte: insertion, replacement: prefix + subtree)
        var newSource = source
        var newDestination = destination
        if sameFile {
            let mutations = [remove, insert].sorted {
                $0.startByte == $1.startByte ? $0.endByte > $1.endByte : $0.startByte > $1.startByte
            }
            newSource.contents = try mutations.reduce(source.contents) { try $1.applied(to: $0) }
            newDestination.contents = newSource.contents
        } else {
            newSource.contents = try remove.applied(to: source.contents)
            newDestination.contents = try insert.applied(to: destination.contents)
        }
        return OrgMovePlan(source: newSource, destination: newDestination)
    }

    private static func planningTimestamp(in structure: Structure, headingStartByte: Int, keyword: OrgPlanningKeyword) throws -> String? {
        let heading = try structure.heading(at: headingStartByte)
        let values = structure.section(of: heading).filter { $0.type == "planning" }
            .flatMap(\.namedChildren).filter {
                $0.type == "planning_entry" && $0.child(named: "keyword")?.text == keyword.rawValue + ":"
            }.compactMap { $0.child(named: "value")?.text }
        guard values.count <= 1 else { throw Failure.ambiguousStructure }
        return values.first.map { $0.replacingOccurrences(of: "<", with: "[").replacingOccurrences(of: ">", with: "]") }
    }

    private static func matches(_ expression: NSRegularExpression, in text: String) -> Bool {
        expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    private static let fileArchiveExpression = try! NSRegularExpression(
        pattern: #"^\s*#\+PROPERTY:\s+ARCHIVE\s+(.*?)\s*$"#, options: [.caseInsensitive]
    )
    private static let archiveHeadingExpression = try! NSRegularExpression(pattern: #"^\*+[ \t]+\S.*$"#)

    private static func capture(_ expression: NSRegularExpression, in source: String) -> String? {
        guard let match = expression.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)),
              let range = Range(match.range(at: 1), in: source) else { return nil }
        return String(source[range])
    }

    private struct Heading {
        let start: Int
        let end: Int
        let level: Int
        let title: String
        let rawTitle: String
    }
    /// Structural edits use the same containers and byte ranges as indexing.
    private struct Structure {
        let blocks: [OrgSyntaxNode]
        let headings: [Heading]
        let byteCount: Int
        let newline: String

        init(_ source: String) throws {
            let tree = OrgParser().parse(source)
            guard !tree.hasIncompleteStructure else { throw Failure.ambiguousStructure }
            blocks = tree.rootNode.namedChildren
            byteCount = source.utf8.count
            newline = source.contains("\r\n") ? "\r\n" : "\n"
            headings = blocks.filter { $0.type == "heading" }.map { node in
                let level = node.child(named: "marker")!.text.prefix { $0 == "*" }.count
                let rawTitle = node.text.trimmingCharacters(in: .whitespacesAndNewlines)
                return Heading(start: Int(node.startByte), end: Int(node.endByte), level: level,
                               title: String(rawTitle.dropFirst(level)).trimmingCharacters(in: .whitespaces),
                               rawTitle: rawTitle)
            }
        }

        func heading(at start: Int) throws -> Heading {
            guard let heading = headings.first(where: { $0.start == start }) else { throw Failure.missingHeading }
            return heading
        }
        func section(of heading: Heading) -> ArraySlice<OrgSyntaxNode> {
            blocks.drop { Int($0.startByte) < heading.end }.prefix { $0.type != "heading" }
        }
        func subtreeEnd(of heading: Heading) -> Int {
            headings.first(where: { $0.start > heading.start && $0.level <= heading.level })?.start ?? byteCount
        }
        func ancestors(of heading: Heading) -> [Heading] {
            var result: [Heading] = []
            for candidate in headings where candidate.start < heading.start {
                while let last = result.last, last.level >= candidate.level { result.removeLast() }
                result.append(candidate)
            }
            while let last = result.last, last.level >= heading.level { result.removeLast() }
            return result
        }
    }
}
