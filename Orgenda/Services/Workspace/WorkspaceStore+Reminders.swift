import Foundation

extension WorkspaceStore {
    func refreshReminders(requestPermission: Bool = false) async {
        reminderPermissionDenied = await reminderScheduler.authorizationStatus() == .denied
        guard usesEmacsConfiguration else {
            reminderStatus = String(localized: "Connect a folder to use reminders")
            return
        }
        if requestPermission {
            do {
                // Keep the user's preference separate from system permission.
                // Denial must remain visible and recoverable in Settings.
                _ = try await reminderScheduler.requestAuthorization()
                reminderPermissionDenied = await reminderScheduler.authorizationStatus() == .denied
            } catch {
                reminderStatus = error.localizedDescription
                return
            }
        }
        reminderStatus = await reminderScheduler.refresh(items: agendaItems, parsed: parsedDocuments,
            enabled: UserDefaults.standard.bool(forKey: "orgRemindersEnabled"))
    }
}
