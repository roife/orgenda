import SwiftUI

struct OrgendaDateHeading: View {
    let date: Date
    var displayedMonth: Date? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .largeTitle) private var dayNumberSize = 50.0

    private let calendar = Calendar.autoupdatingCurrent
    private var month: Date { displayedMonth ?? date }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                Text(date.formatted(.dateTime.month(.abbreviated).day().year()))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(OrgendaTheme.ink)
            } else {
                HStack(alignment: .lastTextBaseline, spacing: 12) {
                    Text(String(calendar.component(.day, from: date)))
                        .font(.system(size: dayNumberSize, weight: .bold, design: .rounded))
                        .foregroundStyle(OrgendaTheme.ink)
                        .fixedSize()
                        .contentTransition(reduceMotion ? .opacity : .numericText(
                            value: Double(calendar.component(.day, from: date))
                        ))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(date.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        monthLabel
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(date.formatted(date: .complete, time: .omitted))
    }

    private var monthLabel: some View {
        let ordinal = calendar.component(.year, from: month) * 12
            + calendar.component(.month, from: month)
        return Text(OrgendaDatePresentation.monthHeading(month))
            .font(.title3.weight(.semibold))
            .foregroundStyle(OrgendaTheme.ink)
            .contentTransition(reduceMotion ? .opacity : .numericText(value: Double(ordinal)))
    }
}
