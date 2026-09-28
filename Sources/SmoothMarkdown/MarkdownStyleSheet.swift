import SwiftUI

/// Fill and left border of a Markdown blockquote. Nil colors inherit the legacy quote colors.
public struct MarkdownBlockquoteDecoration {
    public var backgroundColor: Color?
    public var borderColor: Color?
    public var borderWidth: CGFloat

    public init(backgroundColor: Color? = nil, borderColor: Color? = nil, borderWidth: CGFloat = 4) {
        self.backgroundColor = backgroundColor
        self.borderColor = borderColor
        self.borderWidth = max(0, borderWidth)
    }
}

/// Visual settings for `SmoothMarkdownView` and `StreamMarkdownView`.
/// Nil colors and fonts inherit the host application's SwiftUI appearance.
public struct MarkdownStyleSheet {
    public var backgroundColor: Color?
    public var textColor: Color?
    public var headingColor: Color?
    public var linkColor: Color?
    public var codeBackground: Color?
    public var codeTextColor: Color?
    public var inlineCodeBackground: Color?
    public var inlineCodeTextColor: Color?
    public var quoteBarColor: Color?
    public var quoteBackground: Color?
    /// Overrides the legacy quote colors and left border width when provided.
    public var blockquoteDecoration: MarkdownBlockquoteDecoration?
    /// Insets inside the blockquote background and border.
    public var blockquotePadding: EdgeInsets
    public var tableBorderColor: Color?
    /// Background behind the header row, matching Flutter's tableHeaderDecoration color.
    public var tableHeaderBackgroundColor: Color?
    public var ruleColor: Color?
    /// Thickness of Markdown and HTML horizontal rules, in points.
    public var horizontalRuleThickness: CGFloat
    public var footnoteColor: Color?
    public var highlightColor: Color?
    public var headingFonts: [Font]?
    public var paragraphFont: Font?
    public var codeFont: Font?
    public var tableHeaderFont: Font?
    public var tableCellFont: Font?
    /// Font and color of ordered and unordered list markers.
    public var listBulletFont: Font?
    public var listBulletColor: Color?
    public var blockSpacing: CGFloat
    public var contentPadding: CGFloat
    public var quoteSpacing: CGFloat
    public var listSpacing: CGFloat
    public var listIndent: CGFloat
    public var codePadding: CGFloat
    public var tableCellPadding: CGFloat
    /// Nil follows the host color scheme for syntax highlighting.
    public var darkCodeHighlighting: Bool?

