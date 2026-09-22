import SwiftUI

struct OrgPreviewMathBlock: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let expression: OrgMathExpression

    var body: some View {
        ScrollView(.horizontal) {
            if let rendered = OrgMathRendering.render(
                expression,
                textStyle: .body,
                dynamicTypeSize: dynamicTypeSize,
                colorScheme: colorScheme
            ) {
                Image(uiImage: rendered.image)
                    .accessibilityLabel(expression.original)
            } else {
                Text(expression.original)
                    .font(.body.monospaced())
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .textSelection(.enabled)
    }
}
