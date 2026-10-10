import SwiftUI
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

/// A session token ties the transfer to the validated source snapshot.
private struct OrgHeadingTransfer: Codable, Transferable, Identifiable {
    let id: String
    let token: String
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .orgendaHeading)
    }
}

struct OrgHeadingDragSource: ViewModifier {
    let headingID: String
    @Namespace private var namespace
    @State private var transfer: OrgHeadingTransfer?
    let onBegin: () -> String?
    let onEnd: () -> Void
    var isEnabled = true

    func body(content: Content) -> some View {
        if isEnabled {
            content
                .draggable(containerItemID: headingID, containerNamespace: namespace)
                .dragContainer(for: OrgHeadingTransfer.self, in: namespace) { (id: String) -> [OrgHeadingTransfer] in
                    // SwiftUI may request a payload more than once during a lift.
                    // Keep one validated source snapshot for the entire session.
                    if let transfer { return [transfer] }
                    guard let token = onBegin() else { return [] }
                    let payload = OrgHeadingTransfer(id: id, token: token)
                    transfer = payload
                    return [payload]
                }
                .dragConfiguration(DragConfiguration(
                    operationsWithinApp: .init(allowMove: true),
                    operationsOutsideApp: .init(allowCopy: false)
                ))
                .onDragSessionUpdated { session in
                    switch session.phase {
                    case .ended(let operation) where operation != .move:
                        transfer = nil
                        onEnd()
                    case .dataTransferCompleted:
                        // Typed payload delivery can finish after the gesture ends.
                        transfer = nil
                        onEnd()
                    default:
                        break
                    }
                }
        } else {
            content
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
                .dropDestination(for: OrgHeadingTransfer.self) { items, session in
                    guard accepts(session, headingID: headingID),
                          items.count == 1, items.first?.token == drag?.token else { return }
                    target = nil
                    _ = onMove(headingID, placement(at: session.location.y))
                }
                .dropConfiguration { session in
                    DropConfiguration(operation: accepts(session, headingID: headingID) ? .move : .forbidden)
                }
                .onDropSessionUpdated { session in
                    switch session.phase {
                    case .entering, .active:
                        if accepts(session, headingID: headingID) {
                            target = OrgHeadingDrop(headingID: headingID, placement: placement(at: session.location.y))
                        }
                    default:
                        if target?.headingID == headingID { target = nil }
                    }
                }
        } else {
            content
        }
    }

    private func accepts(_ session: DropSession, headingID: String) -> Bool {
        guard let drag, session.itemsCount == 1,
              session.localSession?.draggedItemIDs(for: String.self).contains(drag.headingID) == true else { return false }
        return OrgHeadingDropZone.accepts(headingID: drag.headingID, targetID: headingID,
                                          parentHeadingIDs: parentHeadingIDs)
    }

    private func placement(at y: CGFloat) -> OrgHeadingPlacement {
        OrgHeadingDropZone.placement(at: y, titleBounds: titleBounds ?? CGRect(x: 0, y: 0, width: 0, height: height))
    }
}
