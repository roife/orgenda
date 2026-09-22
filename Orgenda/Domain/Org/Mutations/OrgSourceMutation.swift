import Foundation

/// A precise replacement expressed in tree-sitter's UTF-8 byte coordinate
/// space. Applying a mutation never re-encodes or normalizes the untouched
/// portions of the document.
struct OrgSourceMutation: Hashable, Sendable {
    let startByte: Int
    let endByte: Int
    let replacement: String

    /// Applies this replacement to `source` and returns a new value.
    ///
    /// The byte offsets must be ordered, inside the source, and convertible to
    /// real `String.Index` values. In particular, an offset in the middle of a
    /// multi-byte scalar is rejected rather than rounded to a nearby boundary.
    func applied(to source: String) throws -> String {
        let range = try Self.validatedRange(
            in: source,
            startByte: startByte,
            endByte: endByte
        )
        var result = source
        result.replaceSubrange(range, with: replacement)
        return result
    }

    /// Builds a mutation that toggles an Org checkbox token.
    ///
    /// Unchecked becomes checked, checked becomes unchecked, and an
    /// indeterminate checkbox becomes checked. Lowercase `[x]` is accepted as
    /// checked input. Any spaces or tabs consumed at the end of the tree-sitter
    /// node are retained verbatim.
    static func checkboxToggle(
        in source: String,
        startByte: Int,
        endByte: Int
    ) throws -> OrgSourceMutation {
        let nodeText = try sourceText(
            in: source,
            startByte: startByte,
            endByte: endByte
        )
        let token = splitTrailingHorizontalWhitespace(from: nodeText)

        let nextToken: String
        switch token.body {
        case "[ ]":
            nextToken = "[X]"
        case "[X]", "[x]":
            nextToken = "[ ]"
        case "[-]":
            nextToken = "[X]"
        default:
            throw OrgSourceMutationError.unsupportedCheckboxToken(String(token.body))
        }

        return OrgSourceMutation(
            startByte: startByte,
            endByte: endByte,
            replacement: nextToken + token.trailingWhitespace
        )
    }

    /// Builds the preview status-button mutation: terminal states return to
    /// TODO, while every open state becomes DONE. Trailing horizontal
    /// whitespace from the syntax node is retained verbatim.
    static func workflowToggle(
        in source: String,
        startByte: Int,
        endByte: Int
    ) throws -> OrgSourceMutation {
        let nodeText = try sourceText(
            in: source,
            startByte: startByte,
            endByte: endByte
        )
        let token = splitTrailingHorizontalWhitespace(from: nodeText)
        guard let state = OrgWorkflowState(rawValue: String(token.body)) else {
            throw OrgSourceMutationError.unsupportedWorkflowToken(String(token.body))
        }
        let nextToken = state.isTerminal ? OrgWorkflowState.todo.rawValue : OrgWorkflowState.done.rawValue

        return OrgSourceMutation(
            startByte: startByte,
            endByte: endByte,
            replacement: nextToken + token.trailingWhitespace
        )
    }

    private static func sourceText(
        in source: String,
        startByte: Int,
        endByte: Int
    ) throws -> String {
        let range = try validatedRange(
            in: source,
            startByte: startByte,
            endByte: endByte
        )
        return String(source[range])
    }

    private static func validatedRange(
        in source: String,
        startByte: Int,
        endByte: Int
    ) throws -> Range<String.Index> {
        guard startByte >= 0, endByte >= 0 else {
            throw OrgSourceMutationError.negativeByteOffset(
                startByte: startByte,
                endByte: endByte
            )
        }
        guard startByte <= endByte else {
            throw OrgSourceMutationError.unorderedByteRange(
                startByte: startByte,
                endByte: endByte
            )
        }

        let byteCount = source.utf8.count
        guard endByte <= byteCount else {
            throw OrgSourceMutationError.byteRangeOutOfBounds(
                startByte: startByte,
                endByte: endByte,
                sourceUTF8Count: byteCount
            )
        }

        let utf8 = source.utf8
        guard let lowerBound = String.Index(utf8.index(utf8.startIndex, offsetBy: startByte), within: source) else {
            throw OrgSourceMutationError.invalidStringBoundary(byteOffset: startByte)
        }
        guard let upperBound = String.Index(utf8.index(utf8.startIndex, offsetBy: endByte), within: source) else {
            throw OrgSourceMutationError.invalidStringBoundary(byteOffset: endByte)
        }

        return lowerBound..<upperBound
    }

