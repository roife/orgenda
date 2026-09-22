import SwiftUI
import UIKit

enum OrgPreviewFontMetrics {
    static func pointSize(for style: UIFont.TextStyle, dynamicTypeSize: DynamicTypeSize) -> CGFloat {
        let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(dynamicTypeSize))
        return UIFont.preferredFont(forTextStyle: style, compatibleWith: traits).pointSize
    }
}
