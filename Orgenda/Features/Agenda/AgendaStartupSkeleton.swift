import SwiftUI

struct AgendaStartupSkeleton: View {
    let date: Date
    let showsCalendar: Bool
    @ScaledMetric(relativeTo: .body) private var titleHeight = 16.0
    @ScaledMetric(relativeTo: .footnote) private var detailHeight = 11.0

    var body: some View {
        VStack(spacing: 0) {
            if showsCalendar {
                OrgendaCalendar(
                    selectedDate: .constant(date),
                    density: .constant(.week),
                    markedDates: [],
                    controlsInHeader: true,
                    onCapture: {}
                )
            }
            ScrollView {
                VStack(alignment: .leading, spacing: showsCalendar ? 12 : 20) {
                    ForEach(0..<3) { section in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                placeholder(width: section == 0 ? 148 : 112, height: titleHeight)
                                Spacer(minLength: 16)
                                placeholder(width: 18, height: detailHeight)
                            }
                            .padding(.vertical, 8)
                            ForEach(0..<(section == 0 ? 3 : 2), id: \.self) { row in
                                HStack(alignment: .top, spacing: 2) {
                                    Circle()
                                        .strokeBorder(Color(uiColor: .tertiaryLabel), lineWidth: 2)
                                        .frame(width: 21, height: 21)
                                        .frame(width: 44, height: 44)
                                    VStack(alignment: .leading, spacing: 8) {
                                        placeholder(width: row.isMultiple(of: 2) ? 252 : 192, height: titleHeight)
                                        placeholder(width: row.isMultiple(of: 2) ? 120 : 88, height: detailHeight)
                                    }
                                    .padding(.vertical, 9)
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                }
                                .padding(.leading, -8)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, showsCalendar ? 0 : 12)
                .padding(.bottom, 24)
            }
            .scrollDisabled(true)
            .scrollIndicators(.hidden)
        }
        .disabled(true)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading workspace")
        .accessibilityValue(showsCalendar ? "Calendar" : "Dashboard")
        .accessibilityIdentifier("workspace.loading")
    }

    private func placeholder(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color(uiColor: .quaternaryLabel))
            .frame(maxWidth: width)
            .frame(height: height)
    }
}
