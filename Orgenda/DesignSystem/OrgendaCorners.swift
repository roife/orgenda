import SwiftUI

/// Shared geometry for custom surfaces; native controls keep their system shapes.
enum OrgendaCorners {
    static let radius: CGFloat = 8
    /// Small habit marks need tighter corners to preserve their grid shape.
    static let indicatorRadius: CGFloat = 2
    /// Floating glass surfaces use the same curvature in SwiftUI and UIKit.
    static let glassRadius: CGFloat = 24

    static let standard = RoundedRectangle(cornerRadius: radius, style: .continuous)
    static let indicator = RoundedRectangle(cornerRadius: indicatorRadius, style: .continuous)
    static let glass = RoundedRectangle(cornerRadius: glassRadius, style: .continuous)
}
