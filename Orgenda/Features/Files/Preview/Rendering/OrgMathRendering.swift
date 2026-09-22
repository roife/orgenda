import SwiftUI
import SwiftMath
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
        let latex = compatibleLatex(expression.latex)
        let key = "\(expression.mode.rawValue)\u{0}\(colorScheme == .dark ? "dark" : "light")\u{0}\(fontSize)\u{0}\(scale)\u{0}\(latex)" as NSString
        if let cached = cache.object(forKey: key) { return cached }

        let traits = UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light)
        let color = UIColor.label.resolvedColor(with: traits)
        var renderer = MathImage(
            latex: latex,
            fontSize: expression.mode == .display ? fontSize * 1.08 : fontSize,
            textColor: color,
            labelMode: expression.mode == .display ? .display : .text,
            textAlignment: .center
        )
        let (_, image, layout) = renderer.asImage()
        guard let image, let layout else { return nil }
        let entry = OrgMathCacheEntry(image: image, descent: layout.descent)
        let cgImage = image.cgImage!
        cache.setObject(entry, forKey: key, cost: cgImage.bytesPerRow * cgImage.height)
        return entry
    }

    static func compatibleLatex(_ latex: String) -> String {
        _ = compatibilitySymbolsRegistered
        return OrgLatexCompatibility.normalizeLatex(latex)
    }

    private static let compatibilitySymbolsRegistered: Void = {
        // Register the actual Unicode glyph with the correct atom class, rather
        // than approximate double brackets, harpoons or definition relations.
        let symbols: [(String, String, MTMathAtomType)] = [
            ("llbracket", "⟦", .open), ("rrbracket", "⟧", .close),
            // Latin Modern lacks U+2A74; these two supported glyphs spell
            // the same double-colon equals relation without a missing-glyph box.
            ("Coloneqq", "∷=", .relation), ("coloneqq", "≔", .relation),
            ("rightharpoonup", "⇀", .relation), ("leftharpoonup", "↼", .relation),
            ("rightharpoondown", "⇁", .relation), ("leftharpoondown", "↽", .relation),
            ("vDash", "⊨", .relation), ("nrightarrow", "↛", .relation),
            ("orgendaBullet", "•", .ordinary), ("orgendaAmpersand", "&", .ordinary),
            ("orgendaHyphen", "-", .ordinary),
            ("orgendaSubtype", "<:", .relation),
        ]
        for (name, glyph, type) in symbols {
            let atom = MTMathAtomFactory.atom(forCharacter: "=")!
            atom.nucleus = glyph
            atom.type = type
            MTMathAtomFactory.add(latexSymbol: name, value: atom)
        }
    }()

}
