import SwiftUI

/// Public component tokens. Document typography and semantic styles stay in MarkdownStyleSheet.
/// Mutate a nested group on a copy to preserve other defaults and presets.
public struct MarkdownDesignTokens {
    public var document: MarkdownDocumentTokens
    public var typography: MarkdownTypographyTokens
    public var heading: MarkdownHeadingTokens
    public var quote: MarkdownQuoteTokens
    public var code: MarkdownCodeTokens
    public var link: MarkdownLinkTokens
    public var details: MarkdownDetailsTokens
    public var keyboard: MarkdownKeyboardTokens
    public var math: MarkdownMathTokens
    public var plugins: MarkdownPluginTokens
    public var mermaid: MarkdownMermaidTokens
    public var footnotePadding: EdgeInsets
    public var imagePlaceholderMinSize: CGFloat

    public init(
        document: MarkdownDocumentTokens = .init(),
        typography: MarkdownTypographyTokens = .init(),
        heading: MarkdownHeadingTokens = .init(),
        quote: MarkdownQuoteTokens = .init(),
        code: MarkdownCodeTokens = .init(),
        link: MarkdownLinkTokens = .init(),
        details: MarkdownDetailsTokens = .init(),
        keyboard: MarkdownKeyboardTokens = .init(),
        math: MarkdownMathTokens = .init(),
        plugins: MarkdownPluginTokens = .init(),
        mermaid: MarkdownMermaidTokens = .init(),
        footnotePadding: EdgeInsets = .init(top: 8, leading: 16, bottom: 8, trailing: 0),
        imagePlaceholderMinSize: CGFloat = 48
    ) {
        self.document = document
        self.typography = typography
        self.heading = heading
        self.quote = quote
        self.code = code
        self.link = link
        self.details = details
        self.keyboard = keyboard
        self.math = math
        self.plugins = plugins
        self.mermaid = mermaid
        self.footnotePadding = footnotePadding
        self.imagePlaceholderMinSize = imagePlaceholderMinSize
        self = normalized()
    }
}

public struct MarkdownHeadingTokens {
    public var accentColor: Color?
    public var decoratedThroughLevel: Int
    public var padding: EdgeInsets
    public var barWidth: CGFloat
    public var barRadius: CGFloat
    public var barSpacing: CGFloat
    public var barEndAlpha: Double
    public var ruleThickness: CGFloat
    public var ruleStartAlpha: Double
    public var ruleEndAlpha: Double

    public init(
        accentColor: Color? = nil,
        decoratedThroughLevel: Int = 2,
        padding: EdgeInsets = .init(top: 8, leading: 0, bottom: 8, trailing: 0),
        barWidth: CGFloat = 4,
        barRadius: CGFloat = 2,
        barSpacing: CGFloat = 12,
        barEndAlpha: Double = 0.3,
        ruleThickness: CGFloat = 2,
        ruleStartAlpha: Double = 0.3,
        ruleEndAlpha: Double = 0
    ) {


        self.accentColor = accentColor
        self.decoratedThroughLevel = decoratedThroughLevel
        self.padding = padding
        self.barWidth = barWidth
        self.barRadius = barRadius
        self.barSpacing = barSpacing
        self.barEndAlpha = barEndAlpha
        self.ruleThickness = ruleThickness
        self.ruleStartAlpha = ruleStartAlpha
        self.ruleEndAlpha = ruleEndAlpha
        self = normalized()
    }
}

public struct MarkdownQuoteTokens {
    public var gradientStartColor: Color?
    public var gradientEndColor: Color?
    public var borderAlpha: Double
    public var showIcon: Bool
    public var iconColor: Color?
    public var iconAlpha: Double
    /// Legacy SwiftUI-only opaque font override. Use iconTypography for a shared override.
    public var iconFont: Font?
    public var iconTypography: MarkdownFontToken?
    /// Shared icon point size used by SwiftUI defaults and native selectable quotes.
    public var iconSize: CGFloat
    public var iconSpacing: CGFloat
    public var cornerRadius: CGFloat
    /// Shared quote shadow drawn by both SwiftUI and native selectable readers.
    public var shadowColor: Color
    public var shadowRadius: CGFloat
    public var shadowX: CGFloat
    public var shadowY: CGFloat

    public init(
        gradientStartColor: Color? = nil,
        gradientEndColor: Color? = nil,
        borderAlpha: Double = 0.6,
        showIcon: Bool = true,
        iconColor: Color? = nil,
        iconAlpha: Double = 0.4,
        iconFont: Font? = nil,
        iconTypography: MarkdownFontToken? = nil,
        iconSize: CGFloat = 24,
        iconSpacing: CGFloat = 12,
        cornerRadius: CGFloat = 4,
        shadowColor: Color = .black.opacity(0.05),
        shadowRadius: CGFloat = 4,
        shadowX: CGFloat = 0,
        shadowY: CGFloat = 2
    ) {

        self.gradientStartColor = gradientStartColor
        self.gradientEndColor = gradientEndColor
        self.borderAlpha = borderAlpha
        self.showIcon = showIcon
        self.iconColor = iconColor
        self.iconAlpha = iconAlpha
        self.iconFont = iconFont
        self.iconTypography = iconTypography
        self.iconSize = iconSize
        self.iconSpacing = iconSpacing
        self.cornerRadius = cornerRadius
        self.shadowColor = shadowColor
        self.shadowRadius = shadowRadius
        self.shadowX = shadowX
        self.shadowY = shadowY
        self = normalized()
    }
}

