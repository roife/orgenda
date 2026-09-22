import SwiftUI

struct JournalDayContent: View {
    let entries: [JournalEntry]
    let onCapture: () -> Void

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 14) {
            if entries.isEmpty {
                ContentUnavailableView {
                    Label("A blank page", systemImage: "book.closed")
                } description: {
                    Text("A thought, a small win, or something to remember.")
                } actions: {
                    Button("Write an Entry", systemImage: "square.and.pencil", action: onCapture)
                        .buttonStyle(.glass)
                        .foregroundStyle(OrgendaTheme.accentText)
                }
                .padding(.top, 44)
            } else {
                ForEach(entries) { entry in
                    JournalEntryCard(entry: entry)
                }
            }
        }
    }
}
private struct JournalEntryCard: View {
    let entry: JournalEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(entry.title)
                        .font(.headline)
                    Spacer(minLength: 0)
                    entryTime
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.title)
                        .font(.headline)
                    entryTime
                }
            }
            Text(entry.body)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(3)
                .textSelection(.enabled)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(.primary.opacity(0.06), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }

    private var entryTime: some View {
        Text(entry.date.formatted(date: .omitted, time: .shortened))
            .font(.subheadline.monospacedDigit().weight(.medium))
            .foregroundStyle(.secondary)
            .fixedSize()
    }
}
