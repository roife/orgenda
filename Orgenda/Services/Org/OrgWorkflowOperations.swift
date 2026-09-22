import Foundation

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
        from != to && [.wait, .canceled].contains(to)
    }

    static func normalized(_ item: OrgItem, replacing original: OrgItem, now: Date = Date()) -> OrgItem {
        var item = item
        if original.state != item.state {
            if item.state.isTerminal { item.closed = now }
            else if original.state.isTerminal && !item.state.isTerminal { item.closed = nil }
        }
        return item
    }

    /// Invoke after semantic item edits, using the unchanged start of the heading.
    /// Providing the old snapshot keeps repeater/warning/range text in date logs.
    static func applyingLogs(
        to source: String, headingStartByte: Int,
        replacing original: OrgItem, with item: OrgItem,
        note: String? = nil, now: Date = Date(), originalSource: String? = nil
    ) throws -> String {
        let cleanNote = note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if requiresNote(from: original.state, to: item.state), cleanNote.isEmpty {
            throw Failure.noteRequired
        }
        var entries: [String] = []
        let stamp = timestamp(now, includesTime: true)
        if original.state != item.state,
           requiresNote(from: original.state, to: item.state)
            || [.urgent, .done].contains(item.state)
            || original.state == .wait {
            var entry = "- State \"\(item.state.rawValue)\" from \"\(original.state.rawValue)\" \(stamp)"
            if !cleanNote.isEmpty {
                entry += " \\\\\n" + cleanNote.components(separatedBy: .newlines).map {
                    // An indented :END: still closes an Org drawer. Escape that
                    // literal note line so the next edit sees the same logbook.
                    let text = $0.trimmingCharacters(in: .whitespaces)
                    return "  " + (text.uppercased() == ":END:" ? "," + $0 : $0)
                }.joined(separator: "\n")
            }
            entries.append(entry)
        }
        for keyword in [OrgPlanningKeyword.scheduled, .deadline] {
            let oldDate = keyword == .scheduled ? original.scheduled : original.deadline
            let newDate = keyword == .scheduled ? item.scheduled : item.deadline
            let oldPrimary: OrgPlanningKeyword = original.scheduled != nil ? .scheduled : .deadline
            let newPrimary: OrgPlanningKeyword = item.scheduled != nil ? .scheduled : .deadline
            let recurrenceChanged = oldPrimary == keyword && newPrimary == keyword && original.recurrence != item.recurrence
            guard let oldDate,
                  oldDate != newDate || original.hasTime != item.hasTime || recurrenceChanged else { continue }
            let oldStamp = try originalSource.flatMap {
                try planningTimestamp(in: $0, headingStartByte: headingStartByte, keyword: keyword)
            } ?? timestamp(oldDate, includesTime: original.hasTime,
                           suffix: oldPrimary == keyword ? original.recurrence : nil)
            let action: String
            switch (keyword, newDate == nil) {
            case (.scheduled, false): action = "Rescheduled from"
            case (.scheduled, true): action = "Not scheduled, was"
            case (.deadline, false): action = "New deadline from"
            default: action = "Removed deadline, was"
            }
            entries.append("- \(action) \"\(oldStamp)\" on \(stamp)")
        }
        guard !entries.isEmpty else { return source }
        let structure = try Structure(source)
        let heading = try structure.heading(at: headingStartByte)
        let sectionEnd = structure.sectionEnd(of: heading)
        let drawers = structure.drawers.filter { $0.start > heading.start && $0.start < sectionEnd && $0.name == "LOGBOOK" }
        guard drawers.count <= 1 else { throw Failure.ambiguousStructure }
        let newline = structure.newline
        let body = entries.joined(separator: "\n").replacingOccurrences(of: "\n", with: newline) + newline
        if let drawer = drawers.first {
            return try OrgSourceMutation(startByte: drawer.contentStart, endByte: drawer.contentStart,
                                         replacement: body).applied(to: source)
        }
        // Keep planning and property metadata directly below the headline.
        var insertion = heading.end
        for line in structure.lines where line.start >= heading.end && line.start < sectionEnd {
            if let drawer = structure.drawers.first(where: { $0.start == line.start && $0.name == "PROPERTIES" }) {
                insertion = drawer.end
            } else if line.start < insertion { continue }
            else if line.text.trimmingCharacters(in: .whitespaces).isEmpty || matches(planningKeywordLineExpression, in: line.text) {
                insertion = line.end
            } else { break }
        }
        let prefix = insertion > 0 && !String(decoding: source.utf8.prefix(insertion), as: UTF8.self).hasSuffix("\n") ? newline : ""
        return try OrgSourceMutation(startByte: insertion, endByte: insertion,
                                     replacement: prefix + ":LOGBOOK:" + newline + body + ":END:" + newline).applied(to: source)
    }

    static func archiveDestination(
        sourcePath: String, source: String, headingStartByte: Int, now: Date = Date()
    ) throws -> OrgArchiveDestination {
        let structure = try Structure(source)
        let heading = try structure.heading(at: headingStartByte)
        let ancestors = structure.ancestors(of: heading) + [heading]
        let preambleEnd = structure.headings.first?.start ?? structure.byteCount
        let fileProperties = structure.lines.filter { $0.start < preambleEnd && !structure.isProtected($0.start) }
            .compactMap { capture(#"^\s*#\+PROPERTY:\s+ARCHIVE\s+(.*?)\s*$"#, in: $0.text) }
        guard fileProperties.count <= 1 else { throw Failure.ambiguousStructure }
        var custom = fileProperties.first
        for ancestor in ancestors {
            let end = structure.sectionEnd(of: ancestor)
            let drawers = structure.drawers.filter { $0.name == "PROPERTIES" && $0.start > ancestor.start && $0.start < end }
            guard drawers.count <= 1 else { throw Failure.ambiguousStructure }
            if let drawer = drawers.first {
                let properties = structure.lines.filter { $0.start >= drawer.contentStart && $0.start < drawer.closeStart }
                let values = properties.compactMap { capture(#"^\s*:ARCHIVE:\s*(.*?)\s*$"#, in: $0.text) }
                guard values.count <= 1 else { throw Failure.ambiguousStructure }
                if let value = values.first { custom = value }
            }
        }
        let filename = (sourcePath as NSString).lastPathComponent
        let directory = (sourcePath as NSString).deletingLastPathComponent
        let base = (filename as NSString).deletingPathExtension
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        let year = calendar.component(.year, from: now)
        let standard = "archives/\(base)-\(year).org::* Archived"
        let location = (custom ?? standard).replacingOccurrences(of: "%s", with: filename)
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
            guard capture(#"^(\*+)[ \t]+\S.*$"#, in: outline) != nil,
                  !outline.contains("\n"), !outline.contains("\r") else { throw Failure.invalidTarget }
        }
        return OrgArchiveDestination(path: path, outline: outline.isEmpty ? nil : outline)
    }

    static let refilePaths: Set<String> = [
        "agenda/actions.org", "agenda/work.org", "agenda/personal.org",
        "agenda/routines.org", "agenda/someday.org"
    ]

    static func refileTargets(in documents: [WorkspaceDocument]) -> [OrgRefileTarget] {
        documents.filter { $0.kind == .org && refilePaths.contains($0.path) }.flatMap { document -> [OrgRefileTarget] in
            guard let structure = try? Structure(document.contents) else { return [] }
            return structure.headings.filter { $0.level <= 3 }.map { heading in
                OrgRefileTarget(path: document.path, headingStartByte: heading.start, title: heading.title,
                                outline: (structure.ancestors(of: heading) + [heading]).map(\.title).joined(separator: "/"),
                                level: heading.level)
            }
        }.sorted { $0.path == $1.path ? $0.headingStartByte < $1.headingStartByte : $0.path < $1.path }
    }

    static func refile(
        source: WorkspaceDocument, headingStartByte: Int,
        destination: WorkspaceDocument, target: OrgRefileTarget
    ) throws -> OrgMovePlan {
        guard refilePaths.contains(destination.path), target.path == destination.path, target.level <= 3 else {
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
        destination: WorkspaceDocument, now: Date = Date()
    ) throws -> OrgMovePlan {
        let location = try archiveDestination(sourcePath: source.path, source: source.contents,
                                              headingStartByte: headingStartByte, now: now)
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
            let separator = destination.contents.isEmpty || destination.contents.hasSuffix("\n") ? "" : structure.newline
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
        let from = try Structure(source.contents)
        let heading = try from.heading(at: headingStartByte)
        let end = from.subtreeEnd(of: heading)
        let into = try Structure(destination.contents)
        let target = try targetHeadingStartByte.map { try into.heading(at: $0) }
        let insertion = target.map { into.subtreeEnd(of: $0) } ?? destination.contents.utf8.count
        let sameFile = source.path == destination.path
        guard !sameFile || source.contents == destination.contents else { throw Failure.invalidTarget }
        if sameFile, let target, target.start >= heading.start && target.start < end { throw Failure.targetInsideSubtree }
        let levelChange = (target.map { $0.level + 1 } ?? 1) - heading.level
        var subtree = String(decoding: source.contents.utf8.dropFirst(heading.start).prefix(end - heading.start), as: UTF8.self)
        for child in from.headings.filter({ $0.start >= heading.start && $0.start < end }).reversed() {
            let newLevel = child.level + levelChange
            guard newLevel > 0 else { throw Failure.invalidTarget }
            subtree = try OrgSourceMutation(startByte: child.start - heading.start,
                                            endByte: child.start - heading.start + child.level,
                                            replacement: String(repeating: "*", count: newLevel)).applied(to: subtree)
        }
        if !subtree.hasSuffix("\n") { subtree += into.newline }
        let prefix = insertion > 0 && !String(decoding: destination.contents.utf8.prefix(insertion), as: UTF8.self).hasSuffix("\n") ? into.newline : ""
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

    private static func timestamp(_ date: Date, includesTime: Bool, suffix: String? = nil) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = includesTime ? "yyyy-MM-dd EEE HH:mm" : "yyyy-MM-dd EEE"
        return "[" + formatter.string(from: date) + (suffix.map { " " + $0 } ?? "") + "]"
    }

    private static func planningTimestamp(in source: String, headingStartByte: Int, keyword: OrgPlanningKeyword) throws -> String? {
        let structure = try Structure(source)
        let heading = try structure.heading(at: headingStartByte)
        let end = structure.sectionEnd(of: heading)
        let candidates = structure.lines.filter {
            $0.start >= heading.end && $0.start < end && !structure.isProtected($0.start)
                && matches(planningKeywordLineExpression, in: $0.text)
        }
        let values = candidates.compactMap { capture("\\b\(keyword.rawValue):[ \\t]*(<[^>\\r\\n]+>|\\[[^\\]\\r\\n]+\\])", in: $0.text) }
        guard values.count <= 1 else { throw Failure.ambiguousStructure }
        return values.first.map { "[" + $0.dropFirst().dropLast() + "]" }
    }

    private static let planningKeywordLineExpression = try? NSRegularExpression(
        pattern: #"^\s*(SCHEDULED|DEADLINE|CLOSED):"#
    )
    private static let dynamicBlockEndExpression = try? NSRegularExpression(
        pattern: #"^\s*#\+END:\s*$"#, options: [.caseInsensitive]
    )
    private static let dynamicBlockBeginExpression = try? NSRegularExpression(
        pattern: #"^\s*#\+BEGIN:"#, options: [.caseInsensitive]
    )

    private static func matches(_ expression: NSRegularExpression?, in text: String) -> Bool {
        expression?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    private static let captureExpressions: [String: NSRegularExpression] = {
        let patterns = [
            #"^\s*#\+PROPERTY:\s+ARCHIVE\s+(.*?)\s*$"#,
            #"^\s*:ARCHIVE:\s*(.*?)\s*$"#,
            #"^(\*+)[ \t]+\S.*$"#,
            #"^\s*#\+END_([A-Z0-9_-]+)\s*$"#,
            #"^\s*#\+BEGIN_([A-Z0-9_-]+)(?:\s|$)"#,
            #"^\s*:([A-Z][A-Z0-9_-]*):\s*$"#,
            #"^(\*+)[ \t]+\S"#,
        ] + OrgPlanningKeyword.allCases.map {
            "\\b\($0.rawValue):[ \\t]*(<[^>\\r\\n]+>|\\[[^\\]\\r\\n]+\\])"
        }
        return patterns.reduce(into: [:]) { result, pattern in
            result[pattern] = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        }
    }()

    private static func capture(_ pattern: String, in source: String) -> String? {
        let expression = captureExpressions[pattern]
            ?? (try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]))
        guard let expression,
              let match = expression.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)),
              let range = Range(match.range(at: 1), in: source) else { return nil }
        return String(source[range])
    }

    private struct Line {
        let start: Int
        let end: Int
        let text: String
    }
    private struct Heading {
        let start: Int
        let end: Int
        let level: Int
        let title: String
        let rawTitle: String
    }
    private struct Drawer {
        let name: String
        let start: Int
        let contentStart: Int
        let closeStart: Int
        let end: Int
    }

    /// Structural scanner is deliberately conservative around unknown drawers
    /// and all BEGIN/END blocks, whose contents the current grammar may not know.
    private struct Structure {
        let lines: [Line]
        let headings: [Heading]
        let drawers: [Drawer]
        let protected: [Range<Int>]
        let byteCount: Int
        let newline: String

        init(_ source: String) throws {
            byteCount = source.utf8.count
            newline = source.contains("\r\n") ? "\r\n" : "\n"
            var lines: [Line] = []
            var offset = 0
            // Split on the scalar LF, since Swift treats CRLF as one Character.
            for part in source.components(separatedBy: "\n").enumerated() {
                let isLast = offset + part.element.utf8.count == byteCount
                let end = offset + part.element.utf8.count + (isLast ? 0 : 1)
                if offset < byteCount {
                    lines.append(Line(start: offset, end: end,
                                      text: part.element.hasSuffix("\r") ? String(part.element.dropLast()) : part.element))
                }
                offset = end
            }
            self.lines = lines
            var headings: [Heading] = []
            var drawers: [Drawer] = []
            var protected: [Range<Int>] = []
            var block: (name: String, start: Int)?
            var drawer: (name: String, start: Int, contentStart: Int)?
            for line in lines {
                if let active = block {
                    let isDynamicEnd = active.name == ":" && matches(dynamicBlockEndExpression, in: line.text)
                    if isDynamicEnd || capture(#"^\s*#\+END_([A-Z0-9_-]+)\s*$"#, in: line.text)?.uppercased() == active.name {
                        protected.append(active.start..<line.end)
                        block = nil
                    }
                    continue
                }
                if let active = drawer {
                    if line.text.trimmingCharacters(in: .whitespaces).uppercased() == ":END:" {
                        drawers.append(Drawer(name: active.name, start: active.start, contentStart: active.contentStart,
                                              closeStart: line.start, end: line.end))
                        protected.append(active.start..<line.end)
                        drawer = nil
                    }
                    continue
                }
                if let name = capture(#"^\s*#\+BEGIN_([A-Z0-9_-]+)(?:\s|$)"#, in: line.text) {
                    block = (name.uppercased(), line.start)
                } else if matches(dynamicBlockBeginExpression, in: line.text) {
                    block = (":", line.start)
                } else if let name = capture(#"^\s*:([A-Z][A-Z0-9_-]*):\s*$"#, in: line.text) {
                    guard name.uppercased() != "END" else { throw Failure.ambiguousStructure }
                    drawer = (name.uppercased(), line.start, line.end)
                } else if let marker = capture(#"^(\*+)[ \t]+\S"#, in: line.text) {
                    let title = String(line.text.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
                    headings.append(Heading(start: line.start, end: line.end, level: marker.count,
                                            title: title, rawTitle: line.text.trimmingCharacters(in: .whitespaces)))
                }
            }
            guard block == nil, drawer == nil else { throw Failure.ambiguousStructure }
            self.headings = headings
            self.drawers = drawers
            self.protected = protected
        }

        func heading(at start: Int) throws -> Heading {
            guard let heading = headings.first(where: { $0.start == start }) else { throw Failure.missingHeading }
            return heading
        }
        func sectionEnd(of heading: Heading) -> Int { headings.first(where: { $0.start > heading.start })?.start ?? byteCount }
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
        func isProtected(_ offset: Int) -> Bool { protected.contains { $0.contains(offset) } }
    }
}
