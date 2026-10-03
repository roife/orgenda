import SwiftUI
import UIKit

struct OrgItemRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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

    var body: some View {
        interactiveRow
            .accessibilityActions {
                if canSchedule {
                    Button("Reschedule") { onReschedule?() }
                }
                if let onShowInFile {
                    Button("Show in File", action: onShowInFile)
                }
            }
    }

    @ViewBuilder
    private var interactiveRow: some View {
        if allowsSwipeActions {
            swipeableRow
        } else {
            rowContent
        }
    }

    private var swipeableRow: some View {
        rowContent
            .swipeActions(edge: .leading) {
                if item.canComplete {
                    Button(action: performToggle) {
                        Label(completionLabel, systemImage: item.state.isTerminal ? "arrow.uturn.backward" : "checkmark")
                    }
                    .tint(.green)
                    .accessibilityIdentifier("agenda.swipe.complete")
                }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button("Edit", systemImage: "pencil", action: onOpen)
                    .tint(.secondary)
                    .accessibilityIdentifier("agenda.swipe.more")
                if canSchedule {
                    Button("Reschedule", systemImage: "calendar") { onReschedule?() }
                        .tint(OrgendaTheme.accent)
                        .accessibilityIdentifier("agenda.swipe.reschedule")
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
            Button("Reschedule…", systemImage: "calendar") { onReschedule?() }
        }
        Button("Edit", systemImage: "pencil", action: onOpen)
        if let onShowInFile {
            Button("Show in File", systemImage: "doc.text.magnifyingglass") {
                onShowInFile()
            }
            .accessibilityIdentifier("agenda.item.showInFile")
        }
    }

    private var canSchedule: Bool { item.hasWorkflowState && item.kind != .event && onReschedule != nil }

    private var rowContent: some View {
        HStack(alignment: .top, spacing: 2) {
            if canSchedule {
                completionControl.draggable(OrgTaskTransfer(item: dragItem ?? item))
            } else {
                completionControl
            }

            Button(action: onOpen) {
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
            .contextMenu { contextActions } preview: { OrgItemContextPreview(item: item) }
        }
        .padding(.leading, -8)
    }

    @ViewBuilder
    private var completionControl: some View {
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
        }
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
