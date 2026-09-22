import SwiftUI

/// Native scrolling owns the only spatial animation. Keeping its tracking state
/// here avoids refreshing journal entries on every visible-date update.
struct JournalDateStrip: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var selectedDate: Date
    @State private var anchor: Date
    @State private var scrollPosition: Int?
    @ScaledMetric(relativeTo: .subheadline) private var cellWidth = 44.0
    @ScaledMetric(relativeTo: .subheadline) private var cellHeight = 54.0
    private let offsets = -730...730

    init(selectedDate: Binding<Date>) {
        _selectedDate = selectedDate
        _anchor = State(initialValue: selectedDate.wrappedValue.startOfDay)
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView(.horizontal) {
                GlassEffectContainer(spacing: 0) {
                    LazyHStack(spacing: 0) {
                        ForEach(offsets, id: \.self) { offset in
                            dateCell(anchor.adding(days: offset))
                                .padding(.horizontal, 4)
                                .frame(width: cellWidth + 8)
                                .id(offset)
                        }
                    }
                    .scrollTargetLayout()
                }
            }
            .safeAreaPadding(.horizontal, max((geometry.size.width - cellWidth - 8) / 2, 0))
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(JournalDateSnapBehavior(slotWidth: cellWidth + 8))
            .scrollPosition(id: $scrollPosition, anchor: .center)
            .defaultScrollAnchor(.center)
            .scrollEdgeEffectStyle(.soft, for: [.leading, .trailing])
            .accessibilityLabel("Journal dates")
            .accessibilityIdentifier("journal.date.strip")
            .task {
                scrollPosition = Calendar.autoupdatingCurrent.dateComponents(
                    [.day], from: anchor, to: selectedDate.startOfDay
                ).day ?? 0
            }
            .onScrollPhaseChange { previous, phase in
                guard phase == .idle,
                      previous == .interacting || previous == .decelerating,
                      let offset = scrollPosition else { return }
                // Native snapping has already centered this date. Commit the
                // selection without a second scroll command or layout spring.
                selectedDate = anchor.adding(days: offset)
            }
            .onChange(of: selectedDate) { _, date in
                let offset = Calendar.autoupdatingCurrent.dateComponents(
                    [.day], from: anchor, to: date.startOfDay
                ).day ?? 0
                guard offsets.contains(offset), scrollPosition != offset else { return }
                withAnimation(reduceMotion ? nil : JournalMotion.dateChange) {
                    scrollPosition = offset
                }
            }
            .sensoryFeedback(.selection, trigger: selectedDate)
        }
        .frame(height: cellHeight + 4)
    }

    private func dateCell(_ date: Date) -> some View {
        let calendar = Calendar.autoupdatingCurrent
        return OrgendaDateButton(
            date: date,
            isSelected: calendar.isDate(date, inSameDayAs: selectedDate),
            isToday: calendar.isDateInToday(date),
            showsWeekday: true
        ) {
            selectedDate = date
        }
        .frame(width: cellWidth, height: cellHeight)
        .accessibilityHint("Selects and centers this journal date")
        .accessibilityIdentifier("journal.date.\(date.orgendaDayKey)")
    }
}

/// Snap the predicted stopping position to the fixed date grid before
/// deceleration begins, rather than correcting an approximate view target later.
private struct JournalDateSnapBehavior: ScrollTargetBehavior {
    let slotWidth: CGFloat

    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        let snapped = (target.rect.minX / slotWidth).rounded() * slotWidth
        let lastSlot = max(0, context.contentSize.width - context.containerSize.width)
        target.rect.origin.x = min(max(snapped, 0), lastSlot)
        target.anchor = .leading
    }
}
