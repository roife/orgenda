import SwiftUI

struct JournalDayContent: View {
    let entries: [JournalEntry]
    let onCapture: () -> Void

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            if entries.isEmpty {
                ContentUnavailableView {
                    Label("A blank page", systemImage: "book.closed")
                } actions: {
                    Button("Write an Entry", systemImage: "square.and.pencil", action: onCapture)
                        .buttonStyle(.glass)
                        .foregroundStyle(OrgendaTheme.accentText)
                        .padding(.top, 16)
                }
                .accessibilityIdentifier("journal.empty")
                .padding(.top, 44)
            } else {
                ForEach(entries) { entry in
                    JournalTimelineEntry(entry: entry, isLast: entry.id == entries.last?.id)
                }
            }
        }
    }
}
private struct JournalTimelineEntry: View {
    let entry: JournalEntry
    let isLast: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(entry.date.formatted(date: .omitted, time: .shortened))
                .font(.subheadline.monospacedDigit().weight(.medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(entry.title)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("journal.entry.title.\(entry.id)")
            if !entry.body.isEmpty {
                Text(entry.body)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(3)
                    .textSelection(.enabled)
            }
        }
        .padding(.leading, 28)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .topLeading) {
            ZStack(alignment: .top) {
                if !isLast {
                    Rectangle()
                        .fill(OrgendaTheme.accent.opacity(0.18))
                        .frame(width: 1)
                        .padding(.top, 10)
                }
                Circle()
                    .fill(OrgendaTheme.accent)
                    .frame(width: 9, height: 9)
                    .padding(.top, 5)
            }
            .frame(width: 12, alignment: .top)
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("journal.entry.\(entry.id)")
    }

}
