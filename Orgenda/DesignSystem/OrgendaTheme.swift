import SwiftUI
import Synchronization

enum OrgendaTheme {
    static let syntaxTeal = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.48, green: 0.78, blue: 0.83, alpha: 1)
            : UIColor(red: 0.12, green: 0.40, blue: 0.46, alpha: 1)
    }
    static let accent = Color(red: 0.18, green: 0.43, blue: 0.53)
    // Text uses a brighter tint in dark mode; filled controls retain the accent
    // above so their white labels keep enough contrast.
    static let accentText = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.48, green: 0.76, blue: 0.84, alpha: 1)
            : UIColor(red: 0.18, green: 0.43, blue: 0.53, alpha: 1)
    })
    static let weekend = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.75, green: 0.62, blue: 0.90, alpha: 1)
            : UIColor(red: 0.43, green: 0.29, blue: 0.57, alpha: 1)
    })
    static let accentSoft = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.12, green: 0.23, blue: 0.27, alpha: 1)
            : UIColor(red: 0.91, green: 0.96, blue: 0.97, alpha: 1)
    })
    static let ink = Color.primary
    static let secondaryInk = Color.secondary
    // Opaque secondary text keeps small Preview labels readable on both surfaces.
    static let previewMetadataColor = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.72, green: 0.76, blue: 0.80, alpha: 1)
            : UIColor(red: 0.34, green: 0.38, blue: 0.42, alpha: 1)
    }
    static let previewMetadata = Color(uiColor: previewMetadataColor)
    static let overdue = Color(red: 0.76, green: 0.09, blue: 0.36)
    static let event = Color(red: 0.19, green: 0.49, blue: 0.80)
    static let habit = Color(red: 0.00, green: 0.54, blue: 0.29)

    static func kindColor(_ kind: OrgItemKind) -> Color {
        switch kind {
        case .event: event
        case .task: accent
        case .project: Color(red: 0.88, green: 0.49, blue: 0.16)
        case .habit: habit
        case .note: secondaryInk
        }
    }

    static func workflowColor(_ state: OrgWorkflowState) -> Color {
        switch state {
        case .todo: previewMetadata
        case .next: adaptiveForeground(
            UIColor(red: 0.10, green: 0.36, blue: 0.78, alpha: 1),
            UIColor(red: 0.38, green: 0.67, blue: 1.00, alpha: 1)
        )
        case .urgent: adaptiveForeground(
            UIColor(red: 0.78, green: 0.16, blue: 0.15, alpha: 1),
            UIColor(red: 1.00, green: 0.42, blue: 0.38, alpha: 1)
        )
        case .done: adaptiveForeground(
            UIColor(red: 0.52, green: 0.53, blue: 0.56, alpha: 1),
            UIColor(red: 0.62, green: 0.63, blue: 0.67, alpha: 1)
        )
        case .wait: adaptiveForeground(
            UIColor(red: 0.68, green: 0.35, blue: 0.04, alpha: 1),
            UIColor(red: 1.00, green: 0.68, blue: 0.30, alpha: 1)
        )
        case .someday: weekend
        case .canceled: adaptiveForeground(
            UIColor(red: 0.69, green: 0.20, blue: 0.43, alpha: 1),
            UIColor(red: 0.95, green: 0.53, blue: 0.72, alpha: 1)
        )
        }
    }

    private static func adaptiveForeground(_ light: UIColor, _ dark: UIColor) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
}

extension OrgWorkflowState {
    var symbol: String {
        switch self {
        case .todo: "circle"
        case .next: "arrow.right.circle"
        case .wait: "hourglass"
        case .someday: "moon"
        case .urgent: "exclamationmark.circle.fill"
        case .done: "checkmark.circle.fill"
        case .canceled: "xmark.circle"
        }
    }
}

extension OrgItem {
    var workflowTitleColor: Color {
        hasWorkflowState && state != .todo ? OrgendaTheme.workflowColor(state) : .primary
    }
}

/// One presentation for workflow states.
/// A symbol embedded in Text supplies a baseline beside multiline headings.
struct OrgWorkflowIcon: View {
    let keyword: String

    init(_ state: OrgWorkflowState) { keyword = state.rawValue }
    init(keyword: String) { self.keyword = keyword }

    var body: some View {
        let state = OrgWorkflowState(rawValue: keyword)
        Text(Image(systemName: state?.symbol ?? "questionmark.circle"))
            .foregroundStyle(state.map(OrgendaTheme.workflowColor) ?? .secondary)
            .fixedSize()
            .accessibilityLabel(state?.title ?? keyword)
    }
}

struct OrgWorkflowPicker: View {
    @Binding var selection: OrgWorkflowState

