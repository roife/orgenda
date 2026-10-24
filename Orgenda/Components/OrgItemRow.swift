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
    var topPadding: CGFloat = OrgendaSpacing.contentInset
    var bottomPadding: CGFloat = OrgendaSpacing.contentInset
    var tagSpacing: CGFloat = OrgendaSpacing.inlineGap
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
        // An empty swipeActions modifier still intercepts calendar page drags.
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
                    Button(action: onToggle) {
                        Label(completionLabel, systemImage: item.state.isTerminal ? "arrow.uturn.backward" : "checkmark")
                    }
                    .labelStyle(.iconOnly)
                    .tint(OrgendaTheme.success)
                    .accessibilityIdentifier("agenda.swipe.complete")
                }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button("Edit", systemImage: "pencil", action: onOpen)
                    .labelStyle(.iconOnly)
                    .tint(.secondary)
                    .accessibilityIdentifier("agenda.swipe.more")
                if canSchedule {
                    Button("Reschedule", systemImage: "calendar") { onReschedule?() }
                        .labelStyle(.iconOnly)
                        .tint(OrgendaTheme.accent)
                        .accessibilityIdentifier("agenda.swipe.reschedule")
                }
            }
    }

    @ViewBuilder
    private var contextActions: some View {
        if item.canComplete {
            Button(action: onToggle) {
                Label(completionLabel, systemImage: item.state.isTerminal ? "circle" : "checkmark.circle")
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
        HStack(alignment: .top, spacing: OrgendaSpacing.textGap) {
            if canSchedule {
                completionControl.draggable(OrgTaskTransfer(item: dragItem ?? item))
            } else {
                completionControl
            }

            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: OrgendaSpacing.compactInset) {
                    HStack(alignment: .firstTextBaseline, spacing: OrgendaSpacing.inlineGap) {
                        if item.priority != .none {
                            Text(item.priority.rawValue)
                                .font(.footnote.weight(.bold))
                                .foregroundStyle(priorityColor)
                                .padding(OrgendaSpacing.badgeInsets)
                                .background(OrgendaTheme.tintedBackground(priorityColor), in: OrgendaCorners.standard)
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
        .padding(.leading, -OrgendaSpacing.rowInset)
        .padding(.vertical, 1)
    }

    @ViewBuilder
    private var completionControl: some View {
        if !item.canComplete {
            statusIcon
                .offset(y: topPadding - 9)
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)
        } else {
            Button(action: onToggle) {
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
        OrgendaFlowLayout(horizontalSpacing: OrgendaSpacing.rowInset) {
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
        if path.hasSuffix(".org") {
            path.removeLast(".org".count)
        }
        return (path.split(separator: "/").map(String.init) + item.source.ancestorTitles).joined(separator: " ▸ ")
    }

    private var habitHistory: some View {
        HStack(spacing: OrgendaSpacing.textGap) {
            ForEach(0..<7, id: \.self) { offset in
                let date = Date.now.adding(days: -offset)
                OrgendaCorners.indicator
                    .fill(item.habitHistory.contains(where: { Calendar.autoupdatingCurrent.isDate($0, inSameDayAs: date) }) ? OrgendaTheme.habit : OrgendaTheme.habitPlaceholder)
                    .frame(width: 5, height: 10)
            }
        }
        .accessibilityLabel("Habit history for the past seven days")
    }

    private var statusIcon: some View {
        Group {
            if item.hasWorkflowState {
                OrgWorkflowIcon(item.state)
            } else {
                Image(systemName: completesOccurrence ? "checkmark.circle" : item.kind.systemImage)
                    .foregroundStyle(OrgendaTheme.kindColor(item.kind))
            }
        }
            .font(.system(size: 21, weight: .medium))
            .frame(width: 20, height: 24)
            .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace))
    }

    private var completesOccurrence: Bool {
        (item.kind == .habit || item.isRepeatingEvent) && item.recurrence != nil && !item.state.isTerminal
    }

    private var completionLabel: String {
        if completesOccurrence { return String(localized: "Complete this occurrence") }
        return item.state.isTerminal ? String(localized: "Mark incomplete") : String(localized: "Mark complete")
    }

    private var priorityColor: Color {
        OrgendaTheme.priorityColor(item.priority)
    }
}
