import SwiftUI

/// Motion primitives shared by orgenda's SwiftUI views.
///
/// The springs intentionally use very little extra bounce: movement should make
/// state changes easier to follow without becoming the focus of the interface.
enum OrgendaMotion {
    enum Token: Sendable {
        /// Fast feedback for a direct selection, such as changing tabs.
        case selection
        /// A calmer animation for presenting or rearranging content.
        case content
    }

    /// Resolves a semantic token while honoring Reduce Motion.
    static func animation(
        _ token: Token,
        reduceMotion: Bool
    ) -> Animation {
        guard !reduceMotion else { return .easeOut(duration: 0.16) }

        switch token {
        case .selection:
            return .snappy(duration: 0.22, extraBounce: 0.03)
        case .content:
            return .smooth(duration: 0.28)
        }
    }

    /// Use for layout, position, and scale changes. Reduce Motion makes the
    /// geometry change immediately; callers may animate opacity separately.
    static func geometryAnimation(
        _ token: Token,
        reduceMotion: Bool
    ) -> Animation? {
        reduceMotion ? nil : animation(token, reduceMotion: false)
    }

    /// A compact content transition. Displacement is capped so views never fly
    /// across the screen; Reduce Motion uses opacity alone.
    static func transition(
        from edge: Edge = .trailing,
        distance: CGFloat = 14,
        reduceMotion: Bool
    ) -> AnyTransition {
        guard !reduceMotion else { return .opacity }

        let offset: CGSize

        switch edge {
        case .top:
            offset = CGSize(width: 0, height: -distance)
        case .leading:
            offset = CGSize(width: -distance, height: 0)
        case .bottom:
            offset = CGSize(width: 0, height: distance)
        case .trailing:
            offset = CGSize(width: distance, height: 0)
        }

        return .opacity.combined(
            with: .offset(x: offset.width, y: offset.height)
        )
    }

}
