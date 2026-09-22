import Foundation

enum OrgPreviewInlineFragment {
    case text(AttributedString)
    case math(OrgMathExpression)
    case image(OrgPreviewImageReference)
}
