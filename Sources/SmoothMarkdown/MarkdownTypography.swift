import SwiftUI

#if os(iOS)
import UIKit
#endif

/// Semantic type roles shared by the SwiftUI reader and its selectable UIKit renderer.
enum MarkdownTypography {
    static let headingStyles: [Font.TextStyle] = [
        .title, .title2, .title3, .headline, .subheadline, .footnote,
    ]

    static func heading(_ level: Int) -> Font {
        .system(headingStyles[min(max(level - 1, 0), headingStyles.count - 1)], weight: .semibold)
    }

    static var headings: [Font] { (1...6).map(heading) }

    #if os(iOS)
    private static let uiHeadingStyles: [UIFont.TextStyle] = [
        .title1, .title2, .title3, .headline, .subheadline, .footnote,
    ]

    static func textStyle(forHeading level: Int) -> UIFont.TextStyle {
        uiHeadingStyles[min(max(level - 1, 0), uiHeadingStyles.count - 1)]
    }

    static func uiTextStyle(_ style: Font.TextStyle) -> UIFont.TextStyle {
        switch style {
        case .largeTitle: .largeTitle
        case .title: .title1
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .subheadline: .subheadline
        case .callout: .callout
        case .footnote: .footnote
        case .caption: .caption1
        case .caption2: .caption2
        default: .body
        }
    }

    static func traits(for size: DynamicTypeSize) -> UITraitCollection {
        let category: UIContentSizeCategory
        switch size {
        case .xSmall: category = .extraSmall
        case .small: category = .small
        case .medium: category = .medium
        case .large: category = .large
        case .xLarge: category = .extraLarge
        case .xxLarge: category = .extraExtraLarge
        case .xxxLarge: category = .extraExtraExtraLarge
        case .accessibility1: category = .accessibilityMedium
        case .accessibility2: category = .accessibilityLarge
        case .accessibility3: category = .accessibilityExtraLarge
        case .accessibility4: category = .accessibilityExtraExtraLarge
        case .accessibility5: category = .accessibilityExtraExtraExtraLarge
        @unknown default: category = .large
        }
        return UITraitCollection(preferredContentSizeCategory: category)
    }

    static func font(forHeading level: Int?, weight: UIFont.Weight,
                     customSize: CGFloat?, traits: UITraitCollection) -> UIFont {
        let textStyle = level.map(textStyle(forHeading:)) ?? .body
        return font(textStyle: textStyle, weight: weight, customSize: customSize, traits: traits)
    }

    static func font(textStyle: UIFont.TextStyle, weight: UIFont.Weight,
                     customSize: CGFloat?, traits: UITraitCollection) -> UIFont {
        if let customSize {
            let base = UIFont.systemFont(ofSize: max(1, customSize), weight: weight)
            return UIFontMetrics(forTextStyle: textStyle).scaledFont(for: base, compatibleWith: traits)
        }
        let preferred = UIFont.preferredFont(forTextStyle: textStyle, compatibleWith: traits)
        return UIFont.systemFont(ofSize: preferred.pointSize, weight: weight)
    }
    #endif
}
