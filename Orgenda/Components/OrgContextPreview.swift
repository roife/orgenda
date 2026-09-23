import SwiftUI

/// A bounded, read-only snapshot: presenting a menu never opens an editor,
/// starts file loading, or changes the workspace.
struct OrgContextPreview<Content: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    var tint: Color = OrgendaTheme.accentText
    var state: OrgWorkflowState? = nil
    var titleColor: Color = .primary
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text(title).foregroundStyle(titleColor).lineLimit(3)
            } icon: {
                if let state {
                    OrgWorkflowIcon(state)
                } else {
                    Image(systemName: systemImage).foregroundStyle(tint)
                }
            }
            .font(.headline)
            content
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(20)
        .frame(width: 300, alignment: .leading)
        .background(Color(uiColor: .systemBackground))
    }
}

struct OrgItemContextPreview: View {
    let item: OrgItem

    var body: some View {
        OrgContextPreview(title: item.title, subtitle: item.source.file,
                          systemImage: item.kind.systemImage, tint: OrgendaTheme.kindColor(item.kind),
                          state: item.hasWorkflowState ? item.state : nil,
                          titleColor: item.hasWorkflowState ? item.workflowTitleColor : .primary) {
            if let date = item.agendaDate {
                Label(item.hasTime ? OrgendaDatePresentation.dateTime(date) : OrgendaDatePresentation.relativeDate(date),
                      systemImage: "calendar")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if !item.body.isEmpty {
                Text(String(item.body.prefix(800)))
                    .font(.body)
                    .lineLimit(8)
            }
            if !item.tags.isEmpty {
                Text(item.tags.map { "#\($0)" }.joined(separator: "  "))
                    .font(.caption)
                    .foregroundStyle(OrgendaTheme.accentText)
                    .lineLimit(2)
            }
            if item.kind == .habit {
                habitHistory
            }
        }
        .accessibilityIdentifier("org.item.contextPreview")
    }

    private var habitHistory: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("28-day history")
                .font(.caption)
                .foregroundStyle(.secondary)
            HabitHistoryView(completedDates: Set(item.habitHistory.map(\.orgendaDayKey)))
            HStack {
                Text(OrgendaDatePresentation.date(.now.adding(days: -27)))
                Spacer()
                Text("Today")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("org.item.contextPreview.habitHistory")
    }
}