    private static func splitTrailingHorizontalWhitespace(
        from text: String
    ) -> (body: Substring, trailingWhitespace: String) {
        let trailingStart = text.lastIndex { $0 != " " && $0 != "\t" }
            .map { text.index(after: $0) } ?? text.startIndex

        return (
            body: text[..<trailingStart],
            trailingWhitespace: String(text[trailingStart...])
        )
    }
}

extension OrgSourceMutation {
    /// Plans independent patches against one freshly resolved heading. The next
    /// heading, property drawers, source blocks, and unrecognized syntax are never
    /// included in a replacement range.
    static func itemEdits(
        replacing original: OrgItem,
        with item: OrgItem,
        heading: ParsedOrgNode,
        following: [ParsedOrgNode]
    ) -> [OrgSourceMutation]? {
        var edits: [OrgSourceMutation] = []
        let newline = heading.text.hasSuffix("\r\n") ? "\r\n" : "\n"
        let headerChanged = original.title != item.title || original.state != item.state
            || original.priority != item.priority || original.tags != item.tags
            || original.kind != item.kind

        if headerChanged {
            guard let marker = heading.children.first(where: { $0.type == "heading_marker" }),
                  let title = heading.children.first(where: { $0.type == "heading_title" })
            else { return nil }
            let workflow = heading.children.first(where: { $0.type == "todo_keyword" })
            let priority = heading.children.first(where: { $0.type == "priority" })
            let tags = heading.children.first(where: { $0.type == "tag_list" })
            func whitespace(_ text: String?) -> String {
                guard let text else { return " " }
                return String(text.reversed().prefix { $0 == " " || $0 == "\t" }.reversed())
            }
            var workflowText = workflow?.text ?? ""
            if original.state != item.state
                || (original.kind != item.kind && workflow == nil && [.task, .project, .habit].contains(item.kind)) {
                workflowText = item.state.rawValue + whitespace(workflow?.text)
            }
            if original.kind != item.kind, (item.kind == .event || item.kind == .note),
               !item.state.isTerminal {
                workflowText = ""
            }
            var priorityText = priority?.text ?? ""
            if original.priority != item.priority {
                priorityText = item.priority == .none ? ""
                    : "[#\(item.priority.rawValue)]" + whitespace(priority?.text)
            }
            var titleText = original.title == item.title
                ? title.text : item.title + whitespace(title.text)
            var tagText = tags?.text ?? ""
            if original.tags != item.tags {
                tagText = item.tags.isEmpty ? "" : ":\(item.tags.joined(separator: ":")):"
                    + (tags.map { whitespace($0.text) } ?? "")
                if !tagText.isEmpty, titleText.last != " ", titleText.last != "\t" {
                    titleText += " "
                }
            }
            let contentEnd = tags?.endByte ?? title.endByte
            let suffix = String(decoding: heading.text.utf8.dropFirst(contentEnd - heading.startByte), as: UTF8.self)
            edits.append(OrgSourceMutation(
                startByte: heading.startByte,
                endByte: heading.endByte,
                replacement: marker.text + workflowText + priorityText + titleText + tagText + suffix
            ))
        }

        let planningEntries = following.filter { $0.type == "planning" }
            .flatMap(\.children).filter { $0.type == "planning_entry" }
        let primary: OrgPlanningKeyword? = item.scheduled != nil ? .scheduled
            : (item.deadline != nil ? .deadline : nil)
        var insertedPlanning: [String] = []
        for keyword in OrgPlanningKeyword.allCases {
            let oldDate: Date?
            let newDate: Date?
            switch keyword {
            case .scheduled: oldDate = original.scheduled; newDate = item.scheduled
            case .deadline: oldDate = original.deadline; newDate = item.deadline
            case .closed: oldDate = original.closed; newDate = item.closed
            }
            let recurrenceChanged = keyword == primary && original.recurrence != item.recurrence
            let timeChanged = keyword != .closed && oldDate != nil && original.hasTime != item.hasTime
            let durationChanged = keyword == primary && original.durationMinutes != item.durationMinutes
            guard oldDate != newDate || recurrenceChanged || timeChanged || durationChanged else { continue }
            let matching = planningEntries.filter {
                $0.children.first(where: { $0.type == "planning_keyword" })?.text == keyword.sourceToken
            }
            guard matching.count <= 1 else { return nil }
            if let entry = matching.first {
                var replacement = ""
                if let newDate {
                    guard var draft = OrgPlanningEntryDraft(source: entry.text) else { return nil }
                    moveTimestamps(in: &draft, to: newDate,
                                   includesTime: keyword == .closed || item.hasTime,
                                   durationMinutes: durationChanged ? item.durationMinutes : nil)
                    if recurrenceChanged { draft.timestamps[0].setRecurrence(item.recurrence) }
                    replacement = draft.source
                }
                edits.append(OrgSourceMutation(
                    startByte: entry.startByte, endByte: entry.endByte, replacement: replacement
                ))
            } else if let newDate {
                insertedPlanning.append(planningSource(
                    keyword: keyword, date: newDate, hasTime: keyword == .closed || item.hasTime,
                    recurrence: keyword == primary ? item.recurrence : nil
                ))
            }
        }

        let eventNode = OrgHeadingBody.firstActiveTimestamp(in: following)
        let eventChanged = original.eventDate != item.eventDate
            || (primary == nil && (original.hasTime != item.hasTime
                || original.recurrence != item.recurrence || original.durationMinutes != item.durationMinutes))
        var eventReplacement: String?
        if eventChanged, original.eventDate != nil || item.eventDate != nil {
            if let date = item.eventDate {
                if let eventNode, var draft = OrgPlanningEntryDraft(timestampSource: eventNode.text) {
                    moveTimestamps(in: &draft, to: date, includesTime: item.hasTime,
                                   durationMinutes: original.durationMinutes != item.durationMinutes ? item.durationMinutes : nil)
                    if original.recurrence != item.recurrence { draft.timestamps[0].setRecurrence(item.recurrence) }
                    eventReplacement = draft.source
                } else {
                    eventReplacement = activeTimestampSource(date: date, hasTime: item.hasTime,
                                                             recurrence: item.recurrence)
                }
            } else {
                eventReplacement = ""
            }
        }

        let bodyNodes = OrgHeadingBody.editableNodes(in: following)
        let bodyWillReplaceEvent = original.body != item.body && eventNode.map { event in
            bodyNodes.contains { $0.startByte <= event.startByte && $0.endByte >= event.endByte }
        } == true
        if let eventNode, let eventReplacement, !bodyWillReplaceEvent {
            edits.append(OrgSourceMutation(startByte: eventNode.startByte, endByte: eventNode.endByte,
                                           replacement: eventReplacement))
        }
        var insertedBody = ""
        if original.body != item.body {
            var replacementBody = item.body
            if bodyWillReplaceEvent, let eventNode, let eventReplacement {
                if let range = replacementBody.range(of: eventNode.text) {
                    replacementBody.replaceSubrange(range, with: eventReplacement)
                } else if !eventReplacement.isEmpty {
                    replacementBody = eventReplacement + newline + replacementBody
                }
            }
            if let first = bodyNodes.first {
                edits.append(OrgSourceMutation(
                    startByte: first.startByte, endByte: first.endByte,
                    replacement: replacementBody.isEmpty ? "" : replacementBody + (first.text.hasSuffix("\n") ? newline : "")
                ))
                for node in bodyNodes.dropFirst() {
                    edits.append(OrgSourceMutation(startByte: node.startByte, endByte: node.endByte, replacement: ""))
                }
            } else if !replacementBody.isEmpty {
                insertedBody = replacementBody + newline
            }
        }
        // Keep new planning immediately below its heading, and new notes after
        // planning/properties. Combining co-located insertions fixes their order.
        var insertions: [Int: String] = [:]
        if !insertedPlanning.isEmpty {
            let prefix = heading.text.hasSuffix("\n") ? "" : newline
            insertions[heading.endByte] = prefix + insertedPlanning.joined(separator: newline) + newline
        }
        if eventNode == nil, let eventReplacement, !eventReplacement.isEmpty {
            let insertionPoint = following.last?.endByte ?? heading.endByte
            let preceding = following.last?.text ?? heading.text
            let prefix = preceding.hasSuffix("\n") || insertions[insertionPoint] != nil ? "" : newline
            insertions[insertionPoint, default: ""] += prefix + eventReplacement + newline
        }
        guard appendPropertyEdits(replacing: original.properties, with: item.properties,
                                  heading: heading, following: following, newline: newline,
                                  edits: &edits, insertions: &insertions) else { return nil }
        if !insertedBody.isEmpty {
            let insertionPoint = following.last?.endByte ?? heading.endByte
            let preceding = following.last?.text ?? heading.text
            let prefix = preceding.hasSuffix("\n") || insertions[insertionPoint] != nil ? "" : newline
            insertions[insertionPoint, default: ""] += prefix + insertedBody
        }
        for (offset, text) in insertions {
            edits.append(OrgSourceMutation(startByte: offset, endByte: offset, replacement: text))
        }
        return edits.sorted {
            $0.startByte == $1.startByte ? $0.endByte > $1.endByte : $0.startByte > $1.startByte
        }
    }

