import Foundation

/// A local, one-step undo. Never overwrite edits made after the gesture.
struct WorkspaceGestureUndo {
    let label: String
    let path: String
    let before: String
    let after: String
    let previousItems: [OrgItem]
}

extension WorkspaceStore {
    func gestureChange(for item: OrgItem, label: String, perform: () -> Void) -> WorkspaceGestureUndo? {
        operationError = nil
        guard let before = documents.first(where: { $0.path == item.source.file })?.contents else {
            operationError = String(localized: "The file is no longer available.")
            return nil
        }
        let previousItems = items.filter { $0.source.file == item.source.file }
        perform()
        guard operationError == nil,
              let after = documents.first(where: { $0.path == item.source.file })?.contents,
              after != before else { return nil }
        return WorkspaceGestureUndo(label: label, path: item.source.file, before: before,
                                    after: after, previousItems: previousItems)
    }

    func reschedule(_ baseline: OrgItem, to day: Date) -> WorkspaceGestureUndo? {
        gestureChange(for: baseline, label: String(localized: "Scheduled · \(OrgendaDatePresentation.relativeDate(day))")) {
            guard items.contains(where: { $0.id == baseline.id && $0.source.file == baseline.source.file }) else {
                operationError = String(localized: "The task was moved or removed. Reopen it before rescheduling.")
                return
            }
            guard baseline.hasWorkflowState, baseline.kind != .event,
                  !(baseline.scheduled == nil && baseline.recurrence != nil && baseline.deadline != nil) else {
                operationError = String(localized: "Open the item editor to change this item's dates and repeat rule together.")
                return
            }
            var draft = baseline
            let calendar = Calendar.autoupdatingCurrent
            if let original = baseline.scheduled {
                let time = calendar.dateComponents([.hour, .minute, .second], from: original)
                draft.scheduled = calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0,
                                               second: time.second ?? 0, of: day)
            } else {
                draft.scheduled = day.startOfDay
            }
            guard save(draft, original: baseline) else {
                operationError = operationError ?? String(localized: "The task changed. Reopen it before rescheduling.")
                return
            }
        }
    }

    @discardableResult
    func undoGesture(_ change: WorkspaceGestureUndo) -> Bool {
        guard let contents = documents.first(where: { $0.path == change.path })?.contents,
              contents.utf8.elementsEqual(change.after.utf8) else {
            operationError = String(localized: "The file changed after this action. Undo would overwrite newer edits.")
            return false
        }
        updateDocument(path: change.path, contents: change.before)
        items.removeAll { $0.source.file == change.path }
        items.append(contentsOf: change.previousItems)
        scheduleWorkspaceParse()
        operationError = nil
        return true
    }

    func refileTargets(for item: OrgItem) -> [OrgRefileTarget] {
        OrgWorkflowOperations.refileTargets(in: documents).filter {
            $0.path != item.source.file || $0.headingStartByte != item.source.startByte
        }
    }

    func archiveItem(_ item: OrgItem) async -> Bool {
        await performMove(item, target: nil)
    }

    func moveItem(_ item: OrgItem, to target: OrgRefileTarget) async -> Bool {
        await performMove(item, target: target)
    }

    private func performMove(_ baseline: OrgItem, target: OrgRefileTarget?) async -> Bool {
        await synchronizeFiles()
        await waitForWorkspaceIndex()
        guard pendingFileCount == 0, !isSynchronizing,
              let current = items.first(where: { $0.id == baseline.id }),
              current.hasSameEditableValues(as: baseline),
              let source = documents.first(where: { $0.path == current.source.file }) else {
            operationError = String(localized: "The item changed or has unsaved file changes. Reopen it before moving.")
            return false
        }
        let originalDocuments = documents
        do {
            let destinationPath = try target?.path ?? OrgWorkflowOperations.archiveDestination(
                sourcePath: source.path, source: source.contents, headingStartByte: current.source.startByte).path
            let existingDestination = documents.first(where: { $0.path == destinationPath })
            let destination = existingDestination ?? WorkspaceDocument(path: destinationPath,
                title: URL(fileURLWithPath: destinationPath).lastPathComponent, contents: "", kind: .org)
            let plan: OrgMovePlan
            if let target {
                plan = try OrgWorkflowOperations.refile(source: source, headingStartByte: current.source.startByte,
                    destination: destination, target: target)
            } else {
                plan = try OrgWorkflowOperations.archive(source: source, headingStartByte: current.source.startByte,
                    destination: destination)
            }
            if let fileStore {
                isSynchronizing = true
                defer { isSynchronizing = false }
                let disk = try await fileStore.load()
                guard documents == originalDocuments,
                      disk.first(where: { $0.path == source.path })?.contents == source.contents,
                      disk.first(where: { $0.path == destination.path })?.contents == existingDestination?.contents else {
                    operationError = String(localized: "The source or destination changed. Refresh and try again.")
                    return false
                }
                try await fileStore.write(path: plan.destination.path, contents: plan.destination.contents,
                                          expectedContents: existingDestination?.contents)
                if plan.source.path != plan.destination.path {
                    // Never remove source text before the full destination exists.
                    guard documents == originalDocuments else {
                        operationError = String(localized: "A copy was saved, but an edit interrupted the move. Both copies are retained.")
                        return false
                    }
                    do {
                        try await fileStore.write(path: plan.source.path, contents: plan.source.contents,
                                                  expectedContents: source.contents)
                    } catch {
                        operationError = String(localized: "A copy was saved to \(plan.destination.path), but the source changed. Both copies are retained.")
                        let loaded = try await fileStore.load()
                        for document in loaded where document.kind != .folder && !dirtyFilePaths.contains(document.path) {
                            persistedContents[document.path] = document.contents
                        }
                        let retainedPaths = Set(loaded.map(\.path)).union(dirtyFilePaths)
                        persistedContents = persistedContents.filter { retainedPaths.contains($0.key) }
                        acceptDiskDocuments(loaded)
                        return false
                    }
                }
                let loaded = try await fileStore.load()
                for document in loaded where document.kind != .folder && !dirtyFilePaths.contains(document.path) {
                    persistedContents[document.path] = document.contents
                }
                acceptDiskDocuments(loaded)
                lastFileSync = .now
            } else {
                var next = documents.filter { $0.path != plan.source.path && $0.path != plan.destination.path }
                next.append(plan.destination)
                if plan.source.path != plan.destination.path { next.append(plan.source) }
                acceptDiskDocuments(next)
            }
            operationError = nil
            await waitForWorkspaceIndex()
            return true
        } catch {
            operationError = error.localizedDescription
            return false
        }
    }

}
