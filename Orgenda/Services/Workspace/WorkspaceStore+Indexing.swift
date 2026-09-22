import Foundation
import SwiftUI

extension WorkspaceStore {
    func parseWorkspace() {
        parseTask?.cancel()
        parseTask = nil
        parseGeneration &+= 1
        pendingDirtyPaths.removeAll()

        let started = CFAbsoluteTimeGetCurrent()
        let parsed = OrgIndexService.parseSynchronously(documents)

        publish(
            parsed,
            replacingAll: true,
            refreshedPaths: Set(documents.filter { $0.kind == .org }.map(\.path)),
            durationMilliseconds: (CFAbsoluteTimeGetCurrent() - started) * 1_000,
            indexedJournal: isFolderConnected ? JournalFileIndex.entries(in: documents) : nil
        )
    }

    /// Schedules a full reparse off the main actor. Interactive paths use this
    /// instead of `parseWorkspace()` so a large workspace never blocks the UI;
    /// the synchronous variant remains for tests and inline index barriers.
    func scheduleWorkspaceParse() {
        let orgPaths = Set(documents.filter { $0.kind == .org }.map(\.path))
        guard !orgPaths.isEmpty else { parseWorkspace(); return }
        // Passing every Org path makes the refresh reparse and republish all of
        // them in place, which matches a full parse without an empty-index gap.
        scheduleWorkspaceRefresh(changedPaths: orgPaths, saveFiles: false)
    }

    func scheduleWorkspaceRefresh(
        changedPaths: Set<String>,
        debounce: Duration? = nil,
        saveFiles: Bool = true
    ) {
        if saveFiles { queueFileSave(paths: changedPaths) }
        pendingDirtyPaths.formUnion(changedPaths)
        parseTask?.cancel()
        parseGeneration &+= 1
        let generation = parseGeneration

        let replacingAll = parsedDocuments.isEmpty
        let requestedPaths = replacingAll
            ? Set(documents.filter { $0.kind == .org }.map(\.path))
            : pendingDirtyPaths
        let targets = documents.filter { document in
            document.kind == .org && requestedPaths.contains(document.path)
        }
        guard !targets.isEmpty else { return }
        let requestedSources = Dictionary(uniqueKeysWithValues: targets.map { ($0.path, $0.contents) })
        let journalSources = documents.filter { $0.kind == .org && $0.path.split(separator: "/").dropLast().contains("journal") }
        let shouldIndexJournal = isFolderConnected && (replacingAll || requestedPaths.contains { $0.split(separator: "/").dropLast().contains("journal") })

        parseTask = Task(priority: .utility) { [weak self, indexService] in
            // Let the state change and its transition commit a frame before doing
            // any tree-sitter work on the index actor.
            await Task.yield()
            if let debounce {
                try? await Task.sleep(for: debounce)
            }
            guard !Task.isCancelled else { return }

            let started = CFAbsoluteTimeGetCurrent()
            let parsed = await indexService.parse(targets)
            let indexedJournal = shouldIndexJournal ? await indexService.journalEntries(in: journalSources) : nil
            let duration = (CFAbsoluteTimeGetCurrent() - started) * 1_000
            guard !Task.isCancelled else { return }

            guard let self, generation == self.parseGeneration else { return }
            let accepted = parsed.filter { document in
                self.documents.first { $0.path == document.path }?.contents
                    == requestedSources[document.path]
            }
            let acceptedPaths = Set(accepted.map(\.path))

            self.publish(
                accepted,
                replacingAll: replacingAll,
                refreshedPaths: acceptedPaths,
                durationMilliseconds: duration,
                indexedJournal: indexedJournal
            )
            self.pendingDirtyPaths.subtract(acceptedPaths)
            self.parseTask = nil
        }
    }

    func waitForWorkspaceIndex() async {
        while let task = parseTask {
            let generation = parseGeneration
            await task.value
            if generation == parseGeneration || Task.isCancelled { return }
        }
    }

