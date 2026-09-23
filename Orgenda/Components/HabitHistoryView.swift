import SwiftUI

struct HabitHistoryView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let completedDates: Set<String>

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: dynamicTypeSize.isAccessibilitySize ? 7 : 14), spacing: 4) {
            ForEach((0..<28).reversed(), id: \.self) { offset in
                let date = Date.now.adding(days: -offset)
                RoundedRectangle(cornerRadius: 2)
                    .fill(completedDates.contains(date.orgendaDayKey) ? OrgendaTheme.habit : Color.secondary.opacity(0.14))
                    .aspectRatio(1, contentMode: .fit)
                    .accessibilityLabel(date.formatted(date: .abbreviated, time: .omitted))
                    .accessibilityValue(completedDates.contains(date.orgendaDayKey) ? "Completed" : "Not completed")
                    .accessibilityIdentifier("habit.history.\(date.orgendaDayKey)")
            }
        }
    }
}
