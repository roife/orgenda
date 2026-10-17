import Foundation
import SwiftUI

extension WorkspaceStore {
    func parseWorkspace() {
        parseTask?.cancel()
        parseTask = nil
        parseGeneration &+= 1
        pendingDirtyPaths.removeAll()

        let parsed = OrgIndexService.parseSynchronously(documents, configuration: effectiveConfiguration)

        publish(
            parsed,
            replacingAll: true,
            refreshedPaths: Set(documents.filter { $0.kind == .org }.map(\.path))
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
        let configuration = effectiveConfiguration

        let replacingAll = parsedDocuments.isEmpty
        let requestedPaths = replacingAll
            ? Set(documents.filter { $0.kind == .org }.map(\.path))
            : pendingDirtyPaths
        let targets = requestedPaths.sorted().compactMap { documentsByPath[$0] }.filter { $0.kind == .org }
        guard !targets.isEmpty else { return }
        let requestedSources = Dictionary(uniqueKeysWithValues: targets.map { ($0.path, $0.contents) })

        parseTask = Task(priority: .utility) { [weak self, indexService] in
            // Let the state change and its transition commit a frame before doing
            // any tree-sitter work on the index actor.
            await Task.yield()
            if let debounce {
                try? await Task.sleep(for: debounce)
            }
            guard !Task.isCancelled else { return }

            let parsed = await indexService.parse(targets, configuration: configuration)
            guard !Task.isCancelled else { return }

            guard let self, generation == self.parseGeneration else { return }
            let accepted = parsed.filter { document in
                guard let current = self.documentsByPath[document.path]?.contents,
                      let requested = requestedSources[document.path] else { return false }
                return current.utf8.elementsEqual(requested.utf8)
            }
            let acceptedPaths = Set(accepted.map(\.path))

            self.publish(
                accepted,
                replacingAll: replacingAll,
                refreshedPaths: acceptedPaths
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
        let changed = Set(loaded.filter { document in
            guard let old = previous[document.path] else { return true }
            return !old.contents.utf8.elementsEqual(document.contents.utf8)
        }.map(\.path))
        let pending = documents.filter { dirtyFilePaths.contains($0.path) }
        let next = (loaded.filter { !dirtyFilePaths.contains($0.path) } + pending).sorted { $0.path < $1.path }
        // Canonically equivalent Swift strings can have different UTF-8 byte
        // ranges. Source-based editors must accept and reindex those changes.
        guard documents != next || !changed.isEmpty else { return }
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

    func acceptStorageDelta(_ delta: WorkspaceSnapshot) {
        let removed = delta.removedPaths.subtracting(dirtyFilePaths)
        var changed = Set<String>()
        for document in delta.documents where !dirtyFilePaths.contains(document.path) {
            let previous = documentsByPath[document.path]
            if previous?.kind != document.kind || previous?.contents.utf8.elementsEqual(document.contents.utf8) != true {
                documentsByPath[document.path] = document
                changed.insert(document.path)
            }
        }
        for path in removed { documentsByPath.removeValue(forKey: path); parsedDocuments.removeValue(forKey: path) }
        guard !changed.isEmpty || !removed.isEmpty else { return }
        storageContentGeneration &+= 1
        for path in changed.union(removed) { externalDocumentRevisions[path, default: 0] &+= 1 }
        items.removeAll { removed.contains($0.source.file) }
        journalEntries.removeAll { removed.contains($0.source.file) }
        pendingDirtyPaths.subtract(removed)
        if !changed.isEmpty { scheduleWorkspaceRefresh(changedPaths: changed, saveFiles: false) }
    }

    private func publish(
        _ parsed: [ParsedOrgDocument],
        replacingAll: Bool,
        refreshedPaths: Set<String>
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
        let allDocuments = nextDocuments.values
        let indexedJournal = isFolderConnected
            ? allDocuments.sorted { $0.path < $1.path }.flatMap(\.journalEntries) : nil
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            if parsedDocuments != nextDocuments { parsedDocuments = nextDocuments }
            if items != nextItems { items = nextItems }
            if let indexedJournal, journalEntries != indexedJournal { journalEntries = indexedJournal }
        }
        if hasWorkspaceConfiguration { Task { await refreshReminders() } }

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

            let index = position.map { candidates[$0] }
            let previous = index.map { currentItems[$0] }
            let id: UUID
            if let position, let previous {
                candidatesByFile[heading.source.file]?.remove(at: position)
                matchedIDs.insert(previous.id)
                id = previous.id
            } else {
                let candidateID = Self.parserItemID(for: heading)
                id = existingIDs.contains(candidateID) ? UUID() : candidateID
                existingIDs.insert(id)
            }
            let item = OrgItem(
                id: id, title: heading.title, state: heading.state ?? previous?.state ?? .todo,
                kind: heading.tags.contains("event") ? .event
                    : (heading.tags.contains("note") ? .note : heading.kind),
                priority: heading.priority, tags: heading.tags,
                scheduled: heading.scheduled, deadline: heading.deadline, closed: heading.closed,
                eventDate: heading.eventDate, hasTime: heading.hasTime,
                durationMinutes: heading.durationMinutes, recurrence: heading.recurrence,
                body: heading.body, source: heading.source,
                habitHistory: previous?.habitHistory ?? [], properties: heading.properties,
                hasWorkflowState: heading.state != nil
            )
            if let index { updatedItems[index] = item }
            else { updatedItems.append(item) }
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