public struct MarkdownSyntaxColors {
    public var keyword: Color
    public var string: Color
    public var comment: Color
    public var number: Color
    public var literal: Color
    /// Optional accents inherit the code foreground when unset. Existing palette colors are preserved.
    public var type: Color? = nil
    public var function: Color? = nil
    public var property: Color? = nil
    public var `operator`: Color? = nil
    public var punctuation: Color? = nil
    public var diffAdd: Color? = nil
    public var diffRemove: Color? = nil

    public init(
        keyword: Color = .purple,
        string: Color = .red,
        comment: Color = .green,
        number: Color = .blue,
        literal: Color = .teal
    ) {
        self.keyword = keyword
        self.string = string
        self.comment = comment
        self.number = number
        self.literal = literal
        self = normalized()
    }
}

public extension MarkdownSyntaxColors {
    static func light() -> Self {
        .init(keyword: Color(red: 0.53, green: 0.21, blue: 0.73),
              string: Color(red: 0.65, green: 0.16, blue: 0.19),
              comment: Color(red: 0.26, green: 0.48, blue: 0.29),
              number: Color(red: 0.16, green: 0.38, blue: 0.69),
              literal: Color(red: 0.07, green: 0.49, blue: 0.52))
    }
    static func dark() -> Self {
        .init(keyword: Color(red: 0.78, green: 0.56, blue: 1),
              string: Color(red: 0.95, green: 0.62, blue: 0.55),
              comment: Color(red: 0.54, green: 0.69, blue: 0.58),
              number: Color(red: 0.55, green: 0.75, blue: 1),
              literal: Color(red: 0.43, green: 0.82, blue: 0.82))
    }
}

/// Code body styling stays in the stylesheet. Scrollbar visibility controls the native indicator;
/// native scrollbar dimensions and colors are owned by the operating system.
public struct MarkdownCodeTokens {
    public var headerPadding: EdgeInsets
    public var headerSpacing: CGFloat
    public var languageFont: Font?
    public var languageColor: Color?
    public var languageBackgroundColor: Color?
    public var languagePadding: EdgeInsets
    public var languageCornerRadius: CGFloat
    public var languageBackgroundAlpha: Double
    public var copyFont: Font?
    public var copyColor: Color?
    public var copiedColor: Color
    public var copyBackgroundColor: Color?
    public var copiedBackgroundColor: Color?
    public var copyPadding: EdgeInsets
    public var copyCornerRadius: CGFloat
    public var copyBackgroundAlpha: Double
    public var copiedBackgroundAlpha: Double
    public var copyLabel: String?
    public var copiedLabel: String?
    public var copyFeedbackSeconds: Double
    public var syntaxColors: MarkdownSyntaxColors?
    public var showScrollbar: Bool

    public init(
        headerPadding: EdgeInsets = .init(top: 8, leading: 8, bottom: 0, trailing: 8),
        headerSpacing: CGFloat = 8,
        languageFont: Font? = nil,
        languageColor: Color? = nil,
        languageBackgroundColor: Color? = nil,
        languagePadding: EdgeInsets = .init(top: 4, leading: 8, bottom: 4, trailing: 8),
        languageCornerRadius: CGFloat = 4,
        languageBackgroundAlpha: Double = 0.12,
        copyFont: Font? = nil,
        copyColor: Color? = nil,
        copiedColor: Color = .green,
        copyBackgroundColor: Color? = nil,
        copiedBackgroundColor: Color? = nil,
        copyPadding: EdgeInsets = .init(top: 5, leading: 7, bottom: 5, trailing: 7),
        copyCornerRadius: CGFloat = 4,
        copyBackgroundAlpha: Double = 0.1,
        copiedBackgroundAlpha: Double = 0.16,
        copyLabel: String? = nil,
        copiedLabel: String? = nil,
        copyFeedbackSeconds: Double = 2,
        syntaxColors: MarkdownSyntaxColors? = nil,
        showScrollbar: Bool = true
    ) {


        self.headerPadding = headerPadding
        self.headerSpacing = headerSpacing
        self.languageFont = languageFont
        self.languageColor = languageColor
        self.languageBackgroundColor = languageBackgroundColor
        self.languagePadding = languagePadding
        self.languageCornerRadius = languageCornerRadius
        self.languageBackgroundAlpha = languageBackgroundAlpha
        self.copyFont = copyFont
        self.copyColor = copyColor
        self.copiedColor = copiedColor
        self.copyBackgroundColor = copyBackgroundColor
        self.copiedBackgroundColor = copiedBackgroundColor
        self.copyPadding = copyPadding
        self.copyCornerRadius = copyCornerRadius
        self.copyBackgroundAlpha = copyBackgroundAlpha
        self.copiedBackgroundAlpha = copiedBackgroundAlpha
        self.copyLabel = copyLabel
        self.copiedLabel = copiedLabel
        self.copyFeedbackSeconds = copyFeedbackSeconds
        self.syntaxColors = syntaxColors
        self.showScrollbar = showScrollbar
        self = normalized()
    }
}

