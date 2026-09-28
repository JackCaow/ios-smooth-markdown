import SwiftUI

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
    public var tableBorderColor: Color?
    public var ruleColor: Color?
    public var footnoteColor: Color?
    public var highlightColor: Color?
    public var headingFonts: [Font]?
    public var paragraphFont: Font?
    public var codeFont: Font?
    public var tableHeaderFont: Font?
    public var tableCellFont: Font?
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
        ruleColor: Color? = nil,
        footnoteColor: Color? = nil,
        highlightColor: Color? = nil,
        headingFonts: [Font]? = nil,
        paragraphFont: Font? = nil,
        codeFont: Font? = nil,
        tableHeaderFont: Font? = nil,
        tableCellFont: Font? = nil,
        blockSpacing: CGFloat = 12,
        contentPadding: CGFloat = 16,
        quoteSpacing: CGFloat = 8,
        listSpacing: CGFloat = 4,
        listIndent: CGFloat = 32,
        codePadding: CGFloat = 12,
        tableCellPadding: CGFloat = 8,
        darkCodeHighlighting: Bool? = nil
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
        self.tableBorderColor = tableBorderColor
        self.ruleColor = ruleColor
        self.footnoteColor = footnoteColor
        self.highlightColor = highlightColor
        self.headingFonts = headingFonts
        self.paragraphFont = paragraphFont
        self.codeFont = codeFont
        self.tableHeaderFont = tableHeaderFont
        self.tableCellFont = tableCellFont
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
             quoteBarColor: rgb(0xBDBDBD), tableBorderColor: rgb(0xE0E0E0),
             ruleColor: rgb(0xBDBDBD), footnoteColor: rgb(0x1976D2),
             headingFonts: defaultHeadingFonts, paragraphFont: .system(size: 16),
             blockSpacing: 16, listIndent: 24, darkCodeHighlighting: false)
    }

    public static func dark() -> Self {
        Self(backgroundColor: rgb(0x121212), textColor: rgb(0xB3B3B3), headingColor: .white,
             linkColor: rgb(0x64B5F6), codeBackground: rgb(0x212121), codeTextColor: rgb(0xB3B3B3),
             inlineCodeBackground: rgb(0x424242), inlineCodeTextColor: rgb(0xEF9A9A),
             quoteBarColor: rgb(0x757575), tableBorderColor: rgb(0x616161),
             ruleColor: rgb(0x616161), footnoteColor: rgb(0x64B5F6),
             headingFonts: defaultHeadingFonts, paragraphFont: .system(size: 16),
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
        [32, 28, 24, 20, 18, 16].map { .system(size: CGFloat($0), weight: .bold) }
    }

    private static func rgb(_ value: UInt32) -> Color {
        Color(.sRGB, red: Double((value >> 16) & 0xFF) / 255,
              green: Double((value >> 8) & 0xFF) / 255,
              blue: Double(value & 0xFF) / 255, opacity: 1)
    }
}
