import SwiftUI
import UIKit

struct OrgPreviewRichText: View {
    let fragments: [OrgPreviewInlineFragment]
    var textStyle: UIFont.TextStyle = .body

    var body: some View {
        if fragments.contains(where: { if case .image = $0 { return true }; return false }) {
            OrgPreviewImageFlow(fragments: fragments, textStyle: textStyle)
        } else {
            OrgPreviewInlineText(fragments: fragments, textStyle: textStyle)
        }
    }
}

struct OrgPreviewInlineText: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let fragments: [OrgPreviewInlineFragment]
    var textStyle: UIFont.TextStyle = .body

    var body: some View {
        fragments.reduce(Text("")) { result, fragment in
            switch fragment {
            case .text(let value):
                return Text("\(result)\(Text(value))")
            case .image(let reference):
                return Text("\(result)\(Text(reference.label))")
            case .math(let expression):
                guard let rendered = OrgMathRendering.render(
                    expression,
                    textStyle: textStyle,
                    dynamicTypeSize: dynamicTypeSize,
                    colorScheme: colorScheme
                ) else {
                    return Text("\(result)\(Text(expression.original))")
                }
                let image = Text(Image(uiImage: rendered.image)).baselineOffset(-rendered.descent)
                return Text("\(result)\(image)")
            }
        }
    }
}
