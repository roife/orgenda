import Foundation

extension WorkspaceStore {
    var primaryConfiguredPerspective: OrgAgendaPerspective { hasWorkspaceConfiguration ? .dashboard : .todos }
    var dashboardPerspectives: [OrgAgendaPerspective] {
        let views: [OrgAgendaPerspective] = hasWorkspaceConfiguration
            ? [.dashboard, .overdue, .todos] : [.overdue, .todos]
        let statuses = effectiveConfiguration.workflow.states.filter { !$0.isTerminal }.map { OrgAgendaPerspective.status($0) }
        return views + statuses
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
        if case .status(let state) = perspective {
            return [OrgAgendaGroup(title: state.title,
                                   items: sorted(open.filter { $0.state.rawValue == state.rawValue }), state: state)]
        }
        if hasWorkspaceConfiguration {
            if perspective == .todos { return [OrgAgendaGroup(title: perspective.localizedName, items: openTodos)] }
            if perspective == .overdue { return [OrgAgendaGroup(title: perspective.localizedName, items: overdueItems)] }
            if perspective == .dashboard {
                let dates = (0..<7).map { offset in
                    let date = now.startOfDay.adding(days: offset)
                    return OrgAgendaGroup(title: OrgendaDatePresentation.relativeDate(date, relativeTo: now),
                                          items: items(on: date), isDateGroup: true)
                }
                // A fixed dashboard follows the configured state sequence;
                // there is no separate user-programmable query/view system.
                return dates + configuration.workflow.states.filter { !$0.isTerminal }.map { state in
                    OrgAgendaGroup(title: state.title, items: openTodos.filter { $0.state.rawValue == state.rawValue })
                }
            }
            return []
        }
        return []
    }

    func upcomingDeadlines(now: Date = .now) -> [OrgItem] {
        let end = now.startOfDay.adding(days: effectiveConfiguration.reminders.deadlineWarningDays)
        return agendaItems.filter {
            guard $0.isOpen, let deadline = $0.deadline else { return false }
            return deadline.startOfDay > now.startOfDay && deadline.startOfDay <= end
        }.sorted { $0.deadline! < $1.deadline! }
    }
}
