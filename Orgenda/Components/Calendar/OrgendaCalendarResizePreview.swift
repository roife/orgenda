import SwiftUI

struct OrgendaCalendarResizePreview<Content: View>: View, Animatable {
    var position: CGFloat
    let content: (CGFloat) -> Content

    var animatableData: CGFloat {
        get { position }
        set { position = newValue }
    }

    var body: some View { content(position) }
}
