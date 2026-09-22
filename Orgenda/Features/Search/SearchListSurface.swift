import SwiftUI

extension View {
    func searchListSurface() -> some View {
        listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .scrollDismissesKeyboard(.interactively)
            .scrollEdgeEffectStyle(.soft, for: [.top, .bottom])
    }
}
