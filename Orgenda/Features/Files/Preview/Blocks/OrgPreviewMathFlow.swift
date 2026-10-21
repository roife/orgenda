import SwiftUI
import UIKit

struct OrgPreviewMathFlow: View {
    let nodes: [ParsedOrgNode]
    var textStyle: UIFont.TextStyle = .body
    var centered = false
    var preservesLineBreaks = false

    var body: some View {
        let blocks = preservesLineBreaks ? nodes : OrgPreviewParagraphs.group(nodes)
        VStack(alignment: centered ? .center : .leading, spacing: preservesLineBreaks ? 4 : 12) {
            ForEach(blocks) { node in
                if node.type == "latex_block" {
                    OrgPreviewMathBlock(expression: OrgMathExpression(node))
                } else if node.type != "blank_line" {
                    OrgPreviewRichText(fragments: OrgPreviewMarkup.fragments(node), textStyle: textStyle)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
