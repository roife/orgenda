import SwiftUI

extension View {
    func searchListSurface() -> some View {
        listStyle(.plain)
            .contentMargins(.horizontal, 0, for: .scrollContent)
            .listSectionSpacing(OrgendaSpacing.rowInset)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .scrollDismissesKeyboard(.interactively)
            .scrollEdgeEffectStyle(.soft, for: [.top, .bottom])
    }
}
