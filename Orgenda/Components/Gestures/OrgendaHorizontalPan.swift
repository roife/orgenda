import SwiftUI
import UIKit

/// Decide the axis before recognition so vertical scrolling, long presses and
/// the system's leading-edge navigation gesture keep their normal priority.
struct OrgendaHorizontalPan: UIGestureRecognizerRepresentable {
    let onChange: (CGFloat, Bool) -> Void
    let onEnd: (CGFloat, CGFloat, Bool) -> Void

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.maximumNumberOfTouches = 1
        pan.delegate = context.coordinator
        return pan
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator(converter: converter)
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        let x = context.converter.localTranslation?.x ?? 0
        let velocity = context.converter.localVelocity?.x ?? 0
        switch recognizer.state {
        case .began, .changed: onChange(x, recognizer.state == .began)
        case .ended: onEnd(x, velocity, false)
        case .cancelled, .failed: onEnd(x, velocity, true)
        default: break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let converter: CoordinateSpaceConverter
        init(converter: CoordinateSpaceConverter) { self.converter = converter }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let velocity = converter.localVelocity, let translation = converter.localTranslation else { return false }
            let startX = converter.location(in: .global).x - translation.x
            return startX > 24 && abs(velocity.x) > abs(velocity.y) * 1.4
        }
    }
}
