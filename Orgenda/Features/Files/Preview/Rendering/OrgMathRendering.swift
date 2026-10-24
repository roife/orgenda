import SwiftUI
import RaTeX
import UIKit

final class OrgMathCacheEntry: NSObject {
    let image: UIImage
    let descent: CGFloat

    init(image: UIImage, descent: CGFloat) {
        self.image = image
        self.descent = descent
    }
}

@MainActor
enum OrgMathRendering {
    private static let cache: NSCache<NSString, OrgMathCacheEntry> = {
        let cache = NSCache<NSString, OrgMathCacheEntry>()
        cache.countLimit = 256
        cache.totalCostLimit = 32 * 1_024 * 1_024
        return cache
    }()

    static func render(
        _ expression: OrgMathExpression,
        textStyle: UIFont.TextStyle,
        dynamicTypeSize: DynamicTypeSize,
        colorScheme: ColorScheme
    ) -> OrgMathCacheEntry? {
        let fontSize = OrgPreviewFontMetrics.pointSize(for: textStyle, dynamicTypeSize: dynamicTypeSize)
        let scale = UIScreen.main.scale
        let latex = expression.latex
        let key = "\(expression.mode.rawValue)\u{0}\(colorScheme == .dark ? "dark" : "light")\u{0}\(fontSize)\u{0}\(scale)\u{0}\(latex)" as NSString
        if let cached = cache.object(forKey: key) { return cached }

        let traits = UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light)
        let label = OrgendaTheme.inkColor.resolvedColor(with: traits)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let components = label.cgColor.converted(to: space, intent: .defaultIntent, options: nil)?.components,
              components.count == 4 else { return nil }
        // Grayscale-to-RGB conversion can slightly overshoot 1. RaTeX rejects
        // out-of-range components, so pass explicit, clamped RGB values.
        let rgba = components.map { min(1, max(0, $0)) }
        let color = UIColor(red: rgba[0], green: rgba[1], blue: rgba[2], alpha: rgba[3])
        guard let displayList = try? RaTeXEngine.shared.parse(
            latex, displayMode: expression.mode == .display, color: color
        ) else { return nil }
        let renderer = RaTeXRenderer(
            displayList: displayList,
            fontSize: expression.mode == .display ? fontSize * 1.08 : fontSize
        )
        let size = CGSize(width: ceil(renderer.width), height: ceil(renderer.totalHeight))
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            renderer.draw(in: context.cgContext)
        }
        let entry = OrgMathCacheEntry(image: image, descent: renderer.depth)
        if let cgImage = image.cgImage {
            cache.setObject(entry, forKey: key, cost: cgImage.bytesPerRow * cgImage.height)
        }
        return entry
    }
}

enum OrgPreviewFontMetrics {
    static func pointSize(for style: UIFont.TextStyle, dynamicTypeSize: DynamicTypeSize) -> CGFloat {
        let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(dynamicTypeSize))
        return UIFont.preferredFont(forTextStyle: style, compatibleWith: traits).pointSize
    }
}