    static func planningSource(
        keyword: OrgPlanningKeyword, date: Date, hasTime: Bool, recurrence: String?
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = hasTime || keyword == .closed ? "yyyy-MM-dd EEE HH:mm" : "yyyy-MM-dd EEE"
        let timestamp = formatter.string(from: date) + (recurrence.map { " " + $0 } ?? "")
        let delimiters = keyword == .closed ? ("[", "]") : ("<", ">")
        return "\(keyword.sourceToken) \(delimiters.0)\(timestamp)\(delimiters.1)"
    }

    static func activeTimestampSource(date: Date, hasTime: Bool, recurrence: String?) -> String {
        String(planningSource(keyword: .scheduled, date: date, hasTime: hasTime, recurrence: recurrence)
            .dropFirst("SCHEDULED: ".count))
    }

    private static func moveTimestamps(in draft: inout OrgPlanningEntryDraft, to date: Date,
                                       includesTime: Bool, durationMinutes: Int?) {
        let delta = date.timeIntervalSince(draft.timestamps[0].date)
        draft.timestamps[0].move(to: date, includesTime: includesTime,
                                 durationMinutes: draft.isRange ? nil : durationMinutes)
        if draft.isRange {
            let end = durationMinutes.map { date.addingTimeInterval(TimeInterval($0) * 60) }
                ?? draft.timestamps[1].date.addingTimeInterval(delta)
            draft.timestamps[1].move(to: end, includesTime: includesTime)
        }
    }

