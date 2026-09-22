import SwiftUI
import UIKit
import UniformTypeIdentifiers

extension UTType {
    static let orgendaHeading = UTType(exportedAs: "com.roifewu.orgenda.heading")
}

struct OrgHeadingDrag {
    let token: String
    let headingID: String
    let document: ParsedOrgDocument
}

struct OrgHeadingDrop: Equatable {
    let headingID: String
    let placement: OrgHeadingPlacement
}

struct OrgHeadingTitleBounds: PreferenceKey {
    static var defaultValue: CGRect? { nil }
    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        value = nextValue() ?? value
    }
}

enum OrgHeadingDropZone {
    static func placement(at y: CGFloat, titleBounds: CGRect) -> OrgHeadingPlacement {
        if y < titleBounds.minY + titleBounds.height * 0.25 { return .before }
        if y > titleBounds.maxY - titleBounds.height * 0.25 { return .after }
        return .child
    }

    static func accepts(headingID: String, targetID: String, parentHeadingIDs: [String]) -> Bool {
        headingID != targetID && !parentHeadingIDs.contains(headingID)
    }
}

/// UIKit supplies a session-end callback even when a drag is cancelled outside
/// the document, so the source and all its descendants always stop dimming.
struct OrgHeadingDragSource: UIViewRepresentable {
    let title: String
    let onBegin: () -> String?
    let onEnd: () -> Void
    var onTap: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        let interaction = UIDragInteraction(delegate: context.coordinator)
        interaction.isEnabled = true
        view.addInteraction(interaction)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped))
        tap.isEnabled = onTap != nil
        view.addGestureRecognizer(tap)
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.source = self
        view.gestureRecognizers?.first { $0 is UITapGestureRecognizer }?.isEnabled = onTap != nil
    }

    final class Coordinator: NSObject, UIDragInteractionDelegate {
        var source: OrgHeadingDragSource
        init(_ source: OrgHeadingDragSource) { self.source = source }

        @objc func tapped() { source.onTap?() }

        func dragInteraction(_ interaction: UIDragInteraction,
                             itemsForBeginning session: UIDragSession) -> [UIDragItem] {
            guard let token = source.onBegin() else { return [] }
            let provider = NSItemProvider(item: token as NSString, typeIdentifier: UTType.orgendaHeading.identifier)
            provider.suggestedName = token
            let item = UIDragItem(itemProvider: provider)
            let title = source.title
            let width = max(120, interaction.view?.bounds.width ?? 240)
            item.previewProvider = {
                let label = UILabel()
                label.text = title
                label.font = .preferredFont(forTextStyle: .headline)
                label.textColor = .label
                label.numberOfLines = 3
                let size = label.sizeThatFits(CGSize(width: width - 24, height: .greatestFiniteMagnitude))
                label.frame = CGRect(x: 12, y: 10, width: width - 24, height: size.height)
                let view = UIView(frame: CGRect(x: 0, y: 0, width: width, height: size.height + 20))
                view.backgroundColor = .secondarySystemBackground
                view.layer.cornerRadius = 8
                view.addSubview(label)
                return UIDragPreview(view: view)
            }
            return [item]
        }

        func dragInteraction(_ interaction: UIDragInteraction, sessionIsRestrictedToDraggingApplication session: UIDragSession) -> Bool {
            true
        }

        func dragInteraction(_ interaction: UIDragInteraction, session: UIDragSession,
                             didEndWith operation: UIDropOperation) {
            source.onEnd()
        }
    }
}

struct OrgHeadingDropModifier: ViewModifier {
    let headingID: String?
    let parentHeadingIDs: [String]
    let drag: OrgHeadingDrag?
    @Binding var target: OrgHeadingDrop?
    let onMove: (String, OrgHeadingPlacement) -> Bool
    @State private var height: CGFloat = 44
    @State private var titleBounds: CGRect?

    func body(content: Content) -> some View {
        if let headingID {
            content
                .contentShape(Rectangle())
                .coordinateSpace(name: headingID)
                .onPreferenceChange(OrgHeadingTitleBounds.self) { titleBounds = $0 }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
                .onDrop(of: [.orgendaHeading], delegate: HeadingDropDelegate(
                    headingID: headingID, parentHeadingIDs: parentHeadingIDs, drag: drag,
                    titleBounds: titleBounds ?? CGRect(x: 0, y: 0, width: 0, height: height),
                    target: $target, onMove: onMove
                ))
        } else {
            content
        }
    }
}

private struct HeadingDropDelegate: DropDelegate {
    let headingID: String
    let parentHeadingIDs: [String]
    let drag: OrgHeadingDrag?
    let titleBounds: CGRect
    @Binding var target: OrgHeadingDrop?
    let onMove: (String, OrgHeadingPlacement) -> Bool

    func validateDrop(info: DropInfo) -> Bool {
        guard let drag,
              OrgHeadingDropZone.accepts(headingID: drag.headingID, targetID: headingID,
                                         parentHeadingIDs: parentHeadingIDs) else { return false }
        return info.itemProviders(for: [.orgendaHeading]).contains { $0.suggestedName == drag.token }
    }

    func dropEntered(info: DropInfo) { updateTarget(info) }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard validateDrop(info: info) else { return DropProposal(operation: .forbidden) }
        updateTarget(info)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        if target?.headingID == headingID { target = nil }
    }

    func performDrop(info: DropInfo) -> Bool {
        guard validateDrop(info: info) else { return false }
        let placement = OrgHeadingDropZone.placement(at: info.location.y, titleBounds: titleBounds)
        target = nil
        return onMove(headingID, placement)
    }

    private func updateTarget(_ info: DropInfo) {
        guard validateDrop(info: info) else { return }
        target = OrgHeadingDrop(headingID: headingID,
                                      placement: OrgHeadingDropZone.placement(
                                        at: info.location.y, titleBounds: titleBounds))
    }
}
