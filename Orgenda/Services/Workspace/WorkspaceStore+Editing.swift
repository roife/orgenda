import Foundation

extension WorkspaceStore {
    static let repeaterTokenExpression = try! NSRegularExpression(
        pattern: #"(?:\+\+|\.\+|\+)\d+[hdwmy]"#
    )

    @discardableResult
    func save(_ draft: OrgItem, original baseline: OrgItem? = nil,
              stateNote: String? = nil) -> Bool {
        let existing = items.first { $0.id == draft.id }
        // An item removed during editing is a conflict, not a new capture.
        guard baseline == nil || existing != nil else { return false }
        var item = normalizedKind(of: draft, replacing: existing)
        item.title = item.title.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !item.title.isEmpty else { return false }
        guard let itemIndex = items.firstIndex(where: { $0.id == item.id }) else {
            appendItem(item)
            return true
        }
        let original = items[itemIndex]
        if let baseline, !original.hasSameEditableValues(as: baseline) { return false }
        if original.hasWorkflowState {
            guard let state = workflow(for: original.source.file).state(item.state.rawValue) else { return false }
            item.state = state
        }
        item = OrgWorkflowOperations.normalized(item, replacing: original, now: .now)
        if configuration.logging.done == .none
            && !original.state.isTerminal && item.state.isTerminal { item.closed = original.closed }
        if OrgWorkflowOperations.requiresNote(from: original.state, to: item.state),
           stateNote?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            operationError = String(localized: "Add a note for this state change.")
            return false
        }
        guard original.source.file == item.source.file,
              let documentIndex = documents.firstIndex(where: { $0.path == original.source.file }),
              let resolved = resolvedHeading(for: original),
              baseline == nil || matchesSourceValues(original, heading: resolved.heading),
              let edits = OrgSourceMutation.itemEdits(
                replacing: original, with: item,
                heading: resolved.node, following: resolved.following
              )
        else { return false }

        var contents = documents[documentIndex].contents
        for edit in edits {
            guard let updated = try? edit.applied(to: contents) else { return false }
            contents = updated
        }
        let logInsertionDelta: Int
        do {
            let priorCount = contents.utf8.count
            contents = try OrgWorkflowOperations.applyingLogs(to: contents,
                headingStartByte: resolved.heading.source.startByte,
                replacing: original, with: item, note: stateNote, now: .now,
                originalSource: documents[documentIndex].contents,
                logging: configuration.logging)
            logInsertionDelta = contents.utf8.count - priorCount
        } catch {
            operationError = error.localizedDescription
            return false
        }