    private static func appendPropertyEdits(
        replacing original: [String: String], with properties: [String: String],
        heading: ParsedOrgNode, following: [ParsedOrgNode], newline: String,
        edits: inout [OrgSourceMutation], insertions: inout [Int: String]
    ) -> Bool {
        let changed = Set(original.keys).union(properties.keys).filter { original[$0] != properties[$0] }.sorted()
        guard !changed.isEmpty else { return true }
        let drawers = following.filter { $0.type == "property_drawer" }
        guard drawers.count <= 1 else { return false }
        let drawer = drawers.first
        var newLines: [String] = []
        for key in changed {
            guard key.range(of: #"^[A-Za-z0-9_@#%+.-]+$"#, options: .regularExpression) != nil,
                  properties[key]?.contains(where: { $0 == "\n" || $0 == "\r" }) != true else { return false }
            let matching = drawer?.children.filter { node in
                node.type == "property" && node.children.first { $0.type == "property_name" }?.text.uppercased() == key.uppercased()
            } ?? []
            guard matching.count <= 1 else { return false }
            if let existing = matching.first {
                let line = existing.text
                let prefixEnd = line.range(of: #"^[ \t]*:[^:]+:[ \t]*"#, options: .regularExpression)?.upperBound
                guard let prefixEnd else { return false }
                let prefix = String(line[..<prefixEnd])
                let replacement = properties[key].map { prefix + (prefix.last == ":" ? " " : "") + $0
                    + (line.hasSuffix("\n") ? newline : "") } ?? ""
                edits.append(OrgSourceMutation(startByte: existing.startByte, endByte: existing.endByte,
                                               replacement: replacement))
            } else if let value = properties[key] {
                newLines.append(":\(key.uppercased()): \(value)")
            }
        }
        if !newLines.isEmpty {
            let lines = newLines.joined(separator: newline) + newline
            if let drawer {
                guard let end = drawer.children.first(where: { $0.type == "property_drawer_end" }) else { return false }
                insertions[end.startByte, default: ""] += lines
            } else {
                let preceding = following.last(where: { $0.type == "planning" }) ?? heading
                let prefix = preceding.text.hasSuffix("\n") || insertions[preceding.endByte] != nil ? "" : newline
                insertions[preceding.endByte, default: ""] += prefix + ":PROPERTIES:" + newline + lines + ":END:" + newline
            }
        }
        return true
    }
}

/// Explicit failures for UTF-8 source mutation and supported semantic token
/// transitions. Associated values make failures actionable in diagnostics and
/// tests without exposing a partially modified source value.
enum OrgSourceMutationError: Error, Equatable, Sendable {
    case negativeByteOffset(startByte: Int, endByte: Int)
    case unorderedByteRange(startByte: Int, endByte: Int)
    case byteRangeOutOfBounds(startByte: Int, endByte: Int, sourceUTF8Count: Int)
    case invalidStringBoundary(byteOffset: Int)
    case unsupportedCheckboxToken(String)
    case unsupportedWorkflowToken(String)
}
