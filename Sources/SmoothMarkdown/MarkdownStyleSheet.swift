import SwiftUI

/// HTML script text uses the surrounding body scale, with a paint-time baseline shift.
enum MarkdownHTMLScript: Equatable {
    case sub, sup

    static let bodyPointSize: CGFloat = 17
    static let fontScale: CGFloat = 0.75

    static func active(in tags: [SafeHTML.Tag]) -> Self? {
        for tag in tags.reversed() {
            if tag.name == "sub" { return .sub }
            if tag.name == "sup" { return .sup }
        }
        return nil
    }

    func baselineOffset(scale: CGFloat) -> CGFloat {
        let factor: CGFloat = self == .sub ? -0.15 : 0.35
        return Self.bodyPointSize * factor * scale
    }
}

/// Text attributes applied to an inline Markdown span. Nil values inherit the
/// surrounding text; a false mark explicitly removes that mark.
public struct MarkdownInlineTextStyle {
    public var fontSize: CGFloat?
    public var textColor: Color?
    public var backgroundColor: Color?
    public var bold: Bool?
    public var italic: Bool?
    public var strikethrough: Bool?
    public var underline: Bool?
    public var monospaced: Bool?

    public init(fontSize: CGFloat? = nil, textColor: Color? = nil, backgroundColor: Color? = nil,
                bold: Bool? = nil, italic: Bool? = nil, strikethrough: Bool? = nil,
                underline: Bool? = nil, monospaced: Bool? = nil) {
        self.fontSize = fontSize.map { max(0, $0) }
        self.textColor = textColor
        self.backgroundColor = backgroundColor
        self.bold = bold
        self.italic = italic
        self.strikethrough = strikethrough
        self.underline = underline
        self.monospaced = monospaced
    }

    fileprivate mutating func apply(_ other: Self?) {
        guard let other else { return }
        if let value = other.fontSize { fontSize = value }
        if let value = other.textColor { textColor = value }
        if let value = other.backgroundColor { backgroundColor = value }
        if let value = other.bold { bold = value }
        if let value = other.italic { italic = value }
        if let value = other.strikethrough { strikethrough = value }
        if let value = other.underline { underline = value }
        if let value = other.monospaced { monospaced = value }
    }
}

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

/// Fill, outline, and corner radius of a fenced code block.
public struct MarkdownCodeBlockDecoration {
    public var backgroundColor: Color?
    public var borderColor: Color?
    public var borderWidth: CGFloat
    public var cornerRadius: CGFloat

