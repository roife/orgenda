import CryptoKit
import Foundation
import UserNotifications

struct OrgReminder: Equatable {
    let id: String
    let title: String
    let body: String
    let date: Date
}

enum OrgReminderPlan {
    /// Builds the reminder plan from already-parsed documents. The workspace
    /// pipeline calls this with its index results so reminder scheduling never
    /// re-parses the workspace.
    static func reminders(
        for items: [OrgItem], parsed: [String: ParsedOrgDocument], now: Date = .now
    ) -> [OrgReminder] {
        var reminders: [OrgReminder] = []
        for item in items where item.isOpen {
            for timestamp in timestamps(for: item, parsed: parsed[item.source.file]) where timestamp.includesTime {
                let base = timestamp.date
                let minutes = item.appointmentWarningMinutes ?? OrgWorkspaceConfiguration.appointmentWarningMinutes
                var occurrence = base
                if occurrence < now, let token = timestamp.recurrence, let firstDigit = token.firstIndex(where: \.isNumber) {
                    // ++ produces the next occurrence on the existing cadence.
                    let upcoming = OrgRepeater("++" + token[firstDigit...])
                    occurrence = upcoming?.nextDate(afterCompletion: now, from: base) ?? base
                }
                let offsets = Set(Array(stride(from: min(minutes, 1_440), through: 0, by: -OrgWorkspaceConfiguration.appointmentRepeatMinutes)) + [0])
                for offset in offsets {
                    let fire = occurrence.addingTimeInterval(-Double(offset) * 60)
                    guard fire > now else { continue }
                    let key = "\(item.source.file):\(item.source.startByte):\(occurrence.timeIntervalSince1970):\(offset)"
                    let hash = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
                    reminders.append(OrgReminder(id: "orgenda.org.\(hash)", title: item.title,
                        body: offset == 0 ? String(localized: "Starting now") : String(localized: "Starts in \(offset) minutes"), date: fire))
                }
            }
        }
        return Array(Dictionary(grouping: reminders, by: \.id).compactMap { $0.value.first }.sorted { $0.date < $1.date }.prefix(60))
    }

    /// Convenience entry point that parses the given documents first. Tests and
    /// call sites without an index use this; the workspace pipeline prefers the
    /// `parsed:` overload.
    static func reminders(for items: [OrgItem], documents: [WorkspaceDocument] = [], now: Date = .now) -> [OrgReminder] {
        let parsed = Dictionary(uniqueKeysWithValues: OrgIndexService.parseSynchronously(documents).map { ($0.path, $0) })
        return reminders(for: items, parsed: parsed, now: now)
    }

    private struct Timestamp {
        let date: Date
        let includesTime: Bool
        let recurrence: String?
    }

    private static func timestamps(for item: OrgItem, parsed: ParsedOrgDocument?) -> [Timestamp] {
        guard let parsed, let index = parsed.root.children.firstIndex(where: {
            $0.type == "heading" && $0.startByte == item.source.startByte
        }) else {
            // Without source metadata only the primary date has known time and
            // repeater semantics. Never infer a midnight alert for another date.
            return item.agendaDate.map { [Timestamp(date: $0, includesTime: item.hasTime, recurrence: item.recurrence)] } ?? []
        }
        let nodes = Array(parsed.root.children.dropFirst(index + 1).prefix { $0.type != "heading" })
        var result: [Timestamp] = []
        func append(_ draft: OrgPlanningEntryDraft?) {
            if let stamp = draft?.timestamps.first {
                result.append(Timestamp(date: stamp.date, includesTime: stamp.includesTime, recurrence: stamp.recurrence))
            }
        }
        func active(_ node: ParsedOrgNode) {
            if node.type == "timestamp_range" || node.type == "active_timestamp" {
                if node.text.hasPrefix("<") { append(OrgPlanningEntryDraft(timestampSource: node.text)) }
                return
            }
            for child in node.children { active(child) }
        }
        for node in OrgHeadingBody.nodesOutsideDrawers(in: nodes) {
            if node.type == "planning" {
                for entry in node.children where entry.type == "planning_entry" {
                    if let draft = OrgPlanningEntryDraft(source: entry.text), draft.keyword != .closed { append(draft) }
                }
            } else if ["paragraph", "list"].contains(node.type) {
                active(node)
            }
        }
        return result
    }
}

actor OrgReminderScheduler {
    private let center = UNUserNotificationCenter.current()
    private var signature: [OrgReminder]?
    private var isApplying = false
    private var revision = 0

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .badge])
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func refresh(
        items: [OrgItem], parsed: [String: ParsedOrgDocument] = [:], enabled: Bool
    ) async -> String {
        revision += 1
        let requestRevision = revision
        while isApplying {
            try? await Task.sleep(for: .milliseconds(25))
            if requestRevision != revision || Task.isCancelled { return String(localized: "Updating reminders…") }
        }
        isApplying = true
        defer { isApplying = false }
        let settings = await center.notificationSettings()
        let authorized = [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus)
        let plan = enabled && authorized ? OrgReminderPlan.reminders(for: items, parsed: parsed) : []
        if signature != plan {
            let old = await center.pendingNotificationRequests().filter { $0.identifier.hasPrefix("orgenda.org.") }.map(\.identifier)
            center.removePendingNotificationRequests(withIdentifiers: old)
            do {
                for reminder in plan {
                    let content = UNMutableNotificationContent()
                    content.title = reminder.title
                    content.body = reminder.body
                    // appt-audible is nil in the imported configuration.
                    content.sound = nil
                    let components = Calendar.autoupdatingCurrent.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.date)
                    let request = UNNotificationRequest(identifier: reminder.id, content: content,
                        trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
                    try await center.add(request)
                }
                signature = plan
            } catch { return String(localized: "Could not schedule reminders: \(error.localizedDescription)") }
        }
        if settings.authorizationStatus == .denied { return String(localized: "Notifications disabled in Settings") }
        guard enabled else { return String(localized: "Off") }
        guard authorized else { return String(localized: "Notifications disabled in Settings") }
        return String(localized: "\(plan.count) notifications scheduled")
    }
}
