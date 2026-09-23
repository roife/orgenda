import SwiftUI

struct OrgendaDateHeading: View, Animatable {
    let date: Date
    var displayedMonth: Date? = nil
    var yearExpansion: CGFloat = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .largeTitle) private var dayNumberSize = 50.0
    @ScaledMetric(relativeTo: .title3) private var monthYearSize = 20.0
    @ScaledMetric(relativeTo: .largeTitle) private var expandedYearSize = 34.0
    @ScaledMetric(relativeTo: .subheadline) private var accessibleYearSize = 17.0

    var animatableData: CGFloat {
        get { yearExpansion }
        set { yearExpansion = newValue }
    }

    private let calendar = Calendar.autoupdatingCurrent
    private var month: Date { displayedMonth ?? date }
    private var progress: CGFloat { min(max(yearExpansion, 0), 1) }
    private var detailOpacity: CGFloat {
        let fade = min(progress / 0.45, 1)
        return 1 - fade * fade * (3 - 2 * fade)
    }
    private var year: String {
        calendar.component(.year, from: month).formatted(.number.grouping(.never))
    }
    private var sourceYearSize: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? accessibleYearSize : monthYearSize
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                HStack(alignment: .lastTextBaseline, spacing: 0) {
                    Text(accessibleDateParts.prefix)
                        .opacity(detailOpacity)
                        .offset(y: sourceYearSize * progress)
                    yearPlaceholder
                    Text(accessibleDateParts.suffix)
                        .opacity(detailOpacity)
                        .offset(y: sourceYearSize * progress)
                }
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
                        .opacity(detailOpacity)
                        .offset(x: -12 * progress)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(date.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .opacity(detailOpacity)
                            .offset(y: sourceYearSize * progress)
                        monthLabel
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlayPreferenceValue(CalendarYearAnchor.self) { anchor in
            GeometryReader { proxy in
                if let anchor {
                    let source = proxy[anchor]
                    let targetSize = dynamicTypeSize.isAccessibilitySize ? accessibleYearSize : expandedYearSize
                    // A single visible year travels from its real inline bounds
                    // to the expanded heading, including during spring settling.
                    Text(year)
                        .font(.system(size: sourceYearSize,
                                      weight: .semibold, design: .rounded))
                        .foregroundStyle(OrgendaTheme.ink)
                        .fixedSize()
                        .contentTransition(reduceMotion ? .opacity : .numericText(
                            value: Double(calendar.component(.year, from: month))
                        ))
                        .scaleEffect(1 + (targetSize / sourceYearSize - 1) * progress, anchor: .leading)
                        .frame(width: proxy.size.width, alignment: .leading)
                        .position(
                            x: proxy.size.width / 2 + source.minX * (1 - progress),
                            y: source.midY + (proxy.size.height / 2 - source.midY) * progress
                        )
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(progress < 0.5
            ? date.formatted(date: .complete, time: .omitted)
            : month.formatted(.dateTime.year()))
    }

    private var monthLabel: some View {
        let ordinal = calendar.component(.year, from: month) * 12
            + calendar.component(.month, from: month)
        return HStack(alignment: .lastTextBaseline, spacing: 0) {
            Text(month.formatted(.dateTime.month(.abbreviated)) + " ")
                .font(.title3.weight(.semibold))
                .foregroundStyle(OrgendaTheme.ink)
                .contentTransition(reduceMotion ? .opacity : .numericText(value: Double(ordinal)))
                .opacity(detailOpacity)
                .offset(y: sourceYearSize * progress)
            yearPlaceholder
        }
    }

    private var yearPlaceholder: some View {
        Text(year)
            .font(.system(size: sourceYearSize, weight: .semibold, design: .rounded))
            .fixedSize()
            .hidden()
            .anchorPreference(key: CalendarYearAnchor.self, value: .bounds) { $0 }
    }

    private var accessibleDateParts: (prefix: String, suffix: String) {
        let label = date.formatted(.dateTime.month(.abbreviated).day().year())
        let selectedYear = calendar.component(.year, from: date).formatted(.number.grouping(.never))
        guard let range = label.range(of: selectedYear, options: .backwards) else {
            return (date.formatted(.dateTime.month(.abbreviated).day()) + " ", "")
        }
        return (String(label[..<range.lowerBound]), String(label[range.upperBound...]))
    }
}

private struct CalendarYearAnchor: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? { nil }

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}
