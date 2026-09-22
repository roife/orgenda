import SwiftUI

struct SearchJournalDetail: View {
    let entry: JournalEntry

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Label(OrgendaDatePresentation.dateTime(entry.date), systemImage: "calendar")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(entry.title)
                    .font(.title.weight(.bold))
                Text(entry.body)
                    .font(.body)
                    .lineSpacing(5)
            }
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .scrollEdgeEffectStyle(.soft, for: [.top, .bottom])
        .navigationTitle("Journal Entry")
        .navigationBarTitleDisplayMode(.inline)
    }
}