    func resetWorkspaceIndex() {
        parseTask?.cancel()
        parseTask = nil
        parseGeneration &+= 1
        pendingDirtyPaths.removeAll()
        parsedDocuments.removeAll()
    }

    func acceptDiskDocuments(_ loaded: [WorkspaceDocument]) {
        let incomingPaths = Set(loaded.map(\.path))
        let removed = Set(documents.map(\.path)).subtracting(incomingPaths).subtracting(dirtyFilePaths)
        let previous = Dictionary(uniqueKeysWithValues: documents.map { ($0.path, $0) })
        let changed = Set(loaded.filter { previous[$0.path]?.contents != $0.contents }.map(\.path))
        let pending = documents.filter { dirtyFilePaths.contains($0.path) }
        let next = (loaded.filter { !dirtyFilePaths.contains($0.path) } + pending).sorted { $0.path < $1.path }
        guard documents != next else { return }
        for path in changed.union(removed).subtracting(dirtyFilePaths) {
            externalDocumentRevisions[path, default: 0] &+= 1
        }
        documents = next
        if !removed.isEmpty {
            parseTask?.cancel()
            parseTask = nil
            parseGeneration &+= 1
            pendingDirtyPaths.subtract(removed)
        }
        items.removeAll { removed.contains($0.source.file) }
        for path in removed { parsedDocuments.removeValue(forKey: path) }
        journalEntries.removeAll { removed.contains($0.source.file) }
        let toIndex = changed.union(pendingDirtyPaths)
        if !toIndex.isEmpty {
            scheduleWorkspaceRefresh(changedPaths: toIndex, saveFiles: false)
        }
    }