/// External-link cue. Link text and underline use MarkdownStyleSheet.linkStyle.
/// Cue offsets apply in both SwiftUI and native selectable readers.
public struct MarkdownLinkTokens {
    public var showExternalIcon: Bool
    public var iconColor: Color?
    public var iconSize: CGFloat
    public var iconGap: CGFloat
    public var iconTopOffset: CGFloat
    public init(showExternalIcon: Bool = true, iconColor: Color? = nil, iconSize: CGFloat = 12,
                iconGap: CGFloat = 2, iconTopOffset: CGFloat = 1) {
        self.showExternalIcon = showExternalIcon; self.iconColor = iconColor
        self.iconSize = iconSize; self.iconGap = iconGap; self.iconTopOffset = iconTopOffset
        self = normalized()
    }
}

public struct MarkdownDetailsTokens {
    public var cornerRadius: CGFloat
    public var outerPadding: EdgeInsets
    public var borderWidth: CGFloat
    public var borderColor: Color?
    public var backgroundColor: Color?
    public var summaryPadding: EdgeInsets
    public var bodyPadding: EdgeInsets
    public var iconSpacing: CGFloat
    public var iconWidth: CGFloat
    public var iconFont: Font?
    public var iconColor: Color?
    public var dividerThickness: CGFloat

    public init(
        cornerRadius: CGFloat = 6,
        outerPadding: EdgeInsets = .init(top: 8, leading: 0, bottom: 8, trailing: 0),
        borderWidth: CGFloat = 1,
        borderColor: Color? = nil,
        backgroundColor: Color? = nil,
        summaryPadding: EdgeInsets = .init(top: 12, leading: 12, bottom: 12, trailing: 12),
        bodyPadding: EdgeInsets = .init(top: 0, leading: 12, bottom: 12, trailing: 12),
        iconSpacing: CGFloat = 8,
        iconWidth: CGFloat = 20,
        iconFont: Font? = nil,
        iconColor: Color? = nil,
        dividerThickness: CGFloat = 1
    ) {
        self.cornerRadius = cornerRadius
        self.outerPadding = outerPadding
        self.borderWidth = borderWidth
        self.borderColor = borderColor
        self.backgroundColor = backgroundColor
        self.summaryPadding = summaryPadding
        self.bodyPadding = bodyPadding
        self.iconSpacing = iconSpacing
        self.iconWidth = iconWidth
        self.iconFont = iconFont
        self.iconColor = iconColor
        self.dividerThickness = dividerThickness
        self = normalized()
    }
}

public struct MarkdownKeyboardTokens {
    public var backgroundColor: Color?
    public var borderColor: Color?
    public var borderWidth: CGFloat
    public var cornerRadius: CGFloat
    public var padding: EdgeInsets
    public var fontSize: CGFloat
    public var backgroundAlpha: Double

    public init(
        backgroundColor: Color? = nil,
        borderColor: Color? = nil,
        borderWidth: CGFloat = 1,
        cornerRadius: CGFloat = 4,
        padding: EdgeInsets = .init(top: 1, leading: 5, bottom: 1, trailing: 5),
        fontSize: CGFloat = 13,
        backgroundAlpha: Double = 0.12
    ) {

        self.backgroundColor = backgroundColor
        self.borderColor = borderColor
        self.borderWidth = borderWidth
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.fontSize = fontSize
        self.backgroundAlpha = backgroundAlpha
        self = normalized()
    }
}

public struct MarkdownMathTokens {
    public var inlineFontSize: CGFloat
    public var displayScale: CGFloat
    public var fontFamily: String
    public var color: Color?
    public var blockPadding: EdgeInsets

    public init(
        inlineFontSize: CGFloat = 16,
        displayScale: CGFloat = 1.25,
        fontFamily: String = "serif",
        color: Color? = nil,
        blockPadding: EdgeInsets = .init(top: 12, leading: 0, bottom: 12, trailing: 0)
    ) {


        self.inlineFontSize = inlineFontSize
        self.displayScale = displayScale
        self.fontFamily = fontFamily
        self.color = color
        self.blockPadding = blockPadding
        self = normalized()
    }
}
