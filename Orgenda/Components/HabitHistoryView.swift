import SwiftUI

struct HabitHistoryView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let completedDates: Set<String>

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: OrgendaSpacing.compactInset), count: dynamicTypeSize.isAccessibilitySize ? 7 : 14), spacing: OrgendaSpacing.compactInset) {
            ForEach((0..<28).reversed(), id: \.self) { offset in
                let date = Date.now.adding(days: -offset)
                OrgendaCorners.indicator
                    .fill(completedDates.contains(date.orgendaDayKey) ? OrgendaTheme.habit : OrgendaTheme.habitPlaceholder)
                    .aspectRatio(1, contentMode: .fit)
                    .accessibilityLabel(date.formatted(date: .abbreviated, time: .omitted))
                    .accessibilityValue(completedDates.contains(date.orgendaDayKey) ? "Completed" : "Not completed")
                    .accessibilityIdentifier("habit.history.\(date.orgendaDayKey)")
            }
        }
    }
}