    public init(backgroundColor: Color? = nil, borderColor: Color? = nil,
                borderWidth: CGFloat = 0, cornerRadius: CGFloat = 0) {
        self.backgroundColor = backgroundColor
        self.borderColor = borderColor
        self.borderWidth = max(0, borderWidth)
        self.cornerRadius = max(0, cornerRadius)
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
    /// Overrides the legacy code background and default rounded shape when provided.
    public var codeBlockDecoration: MarkdownCodeBlockDecoration?
    /// Four-sided padding inside fenced code blocks; nil uses `codePadding` on all sides.
    public var codeBlockPadding: EdgeInsets?
    public var codeTextColor: Color?
    public var inlineCodeBackground: Color?
    public var inlineCodeTextColor: Color?
    public var boldStyle: MarkdownInlineTextStyle?
    public var italicStyle: MarkdownInlineTextStyle?
    public var strikethroughStyle: MarkdownInlineTextStyle?
    public var linkStyle: MarkdownInlineTextStyle?
    public var inlineCodeStyle: MarkdownInlineTextStyle?
    /// Text style for HTML `<sub>` content; defaults to 75% of body size.
    public var subscriptStyle: MarkdownInlineTextStyle?
    /// Text style for HTML `<sup>` content; defaults to 75% of body size.
    public var superscriptStyle: MarkdownInlineTextStyle?
    public var quoteBarColor: Color?
    public var quoteBackground: Color?
    /// Overrides the legacy quote colors and left border width when provided.
    public var blockquoteDecoration: MarkdownBlockquoteDecoration?
    /// Insets inside the blockquote background and border.
    public var blockquotePadding: EdgeInsets
    /// Outer and inner table rules. When set, this takes precedence over `tableBorderColor`.
    /// An empty border draws no rules, matching Flutter's nullable `tableBorder`.
    public var tableBorder: MarkdownTableBorder?
    /// Legacy all-sides table color; used as a 1pt grid when `tableBorder` is nil.
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
    /// Semantic roles used by the selectable UIKit reader. Set these with custom
    /// SwiftUI fonts so both renderer paths respond to Dynamic Type alike.
    public var readerParagraphTextStyle: Font.TextStyle
    public var readerHeadingTextStyles: [Font.TextStyle]
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
        readerParagraphTextStyle: Font.TextStyle = .body,
        readerHeadingTextStyles: [Font.TextStyle] = [.title, .title2, .title3, .headline, .subheadline, .footnote],
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
        blockquotePadding: EdgeInsets = EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16),
        codeBlockDecoration: MarkdownCodeBlockDecoration? = nil,
        codeBlockPadding: EdgeInsets? = nil,
        boldStyle: MarkdownInlineTextStyle? = nil,
        italicStyle: MarkdownInlineTextStyle? = nil,
        strikethroughStyle: MarkdownInlineTextStyle? = nil,
        linkStyle: MarkdownInlineTextStyle? = nil,
        inlineCodeStyle: MarkdownInlineTextStyle? = nil,
        subscriptStyle: MarkdownInlineTextStyle? = nil,
        superscriptStyle: MarkdownInlineTextStyle? = nil,
        tableBorder: MarkdownTableBorder? = nil
    ) {
        self.backgroundColor = backgroundColor
        self.textColor = textColor
        self.headingColor = headingColor
        self.linkColor = linkColor
        self.codeBackground = codeBackground
        self.codeBlockDecoration = codeBlockDecoration
        self.codeBlockPadding = codeBlockPadding.map { EdgeInsets(top: max(0, $0.top), leading: max(0, $0.leading),
                                                                 bottom: max(0, $0.bottom), trailing: max(0, $0.trailing)) }
        self.codeTextColor = codeTextColor
        self.inlineCodeBackground = inlineCodeBackground
        self.inlineCodeTextColor = inlineCodeTextColor
        self.boldStyle = boldStyle
        self.italicStyle = italicStyle
        self.strikethroughStyle = strikethroughStyle
        self.linkStyle = linkStyle
        self.inlineCodeStyle = inlineCodeStyle
        self.subscriptStyle = subscriptStyle
        self.superscriptStyle = superscriptStyle
        self.quoteBarColor = quoteBarColor
        self.quoteBackground = quoteBackground
        self.blockquoteDecoration = blockquoteDecoration
        self.blockquotePadding = EdgeInsets(top: max(0, blockquotePadding.top),
                                           leading: max(0, blockquotePadding.leading),
                                           bottom: max(0, blockquotePadding.bottom),
                                           trailing: max(0, blockquotePadding.trailing))
        self.tableBorderColor = tableBorderColor
        self.tableBorder = tableBorder
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
        self.readerParagraphTextStyle = readerParagraphTextStyle
        self.readerHeadingTextStyles = readerHeadingTextStyles
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
             blockSpacing: 16, listIndent: 24, darkCodeHighlighting: false,
             codeBlockDecoration: .init(borderColor: rgb(0xE0E0E0), borderWidth: 1, cornerRadius: 4),
             inlineCodeStyle: .init(fontSize: 14),
             subscriptStyle: .init(fontSize: MarkdownHTMLScript.bodyPointSize * MarkdownHTMLScript.fontScale),
             superscriptStyle: .init(fontSize: MarkdownHTMLScript.bodyPointSize * MarkdownHTMLScript.fontScale))
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
             blockSpacing: 16, listIndent: 24, darkCodeHighlighting: true,
             codeBlockDecoration: .init(borderColor: rgb(0x616161), borderWidth: 1, cornerRadius: 4),
             inlineCodeStyle: .init(fontSize: 14),
             subscriptStyle: .init(fontSize: MarkdownHTMLScript.bodyPointSize * MarkdownHTMLScript.fontScale),
             superscriptStyle: .init(fontSize: MarkdownHTMLScript.bodyPointSize * MarkdownHTMLScript.fontScale))
    }

    public static func github(dark: Bool = false) -> Self {
        var style = dark ? Self.dark() : Self.light()
        style.backgroundColor = rgb(dark ? 0x0D1117 : 0xFFFFFF)
        style.textColor = rgb(dark ? 0xE6EDF3 : 0x24292F)
        style.headingColor = style.textColor
        style.linkColor = rgb(dark ? 0x58A6FF : 0x0969DA)
        style.codeBackground = rgb(dark ? 0x161B22 : 0xF6F8FA)
        style.codeBlockDecoration = .init(cornerRadius: 6)
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
        style.codeBlockDecoration = .init(borderColor: rgb(dark ? 0x404040 : 0xE0E0E0),
                                          borderWidth: 1, cornerRadius: 4)
        style.codeTextColor = rgb(dark ? 0xD4D4D4 : 0x1E1E1E)
        style.tableBorderColor = rgb(dark ? 0x404040 : 0xE0E0E0)
        return style
    }

    private static var defaultHeadingFonts: [Font] {
        MarkdownTypography.headings
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

    internal var resolvedCodeBlockDecoration: MarkdownCodeBlockDecoration {
        if let codeBlockDecoration {
            return .init(backgroundColor: codeBlockDecoration.backgroundColor ?? codeBackground ?? Color.secondary.opacity(0.1),
                         borderColor: codeBlockDecoration.borderColor,
                         borderWidth: codeBlockDecoration.borderWidth,
                         cornerRadius: codeBlockDecoration.cornerRadius)
        }
        return .init(backgroundColor: codeBackground ?? Color.secondary.opacity(0.1), cornerRadius: 8)
    }

    internal var resolvedCodeBlockPadding: EdgeInsets {
        codeBlockPadding ?? EdgeInsets(top: codePadding, leading: codePadding,
                                       bottom: codePadding, trailing: codePadding)
    }

    internal var resolvedTableBorder: MarkdownTableBorder? {
        if let tableBorder { return tableBorder }
        return tableBorderColor.map { .all(color: $0) }
    }

    internal func resolvedInlineStyle(bold: Bool, italic: Bool, strike: Bool,
                                      link: Bool, code: Bool,
                                      script: MarkdownHTMLScript? = nil) -> MarkdownInlineTextStyle {
        var result = MarkdownInlineTextStyle(
            textColor: code ? inlineCodeTextColor : link ? (linkColor ?? .blue) : nil,
            backgroundColor: code ? inlineCodeBackground : nil,
            bold: bold, italic: italic, strikethrough: strike,
            underline: link, monospaced: code)
        if bold { result.apply(boldStyle) }
        if italic { result.apply(italicStyle) }
        if strike { result.apply(strikethroughStyle) }
        if link { result.apply(linkStyle) }
        if code { result.apply(inlineCodeStyle) }
        if let script {
            result.fontSize = MarkdownHTMLScript.bodyPointSize * MarkdownHTMLScript.fontScale
            result.apply(script == .sub ? subscriptStyle : superscriptStyle)
        }
        return result
    }
}