    public init(
        backgroundColor: Color? = nil,
        textColor: Color? = nil,
        headingColor: Color? = nil,
        linkColor: Color? = nil,
        codeBackground: Color? = nil,
        codeTextColor: Color? = nil,
        inlineCodeBackground: Color? = nil,
        inlineCodeTextColor: Color? = nil,
        quoteBarColor: Color? = nil,
        quoteBackground: Color? = nil,
        tableBorderColor: Color? = nil,
        tableHeaderBackgroundColor: Color? = nil,
        ruleColor: Color? = nil,
        horizontalRuleThickness: CGFloat = 1,
        footnoteColor: Color? = nil,
        highlightColor: Color? = nil,
        headingFonts: [Font]? = nil,
        paragraphFont: Font? = nil,
        codeFont: Font? = nil,
        tableHeaderFont: Font? = nil,
        tableCellFont: Font? = nil,
        listBulletFont: Font? = nil,
        listBulletColor: Color? = nil,
        blockSpacing: CGFloat = 12,
        contentPadding: CGFloat = 16,
        quoteSpacing: CGFloat = 8,
        listSpacing: CGFloat = 4,
        listIndent: CGFloat = 32,
        codePadding: CGFloat = 12,
        tableCellPadding: CGFloat = 8,
        darkCodeHighlighting: Bool? = nil,
        blockquoteDecoration: MarkdownBlockquoteDecoration? = nil,
        blockquotePadding: EdgeInsets = EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)
    ) {
        self.backgroundColor = backgroundColor
        self.textColor = textColor
        self.headingColor = headingColor
        self.linkColor = linkColor
        self.codeBackground = codeBackground
        self.codeTextColor = codeTextColor
        self.inlineCodeBackground = inlineCodeBackground
        self.inlineCodeTextColor = inlineCodeTextColor
        self.quoteBarColor = quoteBarColor
        self.quoteBackground = quoteBackground
        self.blockquoteDecoration = blockquoteDecoration
        self.blockquotePadding = EdgeInsets(top: max(0, blockquotePadding.top),
                                           leading: max(0, blockquotePadding.leading),
                                           bottom: max(0, blockquotePadding.bottom),
                                           trailing: max(0, blockquotePadding.trailing))
        self.tableBorderColor = tableBorderColor
        self.tableHeaderBackgroundColor = tableHeaderBackgroundColor
        self.ruleColor = ruleColor
        self.horizontalRuleThickness = max(0, horizontalRuleThickness)
        self.footnoteColor = footnoteColor
        self.highlightColor = highlightColor
        self.headingFonts = headingFonts
        self.paragraphFont = paragraphFont
        self.codeFont = codeFont
        self.tableHeaderFont = tableHeaderFont
        self.tableCellFont = tableCellFont
        self.listBulletFont = listBulletFont
        self.listBulletColor = listBulletColor
        self.blockSpacing = max(0, blockSpacing)
        self.contentPadding = max(0, contentPadding)
        self.quoteSpacing = max(0, quoteSpacing)
        self.listSpacing = max(0, listSpacing)
        self.listIndent = max(0, listIndent)
        self.codePadding = max(0, codePadding)
        self.tableCellPadding = max(0, tableCellPadding)
        self.darkCodeHighlighting = darkCodeHighlighting
    }

    public static func `default`() -> Self { Self() }

    public static func light() -> Self {
        Self(backgroundColor: .white, textColor: rgb(0x212121), headingColor: .black,
             linkColor: rgb(0x1976D2), codeBackground: rgb(0xF5F5F5), codeTextColor: rgb(0x212121),
             inlineCodeBackground: rgb(0xEEEEEE), inlineCodeTextColor: rgb(0xD32F2F),
             quoteBarColor: rgb(0xBDBDBD), quoteBackground: rgb(0xFAFAFA),
             tableBorderColor: rgb(0xE0E0E0),
             tableHeaderBackgroundColor: rgb(0xEEEEEE),
             ruleColor: rgb(0xBDBDBD), footnoteColor: rgb(0x1976D2),
             headingFonts: defaultHeadingFonts, paragraphFont: .body,
             blockSpacing: 16, listIndent: 24, darkCodeHighlighting: false)
    }

    public static func dark() -> Self {
        Self(backgroundColor: rgb(0x121212), textColor: rgb(0xB3B3B3), headingColor: .white,
             linkColor: rgb(0x64B5F6), codeBackground: rgb(0x212121), codeTextColor: rgb(0xB3B3B3),
             inlineCodeBackground: rgb(0x424242), inlineCodeTextColor: rgb(0xEF9A9A),
             quoteBarColor: rgb(0x757575), quoteBackground: rgb(0x212121),
             tableBorderColor: rgb(0x616161),
             tableHeaderBackgroundColor: rgb(0x303030),
             ruleColor: rgb(0x616161), footnoteColor: rgb(0x64B5F6),
             headingFonts: defaultHeadingFonts, paragraphFont: .body,
             blockSpacing: 16, listIndent: 24, darkCodeHighlighting: true)
    }

    public static func github(dark: Bool = false) -> Self {
        var style = dark ? Self.dark() : Self.light()
        style.backgroundColor = rgb(dark ? 0x0D1117 : 0xFFFFFF)
        style.textColor = rgb(dark ? 0xE6EDF3 : 0x24292F)
        style.headingColor = style.textColor
        style.linkColor = rgb(dark ? 0x58A6FF : 0x0969DA)
        style.codeBackground = rgb(dark ? 0x161B22 : 0xF6F8FA)
        style.codeTextColor = style.textColor
        return style
    }

    public static func vscode(dark: Bool = false) -> Self {
        var style = dark ? Self.dark() : Self.light()
        style.backgroundColor = rgb(dark ? 0x1E1E1E : 0xFFFFFF)
        style.textColor = rgb(dark ? 0xCCCCCC : 0x1E1E1E)
        style.headingColor = style.textColor
        style.linkColor = rgb(dark ? 0x4FC1FF : 0x0066BF)
        style.codeBackground = rgb(dark ? 0x1E1E1E : 0xF5F5F5)
        style.codeTextColor = rgb(dark ? 0xD4D4D4 : 0x1E1E1E)
        style.tableBorderColor = rgb(dark ? 0x404040 : 0xE0E0E0)
        return style
    }

    private static var defaultHeadingFonts: [Font] {
        [.largeTitle, .title, .title2, .title3, .headline, .subheadline]
            .map { .system($0, weight: .bold) }
    }

    private static func rgb(_ value: UInt32) -> Color {
        Color(.sRGB, red: Double((value >> 16) & 0xFF) / 255,
              green: Double((value >> 8) & 0xFF) / 255,
              blue: Double(value & 0xFF) / 255, opacity: 1)
    }

    internal var resolvedBlockquoteDecoration: MarkdownBlockquoteDecoration {
        if let blockquoteDecoration {
            return MarkdownBlockquoteDecoration(
                backgroundColor: blockquoteDecoration.backgroundColor,
                borderColor: blockquoteDecoration.borderColor ?? quoteBarColor ?? .accentColor,
                borderWidth: blockquoteDecoration.borderWidth)
        }
        return MarkdownBlockquoteDecoration(backgroundColor: quoteBackground,
                                            borderColor: quoteBarColor ?? .accentColor)
    }
}
