import SwiftUI

struct AgendaStartupSkeleton: View {
    let date: Date
    let showsCalendar: Bool
    let compactRows: Bool
    @Environment(\.orgendaCalendarMinimumDensity) private var minimumDensity

    // Reuse the real row typography and layout so Dynamic Type and future row
    // changes also apply to the loading state. These items never reach the store.
    private static let placeholderItems = (0..<3).map { _ in
        OrgItem(
            id: UUID(), title: String(localized: "Loading workspace"),
            state: WorkspaceConfiguration.standard.workflow.initial, kind: .task, priority: .none, tags: [],
            scheduled: nil, deadline: nil, hasTime: false, durationMinutes: 0,
            recurrence: nil, body: "",
            source: SourceLocation(file: "inbox.org", startByte: 0, endByte: 0, startLine: 1),
            habitHistory: []
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsCalendar {
                OrgendaCalendar(
                    selectedDate: .constant(date),
                    density: .constant(minimumDensity),
                    markedDates: [],
                    controlsInHeader: true,
                    onCapture: {}
                )
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: showsCalendar ? OrgendaSpacing.contentInset : OrgendaSpacing.pageMargin) {
                    ForEach(0..<3) { section in
                        VStack(alignment: .leading, spacing: OrgendaSpacing.inlineGap) {
                            AgendaDayHeader(date: date.adding(days: section), count: section == 0 ? 3 : 2)
                            ForEach(Self.placeholderItems.prefix(section == 0 ? 3 : 2)) { item in
                                OrgItemRow(
                                    item: item, onToggle: {}, onOpen: {},
                                    topPadding: compactRows ? OrgendaSpacing.inlineGap : OrgendaSpacing.contentInset,
                                    bottomPadding: compactRows ? OrgendaSpacing.rowInset : OrgendaSpacing.contentInset,
                                    allowsSwipeActions: false
                                )
                                .padding(.horizontal, OrgendaSpacing.pageMargin)
                            }
                        }
                    }
                }
                .padding(.top, showsCalendar ? 0 : OrgendaSpacing.contentInset)
                .padding(.bottom, OrgendaSpacing.scrollBottomInset)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
                .redacted(reason: .placeholder)
            }
            .scrollDisabled(true)
            .scrollIndicators(.hidden)
        }
        .disabled(true)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading workspace")
        .accessibilityValue(showsCalendar ? "Calendar" : "Dashboard")
        .accessibilityIdentifier("workspace.loading")
    }
}
