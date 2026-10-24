import SwiftUI

struct SearchJournalDetail: View {
    let entry: JournalEntry

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OrgendaSpacing.pageMargin) {
                Label(OrgendaDatePresentation.dateTime(entry.date), systemImage: "calendar")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(entry.title)
                    .font(.title.weight(.bold))
                Text(entry.body)
                    .font(.body)
                    .lineSpacing(OrgendaSpacing.compactInset)
            }
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(OrgendaSpacing.documentInsets)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .scrollEdgeEffectStyle(.soft, for: [.top, .bottom])
        .navigationTitle("Journal Entry")
        .navigationBarTitleDisplayMode(.inline)
    }
}