        // Repair source locations from the current document before rebasing all
        // items. A second quick edit can then resolve even before indexing finishes.
        var nextItems = items
        for index in nextItems.indices where nextItems[index].source.file == original.source.file {
            let matches = resolved.document.headings.filter { $0.title == nextItems[index].title }
            if let heading = matches.first(where: { $0.source.startByte == nextItems[index].source.startByte })
                ?? (matches.count == 1 ? matches.first : nil) {
                nextItems[index].source = heading.source
            }
        }
        let source = resolved.heading.source
        nextItems[itemIndex] = item
        nextItems[itemIndex].source = source
        rebaseItemSources(&nextItems, in: original.source.file, through: edits, contents: contents)
        if logInsertionDelta != 0 {
            let headingStart = nextItems[itemIndex].source.startByte
            Self.updateItemSources(&nextItems, in: original.source.file, contents: contents) { source in
                if source.startByte > headingStart {
                    source.startByte += logInsertionDelta
                }
                if source.endByte > headingStart {
                    source.endByte += logInsertionDelta
                }
            }
        }
        items = nextItems
        documents[documentIndex].contents = contents
        operationError = nil
        scheduleWorkspaceRefresh(changedPaths: [original.source.file])
        return true
    }

    func toggleDone(_ item: OrgItem) {
        guard var updated = items.first(where: { $0.id == item.id }) else { return }
        operationError = nil
        guard updated.canComplete else { return }
        let beforeDocuments = documents
        let beforeItems = items
        let beforeDirtyPaths = dirtyFilePaths
        let beforeIndexPaths = pendingDirtyPaths
        let repeatedDate = !updated.state.isTerminal
            ? updated.recurrence.flatMap(OrgRepeater.init).flatMap { repeater in
                updated.agendaDate.flatMap { repeater.nextDate(afterCompletion: .now, from: $0) }
            } : nil
        if repeatedDate != nil, let resolved = resolvedHeading(for: updated) {
            func repeatedStamps(_ node: ParsedOrgNode) -> Int {
                if node.type == "active_timestamp" {
                    return Self.repeaterTokenExpression
                        .firstMatch(in: node.text, range: NSRange(node.text.startIndex..., in: node.text)) == nil ? 0 : 1
                }
                return node.children.reduce(0) { $0 + repeatedStamps($1) }
            }
            let count = OrgHeadingBody.nodesOutsideDrawers(in: resolved.following)
                .filter { ["planning", "paragraph", "list"].contains($0.type) }
                .reduce(0) { $0 + repeatedStamps($1) }
            guard count <= 1 else {
                operationError = String(localized: "This item has multiple repeating timestamps. Update them together in the source editor.")
                return
            }
        }
        if !updated.hasWorkflowState {
            guard let repeatedDate else {
                operationError = String(localized: "The next occurrence could not be calculated. Check the repeat rule.")
                return
            }
            completeRepeatingEvent(updated, nextDate: repeatedDate)
            return
        }
        updated.state = workflow(for: updated.source.file).toggled(updated.state)
        if updated.kind == .habit, updated.state.isTerminal {
            updated.habitHistory.append(.now)
        }
        guard save(updated) else {
            operationError = operationError ?? String(localized: "The task changed. Reopen it before changing its state.")
            return
        }
        if let repeatedDate, var repeated = items.first(where: { $0.id == updated.id }) {
            repeated.state = workflow(for: updated.source.file).toggled(updated.state)
            repeated.updateAgendaDate(to: repeatedDate)
            repeated.properties["LAST_REPEAT"] = Date.now.orgTimestamp(active: false, includesTime: true)
            if !save(repeated) {
                documents = beforeDocuments
                items = beforeItems
                dirtyFilePaths = beforeDirtyPaths
                fileSaveTask?.cancel()
                resetWorkspaceIndex()
                scheduleWorkspaceRefresh(changedPaths: beforeIndexPaths.union([updated.source.file]), saveFiles: false)
                if !beforeDirtyPaths.isEmpty { queueFileSave(paths: beforeDirtyPaths) }
                operationError = String(localized: "The repeating item could not be advanced safely. Its original source has been kept.")
            }
        }
    }

    /// Plain calendar events have no task state. Advance and record an occurrence
    /// atomically without adding TODO/DONE, CLOSED, or inferred kind tags.
    private func completeRepeatingEvent(_ original: OrgItem, nextDate: Date) {
        guard let itemIndex = items.firstIndex(where: { $0.id == original.id }),
              let documentIndex = documents.firstIndex(where: { $0.path == original.source.file }),
              let resolved = resolvedHeading(for: original),
              matchesSourceValues(original, heading: resolved.heading) else {
            operationError = String(localized: "The event changed. Reopen it before completing this occurrence.")
            return
        }
        var updated = original
        updated.updateAgendaDate(to: nextDate)
        updated.properties["LAST_REPEAT"] = Date.now.orgTimestamp(active: false, includesTime: true)
        guard let edits = OrgSourceMutation.itemEdits(replacing: original, with: updated,
                heading: resolved.node, following: resolved.following) else {
            operationError = String(localized: "The event metadata is ambiguous. Check its properties before completing it.")
            return
        }
        var contents = documents[documentIndex].contents
        do {
            for edit in edits { contents = try edit.applied(to: contents) }
        } catch {
            operationError = String(localized: "The event changed. Reopen it before completing this occurrence.")
            return
        }
        var nextItems = items
        nextItems[itemIndex] = updated
        nextItems[itemIndex].source = resolved.heading.source
        rebaseItemSources(&nextItems, in: original.source.file, through: edits, contents: contents)
        items = nextItems
        documents[documentIndex].contents = contents
        scheduleWorkspaceRefresh(changedPaths: [original.source.file])
    }

    /// The source viewer shows the actual heading and its own blocks, including
    /// metadata that the form does not expose.
    func exactSource(for item: OrgItem) -> String? {
        let current = items.first(where: { $0.id == item.id }) ?? item
        guard let resolved = resolvedHeading(for: current),
              let source = documentsByPath[current.source.file]?.contents
        else { return nil }
        return String(decoding: source.utf8.dropFirst(resolved.heading.source.startByte)
            .prefix(resolved.heading.source.endByte - resolved.heading.source.startByte), as: UTF8.self)
    }

    func addJournalEntry(title: String, body: String, date: Date) {
        let path = "\(configuration.files.journal)/\(Calendar.autoupdatingCurrent.component(.year, from: date)).org"
        let index: Int
        if let existing = documents.firstIndex(where: { $0.path == path }) {
            index = existing
        } else {
            index = documents.endIndex
            documents.append(WorkspaceDocument(path: path, title: URL(fileURLWithPath: path).lastPathComponent, contents: "", kind: .org))
        }
        let time = date.formatted(.verbatim(
            "\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits)",
            locale: Locale(identifier: "en_US_POSIX"), timeZone: .autoupdatingCurrent,
            calendar: Calendar(identifier: .gregorian)
        ))
        let source = "* \(date.orgDateText(includesTime: false))\n** \(time) \(title)\n\(body)"
        let separator = documents[index].contents.isEmpty ? "" : "\n\n"
        let prefix = documents[index].contents + separator
        let entry = JournalEntry(
            id: UUID(),
            date: date,
            title: title,
            body: body,
            source: SourceLocation(
                file: path,
                startByte: prefix.utf8.count,
                endByte: prefix.utf8.count + source.utf8.count,
                startLine: prefix.utf8.filter { $0 == 10 }.count + 1
            )
        )
        documents[index].contents = prefix + source
        journalEntries.append(entry)
        scheduleWorkspaceRefresh(changedPaths: [path])
    }

    func updateDocument(path: String, contents: String) {
        var document: WorkspaceDocument
        if let existing = documentsByPath[path] { document = existing }
        else if let baseline = retiredBlobs[path], let kind = WorkspaceDocument.Kind(path: path) {
            document = WorkspaceDocument(path: path, title: (path as NSString).lastPathComponent, contents: "", kind: kind)
            persistedBlobs[path] = baseline
        } else { return }
        guard !document.contents.utf8.elementsEqual(contents.utf8) else { return }
        document.contents = contents
        documentsByPath[path] = document
        storageContentGeneration &+= 1
        scheduleWorkspaceRefresh(changedPaths: [path], debounce: .milliseconds(400))
    }

    func refreshDocumentIndex(path: String) {
        scheduleWorkspaceRefresh(changedPaths: [path], saveFiles: false)
    }

    /// The drag snapshot must still match byte-for-byte when the user drops it.
    func moveHeading(
        in document: ParsedOrgDocument,
        headingID: String,
        targetID: String,
        placement: OrgHeadingPlacement
    ) -> OrgHeadingMove? {
        operationError = nil
        guard let index = documents.firstIndex(where: { $0.path == document.path }),
              documents[index].contents.utf8.elementsEqual(document.root.text.utf8) else {
            operationError = String(localized: "The document changed while dragging. Try moving the heading again.")
            return nil
        }
        guard let move = OrgHeadingMove.plan(in: document, headingID: headingID,
                                             targetID: targetID, placement: placement),
              let contents = try? move.mutation.applied(to: documents[index].contents) else { return nil }
        Self.updateItemSources(&items, in: document.path, contents: contents) { source in
            source = move.relocatedSource(source)
        }
        documents[index].contents = contents
        scheduleWorkspaceRefresh(changedPaths: [document.path])
        return move
    }

    @discardableResult
    func applyPlanningDraft(path: String, node: ParsedOrgNode, draft: OrgPlanningEntryDraft) -> Bool {
        guard let index = documents.firstIndex(where: { $0.path == path }) else { return false }
        let source = documents[index].contents
        guard source.utf8.dropFirst(node.startByte).prefix(node.endByte - node.startByte).elementsEqual(node.text.utf8),
              let replacement = try? OrgSourceMutation(startByte: node.startByte, endByte: node.endByte,
                                                       replacement: draft.source).applied(to: source) else { return false }
        var updated = replacement
        // Reuse the published index when it still matches the source; only
        // the post-edit document must always be parsed here.
        let beforeDocument = parsedDocuments[path].flatMap { $0.root.text.utf8.elementsEqual(source.utf8) ? $0 : nil }
            ?? OrgIndexService.parseSynchronously([documents[index]], configuration: configuration).first
        var candidate = documents[index]; candidate.contents = replacement
        let afterDocument = OrgIndexService.parseSynchronously([candidate], configuration: configuration).first
        if let before = beforeDocument?.headings.last(where: { $0.source.startByte <= node.startByte }),
           let after = afterDocument?.headings.first(where: { $0.source.startByte == before.source.startByte }) {
            func item(_ heading: IndexedOrgHeading) -> OrgItem {
                OrgItem(id: UUID(), title: heading.title, state: heading.state ?? .todo,
                    kind: heading.kind, priority: heading.priority, tags: heading.tags,
                    scheduled: heading.scheduled, deadline: heading.deadline, closed: heading.closed,
                    eventDate: heading.eventDate, hasTime: heading.hasTime, durationMinutes: heading.durationMinutes,
                    recurrence: heading.recurrence, body: heading.body, source: heading.source,
                    habitHistory: [], properties: heading.properties)
            }
            do {
                updated = try OrgWorkflowOperations.applyingLogs(to: replacement,
                    headingStartByte: before.source.startByte, replacing: item(before), with: item(after),
                    originalSource: source, logging: configuration.logging)
            } catch { operationError = error.localizedDescription; return false }
        }
        documents[index].contents = updated
        operationError = nil
        scheduleWorkspaceRefresh(changedPaths: [path])
        return true
    }

    @discardableResult
    func applySourceReplacement(
        path: String,
        startByte: Int,
        endByte: Int,
        expectedText: String,
        replacement: String
    ) -> Bool {
        guard let index = documents.firstIndex(where: { $0.path == path }) else { return false }
        let source = documents[index].contents
        guard startByte >= 0,
              endByte >= startByte,
              source.utf8
                .dropFirst(startByte)
                .prefix(endByte - startByte)
                .elementsEqual(expectedText.utf8)
        else { return false }

        let mutation = OrgSourceMutation(
            startByte: startByte,
            endByte: endByte,
            replacement: replacement
        )
        guard let contents = try? mutation.applied(to: source) else { return false }
        documents[index].contents = contents
        scheduleWorkspaceRefresh(changedPaths: [path])
        return true
    }
    private func normalizedKind(of draft: OrgItem, replacing original: OrgItem?) -> OrgItem {
        var item = draft
        if original?.kind != item.kind {
            item.tags.removeAll { ["event", "project", "habit", "note"].contains($0) }
            if item.kind != .task { item.tags.append(item.kind.rawValue) }
        } else if ([.event, .note].contains(item.kind) || (item.kind == .habit && item.recurrence == nil)),
                  !item.tags.contains(item.kind.rawValue) {
            item.tags.append(item.kind.rawValue)
        }
        return item
    }

    private func matchesSourceValues(_ item: OrgItem, heading: IndexedOrgHeading) -> Bool {
        func sameDate(_ lhs: Date?, _ rhs: Date?) -> Bool {
            switch (lhs, rhs) {
            case (nil, nil): return true
            case let (lhs?, rhs?):
                return Calendar.autoupdatingCurrent.isDate(lhs, equalTo: rhs, toGranularity: item.hasTime ? .minute : .day)
            default: return false
            }
        }
        return item.title == heading.title && item.state == (heading.state ?? item.state)
            && item.priority == heading.priority && item.tags == heading.tags
            && sameDate(item.scheduled, heading.scheduled) && sameDate(item.deadline, heading.deadline)
            && sameDate(item.closed, heading.closed) && item.hasTime == heading.hasTime
            && sameDate(item.eventDate, heading.eventDate) && item.properties == heading.properties
            && item.recurrence == heading.recurrence && item.body == heading.body
    }

    private func resolvedHeading(for item: OrgItem) -> (
        document: ParsedOrgDocument, heading: IndexedOrgHeading,
        node: ParsedOrgNode, following: [ParsedOrgNode]
    )? {
        guard let source = documentsByPath[item.source.file] else { return nil }
        let parsed: ParsedOrgDocument?
        if let cached = parsedDocuments[source.path], cached.root.text.utf8.elementsEqual(source.contents.utf8) {
            parsed = cached
        } else {
            parsed = OrgIndexService.parseSynchronously([source], configuration: configuration).first
        }
        guard let parsed else { return nil }
        let matches = parsed.headings.filter { $0.title == item.title }
        guard let heading = matches.first(where: { $0.source.startByte == item.source.startByte })
                ?? (parsedDocuments[source.path] == nil && matches.count == 1 ? matches.first : nil),
              let nodeIndex = parsed.root.children.firstIndex(where: {
                  $0.type == "heading" && $0.startByte == heading.source.startByte
              })
        else { return nil }
        let following = parsed.root.children.dropFirst(nodeIndex + 1).prefix { $0.type != "heading" }
        return (parsed, heading, parsed.root.children[nodeIndex], Array(following))
    }

    /// Start byte of every line (1-based lookup). Built with a single scan so
    /// per-item line repair is a binary search instead of a full prefix count.
    private static func lineStarts(in contents: String) -> [Int] {
        [0] + contents.utf8.enumerated().compactMap { $0.element == 10 ? $0.offset + 1 : nil }
    }

    /// 1-based line number containing the given byte offset.
    private static func lineNumber(atByte byte: Int, lineStarts: [Int]) -> Int {
        var lower = 0
        var upper = lineStarts.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if lineStarts[middle] <= byte { lower = middle + 1 } else { upper = middle }
        }
        return lower
    }

    private func rebaseItemSources(_ items: inout [OrgItem], in path: String,
                                   through edits: [OrgSourceMutation], contents: String) {
        Self.updateItemSources(&items, in: path, contents: contents) { source in
            for edit in edits {
                let delta = edit.replacement.utf8.count - (edit.endByte - edit.startByte)
                if source.startByte >= edit.endByte {
                    source.startByte += delta
                }
                if source.endByte >= edit.endByte {
                    source.endByte += delta
                }
            }
        }
    }

    private static func updateItemSources(_ items: inout [OrgItem], in path: String, contents: String,
                                          update: (inout SourceLocation) -> Void) {
        let lineStarts = Self.lineStarts(in: contents)
        for index in items.indices where items[index].source.file == path {
            var source = items[index].source
            update(&source)
            source.startLine = Self.lineNumber(atByte: source.startByte, lineStarts: lineStarts)
            items[index].source = source
        }
    }

    private func appendItem(_ item: OrgItem) {
        let path = item.source.file
        let index: Int
        if let existing = documents.firstIndex(where: { $0.path == path }) {
            index = existing
        } else {
            index = documents.endIndex
            documents.append(WorkspaceDocument(path: path, title: path, contents: "", kind: .org))
        }
        var lines = [item.orgHeading]
        if [.event, .note].contains(item.kind), !item.state.isTerminal {
            lines[0] = lines[0].replacingOccurrences(of: "* \(item.state.rawValue) ", with: "* ")
        }
        let primary: OrgPlanningKeyword = item.scheduled != nil ? .scheduled
            : (item.deadline != nil ? .deadline : .closed)
        for (keyword, date) in [(OrgPlanningKeyword.scheduled, item.scheduled), (.deadline, item.deadline), (.closed, item.closed)] {
            if let date {
                lines.append(OrgSourceMutation.planningSource(
                    keyword: keyword, date: date, hasTime: item.hasTime,
                    recurrence: keyword == primary ? item.recurrence : nil
                ))
            }
        }
        if !item.body.isEmpty { lines.append(item.body) }
        let newSource = lines.joined(separator: "\n")
        let separator = documents[index].contents.isEmpty || documents[index].contents.hasSuffix("\n\n") ? "" : "\n\n"
        let prefix = documents[index].contents + separator
        var appended = item
        appended.source = SourceLocation(
            file: path, startByte: prefix.utf8.count, endByte: prefix.utf8.count + newSource.utf8.count,
            startLine: prefix.utf8.filter { $0 == 10 }.count + 1
        )
        documents[index].contents = prefix + newSource
        items.append(appended)
        scheduleWorkspaceRefresh(changedPaths: [path])
    }

}