    var body: some View {
        OrgendaFlowLayout(horizontalSpacing: 2, verticalSpacing: 8) {
            ForEach(OrgWorkspaceConfiguration.taskStates) { state in
                OrgWorkflowOption(state: state, isSelected: selection == state) {
                    selection = state
                }
                .accessibilityIdentifier("workflow.option.\(state.rawValue)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Status")
        .accessibilityValue(selection.title)
    }
}

struct OrgWorkflowOption: View {
    let state: OrgWorkflowState
    let isSelected: Bool
    let action: () -> Void
    @ScaledMetric(relativeTo: .body) private var symbolSize = 21.0

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                OrgWorkflowIcon(state)
                    .font(.system(size: symbolSize, weight: .medium))
                Text(state.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(OrgendaTheme.workflowColor(state))
                    .fixedSize(horizontal: false, vertical: true)
            }
                .padding(.horizontal, 10)
                .frame(minWidth: 44, minHeight: 44)
                .background(isSelected ? OrgendaTheme.workflowColor(state).opacity(0.12) : .clear,
                            in: RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(isSelected ? OrgendaTheme.workflowColor(state) : .clear, lineWidth: 2)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(state.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Wraps readable tags without truncating them to make a horizontal row fit.
struct OrgendaTagList: View {
    let tags: [String]

    var body: some View {
        OrgendaFlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
            ForEach(Array(tags.enumerated()), id: \.offset) { _, tag in
                Text(tag)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(OrgendaTheme.accentText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(OrgendaTheme.accentSoft, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}

struct OrgendaFlowLayout: Layout {
    var horizontalSpacing: CGFloat = 8
    var verticalSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(width: proposal.width, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let positions = layout(width: bounds.width, subviews: subviews).frames
        for (subview, frame) in zip(subviews, positions) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private func layout(width: CGFloat?, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        let proposedWidth = width.flatMap { $0.isFinite ? max(0, $0) : nil }
        let limit = proposedWidth ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0
        var frames: [CGRect] = []
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: proposedWidth, height: nil))
            if x > 0, x + size.width > limit {
                x = 0
                y += rowHeight + verticalSpacing
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            usedWidth = max(usedWidth, x + size.width)
            x += size.width + horizontalSpacing
            rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: usedWidth, height: y + rowHeight), frames)
    }
}

extension Date {
    /// Shared formatter for the hot `orgendaDayKey` path; rebuilding one per call
    /// was the main cost of calendar and agenda day-key generation.
    private static let orgendaDayKeyFormatter = Mutex<DateFormatter>({
        let formatter = DateFormatter()
        formatter.calendar = .autoupdatingCurrent
        formatter.timeZone = .autoupdatingCurrent
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }())

    var startOfDay: Date { Calendar.autoupdatingCurrent.startOfDay(for: self) }

    func adding(days: Int) -> Date {
        Calendar.autoupdatingCurrent.date(byAdding: .day, value: days, to: self) ?? self
    }

    var orgendaDayKey: String {
        Self.orgendaDayKeyFormatter.withLock { $0.string(from: self) }
    }

    func orgendaDayKey(in calendar: Calendar) -> String {
        guard calendar != .autoupdatingCurrent else { return orgendaDayKey }
        let parts = calendar.dateComponents([.year, .month, .day], from: self)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

/// Context-aware date labels for browsing surfaces. The current year is
/// implied unless showing it is necessary to disambiguate another year.
enum OrgendaDatePresentation {
    static func relativeDayName(
        for date: Date,
        relativeTo reference: Date = .now,
        locale: Locale = .autoupdatingCurrent,
        calendar: Calendar = .autoupdatingCurrent
    ) -> String? {
        let offset = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: reference),
            to: calendar.startOfDay(for: date)
        ).day
        guard let offset, (-1...1).contains(offset) else { return nil }

        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.dateTimeStyle = .named
        return formatter.localizedString(from: DateComponents(day: offset)).capitalized(with: locale)
    }

    static func date(
        _ date: Date,
        relativeTo reference: Date = .now,
        month: Date.FormatStyle.Symbol.Month = .abbreviated,
        locale: Locale = .autoupdatingCurrent,
        calendar: Calendar = .autoupdatingCurrent
    ) -> String {
        var style = Date.FormatStyle.dateTime
            .locale(locale)
            .month(month)
            .day()
        style.timeZone = calendar.timeZone
        if !calendar.isDate(date, equalTo: reference, toGranularity: .year) {
            style = style.year()
        }
        return date.formatted(style)
    }

    static func weekdayDate(
        _ date: Date,
        relativeTo reference: Date = .now,
        locale: Locale = .autoupdatingCurrent,
        calendar: Calendar = .autoupdatingCurrent
    ) -> String {
        var style = Date.FormatStyle.dateTime
            .locale(locale)
            .weekday(.abbreviated)
            .month(.abbreviated)
            .day()
        style.timeZone = calendar.timeZone
        if !calendar.isDate(date, equalTo: reference, toGranularity: .year) {
            style = style.year()
        }
        return date.formatted(style)
    }

    static func relativeDate(
        _ date: Date,
        relativeTo reference: Date = .now,
        locale: Locale = .autoupdatingCurrent,
        calendar: Calendar = .autoupdatingCurrent
    ) -> String {
        relativeDayName(for: date, relativeTo: reference, locale: locale, calendar: calendar)
            ?? weekdayDate(date, relativeTo: reference, locale: locale, calendar: calendar)
    }

    static func dateTime(
        _ date: Date,
        relativeTo reference: Date = .now,
        usesRelativeDay: Bool = true,
        locale: Locale = .autoupdatingCurrent,
        calendar: Calendar = .autoupdatingCurrent
    ) -> String {
        let day = usesRelativeDay
            ? relativeDate(date, relativeTo: reference, locale: locale, calendar: calendar)
            : self.date(date, relativeTo: reference, locale: locale, calendar: calendar)
        var timeStyle = Date.FormatStyle.dateTime.locale(locale).hour().minute()
        timeStyle.timeZone = calendar.timeZone
        let time = date.formatted(timeStyle)
        return "\(day) · \(time)"
    }

    static func monthHeading(
        _ date: Date,
        locale: Locale = .autoupdatingCurrent,
        calendar: Calendar = .autoupdatingCurrent
    ) -> String {
        var style = Date.FormatStyle.dateTime
            .locale(locale)
            .month(.abbreviated)
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        let month = date.formatted(style)
        let year = calendar.component(.year, from: date)
            .formatted(.number.locale(locale).grouping(.never))
        return "\(month) \(year)"
    }
}
