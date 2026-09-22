import SwiftUI
import UIKit

struct OrgPreviewMathFlow: View {
    let fragments: [OrgPreviewInlineFragment]
    var textStyle: UIFont.TextStyle = .body
    var centered = false

    var body: some View {
        VStack(alignment: centered ? .center : .leading, spacing: 4) {
            ForEach(Array(OrgPreviewContainerMath.segments(fragments).enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .inline(let fragments):
                    OrgPreviewRichText(fragments: fragments, textStyle: textStyle)
                        .fixedSize(horizontal: false, vertical: true)
                case .display(let expression):
                    OrgPreviewMathBlock(expression: expression)
                }
            }
        }
    }
}
