import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Explicit font metrics shared by SwiftUI and selectable UIKit readers.
/// Use the same token instead of opaque SwiftUI Font overrides when both paths must match.
public struct MarkdownFontToken {
    public var fontName: String?
    public var size: CGFloat
    public var weight: Font.Weight
    public var monospaced: Bool
    public init(fontName: String? = nil, size: CGFloat, weight: Font.Weight = .regular, monospaced: Bool = false) {
        self.fontName = fontName; self.size = size; self.weight = weight; self.monospaced = monospaced
        self = normalized()
    }
    public func font(relativeTo role: Font.TextStyle = .body) -> Font {
        let size = MarkdownTokenValidation.positive(self.size, fallback: 17)
        if let fontName { return .custom(fontName, size: size, relativeTo: role).weight(weight) }
        #if os(iOS)
        let name = monospaced ? UIFont.monospacedSystemFont(ofSize: size, weight: uiWeight).fontName : UIFont.systemFont(ofSize: size, weight: uiWeight).fontName
        return .custom(name, size: size, relativeTo: role)
        #else
        return .system(size: size, weight: weight, design: monospaced ? .monospaced : .default)
        #endif
    }
    #if os(iOS)
    var uiWeight: UIFont.Weight {
        switch weight {
        case .ultraLight: .ultraLight
        case .thin: .thin
        case .light: .light
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        case .heavy: .heavy
        case .black: .black
        default: .regular
        }
    }
    func uiFont(textStyle: Font.TextStyle, traits: UITraitCollection) -> UIFont {
        let size = MarkdownTokenValidation.positive(self.size, fallback: 17)
        let base: UIFont
        if let name = fontName, let custom = UIFont(name: name, size: size) {
            let descriptor = custom.fontDescriptor.addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: uiWeight]])
            base = UIFont(descriptor: descriptor, size: size)
        } else { base = monospaced ? .monospacedSystemFont(ofSize: size, weight: uiWeight) : .systemFont(ofSize: size, weight: uiWeight) }
        return UIFontMetrics(forTextStyle: MarkdownTypography.uiTextStyle(textStyle)).scaledFont(for: base, compatibleWith: traits)
    }
    #endif
}

/// Body/heading font tokens and line height ratios shared by both renderer paths.
public struct MarkdownTypographyTokens {
    public var paragraph: MarkdownFontToken?
    public var headings: [MarkdownFontToken]?
    public var paragraphLineHeight: CGFloat
    public var headingLineHeights: [CGFloat]
    public init(paragraph: MarkdownFontToken? = nil, headings: [MarkdownFontToken]? = nil,
                paragraphLineHeight: CGFloat = 1.5, headingLineHeights: [CGFloat] = [1.3, 1.3, 1.4, 1.4, 1.4, 1.4]) {


        self.paragraph = paragraph; self.headings = headings
        self.paragraphLineHeight = paragraphLineHeight; self.headingLineHeights = headingLineHeights
        self = normalized()
    }
}

/// Six named heading values. This avoids missing levels and out-of-range array indexing.
public struct MarkdownHeadingValues<Value> {
    public var h1: Value
    public var h2: Value
    public var h3: Value
    public var h4: Value
    public var h5: Value
    public var h6: Value
    public init(h1: Value, h2: Value, h3: Value, h4: Value, h5: Value, h6: Value) {
        self.h1 = h1; self.h2 = h2; self.h3 = h3; self.h4 = h4; self.h5 = h5; self.h6 = h6
    }
    public var values: [Value] { [h1, h2, h3, h4, h5, h6] }
    public subscript(level level: Int) -> Value {
        get { values[min(5, max(0, level - 1))] }
        set {
            switch min(6, max(1, level)) {
            case 1: h1 = newValue
            case 2: h2 = newValue
            case 3: h3 = newValue
            case 4: h4 = newValue
            case 5: h5 = newValue
            default: h6 = newValue
            }
        }
    }
}

public extension MarkdownTypographyTokens {
    var headingFontsByLevel: MarkdownHeadingValues<MarkdownFontToken>? {
        get {
            guard let values = normalized().headings else { return nil }
            return .init(h1: values[0], h2: values[1], h3: values[2], h4: values[3], h5: values[4], h6: values[5])
        }
        set { headings = newValue?.values.map { $0.normalized() } }
    }
    var headingLineHeightsByLevel: MarkdownHeadingValues<CGFloat> {
        get {
            let values = normalized().headingLineHeights
            return .init(h1: values[0], h2: values[1], h3: values[2], h4: values[3], h5: values[4], h6: values[5])
        }
        set { headingLineHeights = newValue.values; self = normalized() }
    }
}
