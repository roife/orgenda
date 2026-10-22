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
        guard let before = documentsByPath[item.source.file]?.contents else {
            operationError = String(localized: "The file is no longer available.")
            return nil
        }
        let previousItems = items.filter { $0.source.file == item.source.file }
        perform()
        guard operationError == nil,
              let after = documentsByPath[item.source.file]?.contents,
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
        guard let contents = documentsByPath[change.path]?.contents,
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
        OrgWorkflowOperations.refileTargets(in: documents, refilePaths: Set(configuration.files.refile),
                                           maxLevel: configuration.files.refileMaxLevel).filter {
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
        await persistFileEdits()
        await waitForWorkspaceIndex()
        guard dirtyFilePaths.isEmpty, fileSaveErrors.isEmpty,
              let current = items.first(where: { $0.id == baseline.id }),
              current.hasSameEditableValues(as: baseline),
              let source = documentsByPath[current.source.file] else {
            operationError = String(localized: "The item changed or has unsaved file changes. Reopen it before moving.")
            return false
        }
        let originalDocuments = documents
        do {
            guard let localStore else { throw StorageError.rootUnavailable }
            let destinationPath = try target?.path ?? OrgWorkflowOperations.archiveDestination(
                sourcePath: source.path, source: source.contents, headingStartByte: current.source.startByte,
                defaultLocation: configuration.files.archive).path
            let existingDestination = documentsByPath[destinationPath]
            let destination = existingDestination ?? WorkspaceDocument(path: destinationPath,
                title: URL(fileURLWithPath: destinationPath).lastPathComponent, contents: "", kind: .org)
            let plan: OrgMovePlan
            if let target {
                plan = try OrgWorkflowOperations.refile(source: source, headingStartByte: current.source.startByte,
                    destination: destination, target: target, refilePaths: Set(configuration.files.refile),
                    maxLevel: configuration.files.refileMaxLevel)
            } else {
                plan = try OrgWorkflowOperations.archive(source: source, headingStartByte: current.source.startByte,
                    destination: destination, defaultLocation: configuration.files.archive)
            }
            let diskSource = try await localStore.document(at: source.path)
            let diskDestination = try await localStore.document(at: destination.path)
            guard documents == originalDocuments,
                  diskSource?.contents == source.contents,
                  diskDestination?.contents == existingDestination?.contents else {
                operationError = String(localized: "The source or destination changed. Refresh and try again.")
                return false
            }
            try await localStore.refile(source: plan.source, destination: plan.destination,
                expectedSource: source.contents, expectedDestination: existingDestination?.contents)
            applyStorageSnapshot(try await localStore.snapshot())
            operationError = nil
            await waitForWorkspaceIndex()
            Task { await self.synchronizeFiles(automatic: true, pushOnly: true) }
            return true
        } catch {
            operationError = error.localizedDescription
            return false
        }
    }

}
