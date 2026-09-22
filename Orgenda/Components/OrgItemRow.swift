import SwiftUI
import UIKit

struct OrgItemRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var completionFeedback = 0
    @State private var swipeOffset: CGFloat = 0
    @State private var swipeStart: CGFloat = 0

    let item: OrgItem
    let onToggle: () -> Void
    let onOpen: () -> Void
    var onReschedule: (() -> Void)? = nil
    var onShowInFile: (() -> Void)? = nil
    var dragItem: OrgItem? = nil
    var topPadding: CGFloat = 9
    var bottomPadding: CGFloat = 9
    var tagSpacing: CGFloat = 6
    var allowsSwipeActions = true
    @Binding var revealedItemID: UUID?

    var body: some View {
        ZStack {
            swipeActions
            draggableContent
                .background(Color(uiColor: .systemBackground))
                .offset(x: swipeOffset)
                .gesture(OrgendaHorizontalPan(onChange: { translation, began in
                    if began {
                        swipeStart = swipeOffset
                        revealedItemID = item.id
                    }
                    swipeOffset = min(max(swipeStart + translation, -trailingRevealWidth), item.canComplete ? 130 : 0)
                }, onEnd: { translation, velocity, cancelled in
                    let total = swipeStart + translation
                    let completes = !cancelled && item.canComplete && total > 96 && velocity > -100
                    withAnimation(OrgendaMotion.geometryAnimation(.selection, reduceMotion: reduceMotion)) {
                        if !cancelled && !completes && total < -45 {
                            swipeOffset = -trailingRevealWidth
                        } else if !cancelled && !completes && item.canComplete && total > 45 {
                            swipeOffset = 72
                        } else {
                            swipeOffset = 0
                        }
                    }
                    if completes { performToggle() }
                    if swipeOffset == 0 { revealedItemID = nil }
                }, isEnabled: allowsSwipeActions))
        }
        .clipped()
        .onChange(of: revealedItemID) { _, selected in
            if selected != item.id {
                withAnimation(OrgendaMotion.geometryAnimation(.selection, reduceMotion: reduceMotion)) { swipeOffset = 0 }
            }
        }
        .accessibilityActions {
            if canSchedule {
                Button("Reschedule") { closeActions(); onReschedule?() }
            }
            if let onShowInFile {
                Button("Show in File", action: onShowInFile)
            }
        }
    }

    @ViewBuilder
    private var contextActions: some View {
        if item.canComplete {
            let target: OrgWorkflowState = item.state.isTerminal ? .todo : .done
            Button(action: performToggle) {
                Label(completionLabel, systemImage: target.symbol)
            }
            .accessibilityLabel(completionLabel)
        }
        if canSchedule {
            Button("Reschedule…", systemImage: "calendar") { closeActions(); onReschedule?() }
        }
        Button("Edit", systemImage: "pencil", action: onOpen)
        if let onShowInFile {
            Button("Show in File", systemImage: "doc.text.magnifyingglass") {
                closeActions()
                onShowInFile()
            }
            .accessibilityIdentifier("agenda.item.showInFile")
        }
    }

    private var canSchedule: Bool { item.hasWorkflowState && item.kind != .event && onReschedule != nil }
    private let actionDiameter: CGFloat = 48
    private let actionSpacing: CGFloat = 12
    private var trailingRevealWidth: CGFloat {
        (canSchedule ? actionDiameter * 2 + actionSpacing : actionDiameter) + 24
    }

    @ViewBuilder
    private var draggableContent: some View {
        if canSchedule {
            rowContent.draggable(OrgTaskTransfer(item: dragItem ?? item)) {
                Label(item.title, systemImage: "calendar.badge.clock")
                    .foregroundStyle(item.workflowTitleColor)
                    .font(.body).padding(14).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
            .contextMenu { contextActions }
        } else {
            rowContent.contextMenu { contextActions }
        }
    }

    private var swipeActions: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 0) {
                if swipeOffset > 0 {
                    Button { closeActions(); performToggle() } label: {
                        Image(systemName: item.state.isTerminal ? "arrow.uturn.backward" : "checkmark")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: actionDiameter, height: actionDiameter)
                            .glassEffect(.regular.tint(.green).interactive(), in: .circle)
                            .contentShape(Circle())
                    }
                    .accessibilityLabel(item.state.isTerminal ? "Reopen" : "Done")
                    .accessibilityIdentifier("agenda.swipe.complete")
                    .modifier(SwipeActionReveal(progress: min(swipeOffset / 72, 1), reduceMotion: reduceMotion))
                    .padding(.leading, 12)
                    Spacer(minLength: 0)
                } else if swipeOffset < 0 {
                    Spacer(minLength: 0)
                    HStack(spacing: actionSpacing) {
                        if canSchedule {
                            Button { closeActions(); onReschedule?() } label: {
                                Image(systemName: "calendar")
                                    .font(.system(size: 20, weight: .medium))
                                    .foregroundStyle(.white)
                                    .frame(width: actionDiameter, height: actionDiameter)
                                    .glassEffect(.regular.tint(OrgendaTheme.accent).interactive(), in: .circle)
                                    .contentShape(Circle())
                            }
                            .accessibilityLabel("Reschedule")
                            .accessibilityIdentifier("agenda.swipe.reschedule")
                        }
                        Button { closeActions(); onOpen() } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(.primary)
                                .frame(width: actionDiameter, height: actionDiameter)
                                .glassEffect(.regular.interactive(), in: .circle)
                                .contentShape(Circle())
                        }
                        .accessibilityLabel("Edit")
                        .accessibilityIdentifier("agenda.swipe.more")
                    }
                    .modifier(SwipeActionReveal(progress: min(-swipeOffset / trailingRevealWidth, 1), reduceMotion: reduceMotion))
                    .padding(.horizontal, 12)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityHidden(swipeOffset == 0)
    }

    private func closeActions() {
        revealedItemID = nil
        withAnimation(OrgendaMotion.geometryAnimation(.selection, reduceMotion: reduceMotion)) { swipeOffset = 0 }
    }

    private var rowContent: some View {
        HStack(alignment: .top, spacing: 2) {
            if !item.canComplete {
                statusIcon
                    .offset(y: topPadding - 9)
                    .frame(width: 44, height: 44)
                    .accessibilityHidden(true)
            } else {
                Button(action: performToggle) {
                    statusIcon
                        .offset(y: topPadding - 9)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(completionLabel)
                .accessibilityValue(item.hasWorkflowState ? "\(item.title), \(item.state.title)" : item.title)
                .accessibilityHint(completesOccurrence ? "Record completion and schedule the next occurrence" : "")
                .accessibilityIdentifier("agenda.item.complete.\(item.id)")
                .sensoryFeedback(.success, trigger: completionFeedback)
            }

            Button {
                if swipeOffset != 0 { closeActions() } else { onOpen() }
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        if item.priority != .none {
                            Text(item.priority.rawValue)
                                .font(.footnote.weight(.bold))
                                .foregroundStyle(priorityColor)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(priorityColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 4))
                                .accessibilityLabel("Priority \(item.priority.rawValue)")
                        }
                        Text(item.title)
                            .font(.body.weight(item.kind == .event ? .regular : .medium))
                            .foregroundStyle(item.workflowTitleColor)
                            .strikethrough(item.hasWorkflowState && item.state.isTerminal, color: item.workflowTitleColor)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }

                    VStack(alignment: .leading, spacing: tagSpacing) {
                        metadata
                        if !item.tags.isEmpty {
                            OrgendaTagList(tags: item.tags)
                        }
                    }
                    if item.kind == .habit {
                        habitHistory
                    }
                }
                .padding(.top, topPadding)
                .padding(.bottom, bottomPadding)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Edit item")
            .accessibilityIdentifier("agenda.item.open.\(item.id)")
        }
        .padding(.leading, -8)
    }

    private var metadata: some View {
        OrgendaFlowLayout(horizontalSpacing: 8) {
            if item.hasTime, let date = item.agendaDate {
                Text(date.formatted(date: .omitted, time: .shortened))
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(item.isOverdue ? OrgendaTheme.overdue : .secondary)
            }
            Text(displaySourcePath)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var displaySourcePath: String {
        var path = item.source.file
        if path.hasPrefix("agenda/") {
            path.removeFirst("agenda/".count)
        }
        if path.hasSuffix(".org") {
            path.removeLast(".org".count)
        }
        return path.split(separator: "/").joined(separator: " ▸ ")
    }

    private var habitHistory: some View {
        HStack(spacing: 2) {
            ForEach(0..<7, id: \.self) { offset in
                let date = Date.now.adding(days: -offset)
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(item.habitHistory.contains(where: { Calendar.autoupdatingCurrent.isDate($0, inSameDayAs: date) }) ? OrgendaTheme.habit : Color.secondary.opacity(0.18))
                    .frame(width: 5, height: 10)
            }
        }
        .accessibilityLabel("Habit history for the past seven days")
    }

    @ViewBuilder
    private var statusIcon: some View {
        let icon = Group {
            if item.hasWorkflowState {
                OrgWorkflowIcon(item.state)
            } else {
                Image(systemName: completesOccurrence ? "checkmark.circle" : item.kind.systemImage)
                    .foregroundStyle(OrgendaTheme.kindColor(item.kind))
            }
        }
            .font(.system(size: 21, weight: .medium))
            .frame(width: 20, height: 24)

        if reduceMotion {
            icon.contentTransition(.opacity)
        } else {
            icon
                .contentTransition(.symbolEffect(.replace))
        }
    }

    private func performToggle() {
        if !item.state.isTerminal {
            completionFeedback += 1
        }
        onToggle()
    }

    private var completesOccurrence: Bool {
        (item.kind == .habit || item.isRepeatingEvent) && item.recurrence != nil && !item.state.isTerminal
    }

    private var completionLabel: String {
        if completesOccurrence { return String(localized: "Complete this occurrence") }
        return item.state.isTerminal ? String(localized: "Mark incomplete") : String(localized: "Mark complete")
    }

    private var priorityColor: Color {
        switch item.priority {
        case .high: .red
        case .medium: .orange
        case .low: .blue
        case .none: .secondary
        }
    }
}

private struct SwipeActionReveal: ViewModifier {
    let progress: CGFloat
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .opacity(progress)
            .scaleEffect(reduceMotion ? 1 : 0.86 + 0.14 * progress)
    }
}