    private func publish(
        _ parsed: [ParsedOrgDocument],
        replacingAll: Bool,
        refreshedPaths: Set<String>,
        durationMilliseconds: Double,
        indexedJournal: [JournalEntry]? = nil
    ) {
        var nextDocuments = replacingAll ? [:] : parsedDocuments
        for path in refreshedPaths {
            nextDocuments.removeValue(forKey: path)
        }
        for document in parsed {
            nextDocuments[document.path] = document
        }

        let headings = parsed.flatMap(\.headings)
            .filter {
                $0.state != nil || $0.scheduled != nil || $0.deadline != nil || $0.closed != nil || $0.eventDate != nil
                    || $0.tags.contains(where: { ["note", "event", "project", "habit"].contains($0) })
            }
        let nextItems = merging(headings, into: items, refreshedPaths: refreshedPaths)
        let allDocuments = Array(nextDocuments.values)
        let nodeCount = allDocuments.reduce(0) { $0 + $1.nodeCount }
        let errorCount = allDocuments.filter(\.hasError).count
        let status = errorCount == 0
            ? String(localized: "Ready · \(allDocuments.count) files · \(nodeCount) nodes")
            : String(localized: "Ready with \(errorCount) recovery tree(s)")

        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            if parsedDocuments != nextDocuments { parsedDocuments = nextDocuments }
            if items != nextItems { items = nextItems }
            if let indexedJournal, journalEntries != indexedJournal { journalEntries = indexedJournal }
            parseDurationMilliseconds = durationMilliseconds
            parserStatus = status
        }
        if usesEmacsConfiguration { Task { await refreshReminders() } }

    }
    private func merging(
        _ headings: [IndexedOrgHeading],
        into currentItems: [OrgItem],
        refreshedPaths: Set<String>
    ) -> [OrgItem] {
        var updatedItems = currentItems
        var matchedIDs: Set<UUID> = []
        let titlesByFile = Dictionary(grouping: headings, by: { $0.source.file })
            .mapValues { Set($0.map(\.title)) }
        // Candidates grouped once by file (order preserved); each heading then
        // probes only its own file's list instead of rescanning every item.
        var candidatesByFile = Dictionary(grouping: currentItems.indices, by: { currentItems[$0].source.file })
        var existingIDs = Set(currentItems.map(\.id))

        for heading in headings {
            let candidates = candidatesByFile[heading.source.file] ?? []
            let position = candidates.firstIndex {
                currentItems[$0].source.startByte == heading.source.startByte
                    && currentItems[$0].title == heading.title
            } ?? candidates.firstIndex {
                currentItems[$0].title == heading.title
            } ?? candidates.firstIndex {
                currentItems[$0].source.startByte == heading.source.startByte
                    && titlesByFile[heading.source.file]?.contains(currentItems[$0].title) == false
            }

            if let position {
                let index = candidates[position]
                candidatesByFile[heading.source.file]?.remove(at: position)
                matchedIDs.insert(currentItems[index].id)
                updatedItems[index].title = heading.title
                updatedItems[index].state = heading.state ?? updatedItems[index].state
                updatedItems[index].hasWorkflowState = heading.state != nil
                updatedItems[index].kind = heading.tags.contains("event") ? .event
                    : (heading.tags.contains("note") ? .note : heading.kind)
                updatedItems[index].priority = heading.priority
                updatedItems[index].tags = heading.tags
                updatedItems[index].scheduled = heading.scheduled
                updatedItems[index].deadline = heading.deadline
                updatedItems[index].closed = heading.closed
                updatedItems[index].eventDate = heading.eventDate
                updatedItems[index].properties = heading.properties
                updatedItems[index].durationMinutes = heading.durationMinutes
                updatedItems[index].hasTime = heading.hasTime
                updatedItems[index].recurrence = heading.recurrence
                updatedItems[index].body = heading.body
                updatedItems[index].source = heading.source
            } else {
                let candidateID = Self.parserItemID(for: heading)
                let newID = existingIDs.contains(candidateID) ? UUID() : candidateID
                existingIDs.insert(newID)
                updatedItems.append(
                    OrgItem(
                        id: newID,
                        title: heading.title,
                        state: heading.state ?? .todo,
                        kind: heading.tags.contains("event") ? .event
                            : (heading.tags.contains("note") ? .note : heading.kind),
                        priority: heading.priority,
                        tags: heading.tags,
                        scheduled: heading.scheduled,
                        deadline: heading.deadline,
                        closed: heading.closed,
                        eventDate: heading.eventDate,
                        hasTime: heading.hasTime,
                        durationMinutes: heading.durationMinutes,
                        recurrence: heading.recurrence,
                        body: heading.body,
                        source: heading.source,
                        habitHistory: [],
                        properties: heading.properties,
                        hasWorkflowState: heading.state != nil
                    )
                )
            }
        }

        let oldIDs = Set(currentItems.map(\.id))
        return updatedItems.filter {
            !refreshedPaths.contains($0.source.file) || !oldIDs.contains($0.id) || matchedIDs.contains($0.id)
        }
    }

    private static func parserItemID(for heading: IndexedOrgHeading) -> UUID {
        let key = "\(heading.source.file):\(heading.source.startByte)"
        let first = stableHash(key.utf8, seed: 0xcbf29ce484222325)
        let second = stableHash((key + "#org").utf8, seed: 0x84222325cbf29ce4)
        let value = String(
            format: "%08llx-%04llx-%04llx-%04llx-%012llx",
            (first >> 32) & 0xffff_ffff,
            (first >> 16) & 0xffff,
            (first & 0x0fff) | 0x5000,
            ((second >> 48) & 0x3fff) | 0x8000,
            second & 0xffff_ffff_ffff
        )
        return UUID(uuidString: value)!
    }

    private static func stableHash<S: Sequence>(
        _ bytes: S,
        seed: UInt64
    ) -> UInt64 where S.Element == UInt8 {
        bytes.reduce(seed) { ($0 ^ UInt64($1)) &* 0x100000001b3 }
    }
}
