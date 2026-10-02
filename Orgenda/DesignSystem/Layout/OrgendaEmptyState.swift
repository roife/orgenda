import SwiftUI

extension View {
    /// Center a page-level placeholder in its available content area, while
    /// keeping its text and actions reachable in short windows or large type.
    func orgendaEmptyState() -> some View {
        ScrollView {
            self
                .frame(maxWidth: .infinity)
        }
        .defaultScrollAnchor(.center, for: .alignment)
        .scrollBounceBehavior(.basedOnSize)
    }
}
