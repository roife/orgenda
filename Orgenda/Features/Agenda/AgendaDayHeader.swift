import SwiftUI

struct AgendaDayHeader: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let date: Date
    let count: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: OrgendaSpacing.contentInset) {
            let dateLayout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: OrgendaSpacing.compactInset))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: OrgendaSpacing.rowInset))
            dateLayout {
                Text((OrgendaDatePresentation.relativeDayName(for: date)
                      ?? date.formatted(.dateTime.weekday(.abbreviated))).uppercased())
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Calendar.autoupdatingCurrent.isDateInWeekend(date) ? OrgendaTheme.accent : .primary)
                Text(OrgendaDatePresentation.date(date))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            if count > 0 {
                Text("\(count)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .accessibilityLabel("\(count) items")
            }
        }
        .padding(.horizontal, OrgendaSpacing.pageMargin)
        .padding(.vertical, OrgendaSpacing.rowInset)
        .background(OrgendaTheme.pinnedHeaderBackground)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("orgenda.agenda.day.\(date.orgendaDayKey)")
    }

}
