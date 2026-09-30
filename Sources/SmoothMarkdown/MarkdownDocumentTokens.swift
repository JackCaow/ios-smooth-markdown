import SwiftUI

/// Semantic document colors. Non-nil token values override legacy stylesheet fields.
/// Nil inherits the legacy value or the host's platform appearance.
public struct MarkdownDocumentTokens {
    public var textColor: Color?
    public var headingColor: Color?
    public var linkColor: Color?
    public var codeBackground: Color?
    public var codeTextColor: Color?
    public var inlineCodeBackground: Color?
    public var inlineCodeTextColor: Color?
    public var highlightColor: Color?
    public var footnoteColor: Color?
    public var quoteBarColor: Color?
    public var quoteBackground: Color?
    public var tableBorderColor: Color?
    public var ruleColor: Color?
    public var backgroundColor: Color?
    public var tableHeaderBackgroundColor: Color?

    public init(textColor: Color? = nil, headingColor: Color? = nil, linkColor: Color? = nil,
                codeBackground: Color? = nil, codeTextColor: Color? = nil,
                inlineCodeBackground: Color? = nil, inlineCodeTextColor: Color? = nil,
                highlightColor: Color? = nil, footnoteColor: Color? = nil,
                quoteBarColor: Color? = nil, quoteBackground: Color? = nil,
                tableBorderColor: Color? = nil, ruleColor: Color? = nil, backgroundColor: Color? = nil,
                tableHeaderBackgroundColor: Color? = nil) {
        self.textColor = textColor; self.headingColor = headingColor; self.linkColor = linkColor
        self.codeBackground = codeBackground; self.codeTextColor = codeTextColor
        self.inlineCodeBackground = inlineCodeBackground; self.inlineCodeTextColor = inlineCodeTextColor
        self.highlightColor = highlightColor; self.footnoteColor = footnoteColor
        self.quoteBarColor = quoteBarColor; self.quoteBackground = quoteBackground
        self.tableBorderColor = tableBorderColor; self.ruleColor = ruleColor
        self.backgroundColor = backgroundColor; self.tableHeaderBackgroundColor = tableHeaderBackgroundColor
    }
}

public extension MarkdownStyleSheet {
    /// Produces a rendering snapshot without replacing the caller's legacy fallbacks.
    /// Semantic design tokens win over explicit legacy decoration/inline fields,
    /// followed by legacy scalar colors, then platform defaults.
    func resolved() -> Self {
        var value = normalized()
        let document = designTokens.document
        value.textColor = document.textColor ?? value.textColor
        value.headingColor = document.headingColor ?? value.headingColor
        value.linkColor = document.linkColor ?? value.linkColor
        value.codeBackground = document.codeBackground ?? value.codeBackground
        value.codeTextColor = document.codeTextColor ?? value.codeTextColor
        value.inlineCodeBackground = document.inlineCodeBackground ?? value.inlineCodeBackground
        value.inlineCodeTextColor = document.inlineCodeTextColor ?? value.inlineCodeTextColor
        value.highlightColor = document.highlightColor ?? value.highlightColor
        value.footnoteColor = document.footnoteColor ?? value.footnoteColor
        value.quoteBarColor = document.quoteBarColor ?? value.quoteBarColor
        value.quoteBackground = document.quoteBackground ?? value.quoteBackground
        value.tableBorderColor = document.tableBorderColor ?? value.tableBorderColor
        value.ruleColor = document.ruleColor ?? value.ruleColor
        value.backgroundColor = document.backgroundColor ?? value.backgroundColor
        value.tableHeaderBackgroundColor = document.tableHeaderBackgroundColor ?? value.tableHeaderBackgroundColor
        if document.codeBackground != nil, var decoration = value.codeBlockDecoration {
            decoration.backgroundColor = document.codeBackground; value.codeBlockDecoration = decoration
        }
        if var decoration = value.blockquoteDecoration {
            decoration.backgroundColor = document.quoteBackground ?? decoration.backgroundColor
            decoration.borderColor = document.quoteBarColor ?? decoration.borderColor
            value.blockquoteDecoration = decoration
        }
        if let color = document.linkColor, var inline = value.linkStyle {
            inline.textColor = color; value.linkStyle = inline
        }
        if var inline = value.inlineCodeStyle {
            inline.textColor = document.inlineCodeTextColor ?? inline.textColor
            inline.backgroundColor = document.inlineCodeBackground ?? inline.backgroundColor
            value.inlineCodeStyle = inline
        }
        if let color = document.highlightColor, var inline = value.highlightStyle {
            inline.backgroundColor = color; value.highlightStyle = inline
        }
        if let color = document.tableBorderColor, var border = value.tableBorder {
            func recolored(_ side: MarkdownTableBorderSide?) -> MarkdownTableBorderSide? {
                guard var side else { return nil }
                side.color = color; return side
            }
            border.top = recolored(border.top); border.bottom = recolored(border.bottom)
            border.left = recolored(border.left); border.right = recolored(border.right)
            border.horizontalInside = recolored(border.horizontalInside); border.verticalInside = recolored(border.verticalInside)
            value.tableBorder = border
        }
        return value
    }
}
