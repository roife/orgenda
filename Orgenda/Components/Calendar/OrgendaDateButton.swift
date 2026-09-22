import SwiftUI

enum OrgendaDateLayout {
    static let dayDiameter: CGFloat = 34
    static let dayNumberSize: CGFloat = 15
    static let weekdayLineHeight: CGFloat = 17
    static let eventMarkerDiameter: CGFloat = 3
    static let eventMarkerSpacing: CGFloat = 2
    static let dayCellHeight: CGFloat = 44

    static func accessibleDayDiameter(numberSize: CGFloat) -> CGFloat {
        max(dayDiameter, numberSize * 1.4 + 12)
    }
}

struct OrgendaDateButton: View {
    struct Selection {
        let id: String
        let namespace: Namespace.ID
    }

    let date: Date
    let isSelected: Bool
    let isToday: Bool
    var isDimmed = false
    var showsWeekday = false
    var scalesForAccessibility = false
    // A non-nil value reserves the marker slot, even on unmarked dates.
    var eventMarker: Bool? = nil
    var selection: Selection? = nil
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .subheadline) private var scaledDayNumberSize = OrgendaDateLayout.dayNumberSize

    private var isWeekend: Bool {
        let weekday = Calendar.autoupdatingCurrent.component(.weekday, from: date)
        return weekday == 1 || weekday == 7
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: showsWeekday ? 3 : OrgendaDateLayout.eventMarkerSpacing) {
                if showsWeekday {
                    Text(date.formatted(.dateTime.weekday(.narrow)).uppercased())
                        .font(.footnote.weight(.semibold))
                        .lineLimit(1)
                        .fixedSize()
                        .foregroundStyle(isWeekend ? OrgendaTheme.weekend : .secondary)
                }

                dayNumber

                if let eventMarker {
                    Circle()
                        .fill(eventMarker ? OrgendaTheme.accent : .clear)
                        .frame(
                            width: OrgendaDateLayout.eventMarkerDiameter,
                            height: OrgendaDateLayout.eventMarkerDiameter
                        )
                }
            }
            .dynamicTypeSize(scalesForAccessibility ? dynamicTypeSize : min(dynamicTypeSize, .xxxLarge))
            .frame(maxWidth: .infinity, minHeight: OrgendaDateLayout.dayCellHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(date.formatted(date: .complete, time: .omitted))
        .accessibilityValue(isToday ? "Today" : "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var selectionSurface: some View {
        let surface = Circle()
            .fill(OrgendaTheme.accent)
            .frame(width: dayDiameter, height: dayDiameter)

        if let selection, !reduceMotion {
            surface
                .matchedGeometryEffect(id: selection.id, in: selection.namespace, properties: .frame)
        } else {
            surface
                .transition(.opacity)
        }
    }

    private var dayNumber: some View {
        Text(String(Calendar.autoupdatingCurrent.component(.day, from: date)))
            .font(.subheadline.weight(isSelected ? .semibold : .regular))
            .fontDesign(.rounded)
            .lineLimit(1)
            .foregroundStyle(dayColor)
            .frame(width: dayDiameter, height: dayDiameter)
            .background {
                // Content selection stays in the grid's normal drawing order.
                if isSelected {
                    selectionSurface
                } else if isToday {
                    Circle()
                        .stroke(OrgendaTheme.accent.opacity(0.72), lineWidth: 1.5)
                }
            }
    }

    private var dayDiameter: CGFloat {
        guard scalesForAccessibility && dynamicTypeSize.isAccessibilitySize else {
            return OrgendaDateLayout.dayDiameter
        }
        return OrgendaDateLayout.accessibleDayDiameter(numberSize: scaledDayNumberSize)
    }

    private var dayColor: Color {
        if isSelected { return .white }
        let opacity = isDimmed ? (colorSchemeContrast == .increased ? 0.75 : 0.55) : 1
        return (isWeekend ? OrgendaTheme.weekend : OrgendaTheme.ink).opacity(opacity)
    }
}
