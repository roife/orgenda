import SwiftUI

enum JournalMotion {
    // Ease into the next day, then settle gently without the selection spring's snap.
    static let dateChange = Animation.timingCurve(0.32, 0, 0.18, 1, duration: 0.38)
    static let contentChange = Animation.easeInOut(duration: 0.24)
}

struct JournalView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let store: WorkspaceStore
    @Binding var selectedDate: Date
    let onCapture: () -> Void
    @State private var capture: JournalCapture?
    @State private var dayDrag: CGFloat = 0

    var body: some View {
        let entries = store.journal(on: selectedDate)
        // Day changes also reset the reading position to the top of that day.
        let contentID = entries.isEmpty ? "empty" : selectedDate.orgendaDayKey

        NavigationStack {
            VStack(spacing: 0) {
                journalHeader

                ScrollView {
                    ZStack(alignment: .topLeading) {
                        JournalDayContent(entries: entries) {
                            capture = JournalCapture(date: selectedDate)
                        }
                        .id(contentID)
                        .transition(.opacity)
                    }
                    .frame(maxWidth: .infinity, minHeight: 280, alignment: .topLeading)
                    .padding(16)
                    .padding(.bottom, 24)
                    .animation(reduceMotion ? .easeOut(duration: 0.12) : JournalMotion.contentChange, value: contentID)
                    .offset(x: reduceMotion ? 0 : dayDrag)
                }
                .id(selectedDate.orgendaDayKey)
                .scrollIndicators(.hidden)
                .scrollEdgeEffectStyle(.soft, for: [.top, .bottom])
                .contentShape(Rectangle())
                .gesture(OrgendaHorizontalPan(onChange: { translation, _ in
                    dayDrag = min(max(translation * 0.25, -50), 50)
                }, onEnd: { translation, velocity, cancelled in
                    withAnimation(reduceMotion ? nil : JournalMotion.dateChange) { dayDrag = 0 }
                    guard !cancelled, abs(translation) > 60 || (abs(translation) > 20 && abs(velocity) > 600) else { return }
                    selectedDate = selectedDate.adding(days: translation < 0 ? 1 : -1)
                }))
                .accessibilityIdentifier("journal.day.content")
                .accessibilityAction(named: "Previous day") { selectedDate = selectedDate.adding(days: -1) }
                .accessibilityAction(named: "Next day") { selectedDate = selectedDate.adding(days: 1) }
            }
            .background(Color(uiColor: .systemBackground))
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $capture) { capture in
                JournalComposer(store: store, date: capture.date)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    private var journalHeader: some View {
        VStack(spacing: 8) {
            let headerLayout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
            headerLayout {
                OrgendaDateHeading(date: selectedDate)
                    .animation(reduceMotion ? .easeOut(duration: 0.12) : JournalMotion.dateChange, value: selectedDate)
                    .accessibilityIdentifier("journal.date.heading")
                headerActions
            }

            JournalDateStrip(selectedDate: $selectedDate)
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 12)
    }

    private var headerActions: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                let isToday = Calendar.autoupdatingCurrent.isDateInToday(selectedDate)
                if !isToday {
                    Button { selectedDate = Date.now.startOfDay } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 18, weight: .medium))
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .foregroundStyle(OrgendaTheme.accentText)
                    .accessibilityLabel("Go to today's journal")
                }

                Button(action: onCapture) {
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .regular))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .foregroundStyle(OrgendaTheme.accentText)
                .accessibilityLabel("New journal entry")
                .accessibilityIdentifier("orgenda.capture")
            }
            .fixedSize()
        }
        .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil, alignment: .trailing)
    }
}

private struct JournalCapture: Identifiable {
    let date: Date
    var id: Date { date }
}
