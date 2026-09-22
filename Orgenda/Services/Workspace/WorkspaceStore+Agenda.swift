import Foundation

extension WorkspaceStore {
    var agendaSourceCount: Int {
        documents.filter { $0.kind == .org && (!usesEmacsConfiguration || OrgWorkspaceConfiguration.isAgendaSource($0.path)) }.count
    }

    func agendaGroups(for perspective: OrgAgendaPerspective, now: Date = .now) -> [OrgAgendaGroup] {
        let open = agendaItems.filter { $0.isOpen && $0.hasWorkflowState }
        func sorted(_ values: [OrgItem]) -> [OrgItem] {
            values.sorted {
                let lhs = $0.priority == .none ? "B" : $0.priority.rawValue
                let rhs = $1.priority == .none ? "B" : $1.priority.rawValue
                if lhs != rhs { return lhs < rhs }
                if $0.source.file != $1.source.file { return $0.source.file < $1.source.file }
                return $0.source.startByte < $1.source.startByte
            }
        }
        func group(_ title: String, state: OrgWorkflowState, paths: Set<String> = OrgWorkspaceConfiguration.actionPaths) -> OrgAgendaGroup {
            OrgAgendaGroup(title: title, items: sorted(open.filter { $0.state == state && paths.contains($0.source.file) }), state: state)
        }
        let projects = OrgAgendaGroup(title: String(localized: "Projects"), items: sorted(open.filter {
            $0.state == .todo && $0.tags.contains("project") && OrgWorkspaceConfiguration.projectPaths.contains($0.source.file)
        }))
        switch perspective {
        case .dashboard:
            let week = (0..<7).compactMap { offset -> OrgAgendaGroup? in
                let date = now.startOfDay.adding(days: offset)
                let dayItems = items(on: date)
                guard !dayItems.isEmpty else { return nil }
                return OrgAgendaGroup(
                    title: OrgendaDatePresentation.relativeDate(date, relativeTo: now),
                    items: dayItems,
                    isDateGroup: true
                )
            }
            let dated = week.isEmpty ? [OrgAgendaGroup(title: String(localized: "This week"), items: [], isDateGroup: true)] : week
            return dated + [group(String(localized: "Urgent actions"), state: .urgent), group(String(localized: "Next actions"), state: .next), projects,
                           group(String(localized: "Waiting"), state: .wait), group(OrgAgendaPerspective.someday.localizedName, state: .someday, paths: OrgWorkspaceConfiguration.somedayPaths)]
        case .urgent: return [group(perspective.localizedName, state: .urgent)]
        case .next: return [group(perspective.localizedName, state: .next)]
        case .waiting: return [group(perspective.localizedName, state: .wait)]
        case .projects: return [projects]
        case .someday: return [group(perspective.localizedName, state: .someday, paths: OrgWorkspaceConfiguration.somedayPaths)]
        case .overdue: return [OrgAgendaGroup(title: perspective.localizedName, items: overdueItems)]
        case .todos: return [OrgAgendaGroup(title: perspective.localizedName, items: sorted(open.filter { OrgWorkspaceConfiguration.actionPaths.contains($0.source.file) }))]
        case .agenda: return []
        }
    }

    func upcomingDeadlines(now: Date = .now) -> [OrgItem] {
        let end = now.startOfDay.adding(days: OrgWorkspaceConfiguration.deadlineWarningDays)
        return agendaItems.filter {
            guard $0.isOpen, OrgWorkspaceConfiguration.datedPaths.contains($0.source.file), let deadline = $0.deadline else { return false }
            return deadline.startOfDay > now.startOfDay && deadline.startOfDay <= end
        }.sorted { $0.deadline! < $1.deadline! }
    }
}
