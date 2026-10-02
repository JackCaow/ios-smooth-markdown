import SwiftUI

/// All public configuration uses one policy: invalid dimensions become zero,
/// opacity is clamped to 0...1, and invalid positive font/line-height values use defaults.
/// Values are normalized again at renderer boundaries, including values mutated after init.
enum MarkdownTokenValidation {
    static func dimension<T: BinaryFloatingPoint>(_ value: T) -> T { value.isFinite ? max(0, value) : 0 }
    static func finite<T: BinaryFloatingPoint>(_ value: T) -> T { value.isFinite ? value : 0 }
    static func opacity<T: BinaryFloatingPoint>(_ value: T) -> T { min(1, dimension(value)) }
    static func positive<T: BinaryFloatingPoint>(_ value: T, fallback: T) -> T {
        value.isFinite && value > 0 ? value : fallback
    }
    static func insets(_ value: EdgeInsets) -> EdgeInsets {
        .init(top: dimension(value.top), leading: dimension(value.leading), bottom: dimension(value.bottom), trailing: dimension(value.trailing))
    }
}

public extension MarkdownDesignTokens {
    /// Returns a safe copy without altering the caller's configuration.
    func normalized() -> Self {
        var value = self
        value.typography = typography.normalized()
        value.heading = heading.normalized()
        value.quote = quote.normalized()
        value.code = code.normalized()
        value.link = link.normalized()
        value.details = details.normalized()
        value.keyboard = keyboard.normalized()
        value.math = math.normalized()
        value.plugins = plugins.normalized()
        value.mermaid = mermaid.normalized()
        value.footnotePadding = MarkdownTokenValidation.insets(footnotePadding)
        value.imagePlaceholderMinSize = MarkdownTokenValidation.dimension(imagePlaceholderMinSize)
        return value
    }
}

public extension MarkdownHeadingTokens {
    /// Returns a safe copy without altering the caller's configuration.
    func normalized() -> Self {
        var value = self
        value.decoratedThroughLevel = min(6, max(0, decoratedThroughLevel))
        value.padding = MarkdownTokenValidation.insets(padding)
        value.barWidth = MarkdownTokenValidation.dimension(barWidth)
        value.barRadius = MarkdownTokenValidation.dimension(barRadius)
        value.barSpacing = MarkdownTokenValidation.dimension(barSpacing)
        value.barEndAlpha = MarkdownTokenValidation.opacity(barEndAlpha)
        value.ruleThickness = MarkdownTokenValidation.dimension(ruleThickness)
        value.ruleStartAlpha = MarkdownTokenValidation.opacity(ruleStartAlpha)
        value.ruleEndAlpha = MarkdownTokenValidation.opacity(ruleEndAlpha)
        return value
    }
}

public extension MarkdownQuoteTokens {
    /// Returns a safe copy without altering the caller's configuration.
    func normalized() -> Self {
        var value = self
        value.borderAlpha = MarkdownTokenValidation.opacity(borderAlpha)
        value.iconAlpha = MarkdownTokenValidation.opacity(iconAlpha)
        value.iconTypography = iconTypography?.normalized()
        value.iconSize = MarkdownTokenValidation.dimension(iconSize)
        value.iconSpacing = MarkdownTokenValidation.dimension(iconSpacing)
        value.cornerRadius = MarkdownTokenValidation.dimension(cornerRadius)
        value.shadowRadius = MarkdownTokenValidation.dimension(shadowRadius)
        value.shadowX = MarkdownTokenValidation.finite(shadowX)
        value.shadowY = MarkdownTokenValidation.finite(shadowY)
        return value
    }
}

public extension MarkdownSyntaxColors {
    /// Returns a safe copy without altering the caller's configuration.
    func normalized() -> Self { self }
}

public extension MarkdownCodeTokens {
    /// Returns a safe copy without altering the caller's configuration.
    func normalized() -> Self {
        var value = self
        value.headerPadding = MarkdownTokenValidation.insets(headerPadding)
        value.headerSpacing = MarkdownTokenValidation.dimension(headerSpacing)
        value.languagePadding = MarkdownTokenValidation.insets(languagePadding)
        value.languageCornerRadius = MarkdownTokenValidation.dimension(languageCornerRadius)
        value.languageBackgroundAlpha = MarkdownTokenValidation.opacity(languageBackgroundAlpha)
        value.copyPadding = MarkdownTokenValidation.insets(copyPadding)
        value.copyCornerRadius = MarkdownTokenValidation.dimension(copyCornerRadius)
        value.copyBackgroundAlpha = MarkdownTokenValidation.opacity(copyBackgroundAlpha)
        value.copiedBackgroundAlpha = MarkdownTokenValidation.opacity(copiedBackgroundAlpha)
        value.copyFeedbackSeconds = MarkdownTokenValidation.dimension(copyFeedbackSeconds)
        value.syntaxColors = syntaxColors?.normalized()
        return value
    }
}

public extension MarkdownLinkTokens {
    /// Returns a safe copy without altering the caller's configuration.
    func normalized() -> Self {
        var value = self
        value.iconSize = MarkdownTokenValidation.dimension(iconSize)
        value.iconGap = MarkdownTokenValidation.dimension(iconGap)
        value.iconTopOffset = MarkdownTokenValidation.finite(iconTopOffset)
        return value
    }
}

public extension MarkdownDetailsTokens {
    /// Returns a safe copy without altering the caller's configuration.
    func normalized() -> Self {
        var value = self
        value.cornerRadius = MarkdownTokenValidation.dimension(cornerRadius)
        value.outerPadding = MarkdownTokenValidation.insets(outerPadding)
        value.borderWidth = MarkdownTokenValidation.dimension(borderWidth)
        value.summaryPadding = MarkdownTokenValidation.insets(summaryPadding)
        value.bodyPadding = MarkdownTokenValidation.insets(bodyPadding)
        value.iconSpacing = MarkdownTokenValidation.dimension(iconSpacing)
        value.iconWidth = MarkdownTokenValidation.dimension(iconWidth)
        value.dividerThickness = MarkdownTokenValidation.dimension(dividerThickness)
        return value
    }
}

public extension MarkdownKeyboardTokens {
    /// Returns a safe copy without altering the caller's configuration.
    func normalized() -> Self {
        var value = self
        value.borderWidth = MarkdownTokenValidation.dimension(borderWidth)
        value.cornerRadius = MarkdownTokenValidation.dimension(cornerRadius)
        value.padding = MarkdownTokenValidation.insets(padding)
        value.fontSize = MarkdownTokenValidation.positive(fontSize, fallback: 17)
        value.backgroundAlpha = MarkdownTokenValidation.opacity(backgroundAlpha)
        return value
    }
}

public extension MarkdownMathTokens {
    /// Returns a safe copy without altering the caller's configuration.
    func normalized() -> Self {
        var value = self
        value.inlineFontSize = MarkdownTokenValidation.positive(inlineFontSize, fallback: 16)
        value.displayScale = MarkdownTokenValidation.positive(displayScale, fallback: 1.25)
        value.fontFamily = ["serif", "sans-serif", "monospace"].contains(fontFamily) ? fontFamily : "serif"
        value.blockPadding = MarkdownTokenValidation.insets(blockPadding)
        return value
    }
}

public extension MarkdownFontToken {
    /// Returns a safe copy without altering the caller's configuration.
    func normalized() -> Self {
        var value = self
        value.size = MarkdownTokenValidation.positive(size, fallback: 17)
        return value
    }
}

public extension MarkdownTypographyTokens {
    /// Returns a safe copy without altering the caller's configuration.
    func normalized() -> Self {
        var value = self
        value.paragraph = paragraph?.normalized()
        value.headings = headings.flatMap { fonts in fonts.isEmpty ? nil : (0..<6).map { fonts[min($0, fonts.count - 1)].normalized() } }
        value.paragraphLineHeight = MarkdownTokenValidation.positive(paragraphLineHeight, fallback: 1.5)
        value.headingLineHeights = (0..<6).map { index in MarkdownTokenValidation.positive(headingLineHeights.indices.contains(index) ? headingLineHeights[index] : (index < 2 ? 1.3 : 1.4), fallback: index < 2 ? 1.3 : 1.4) }
        return value
    }
}

public extension MarkdownPluginPanelTokens {
    /// Returns a safe copy without altering the caller's configuration.
    func normalized() -> Self {
        var value = self
        value.outerPadding = MarkdownTokenValidation.insets(outerPadding)
        value.headerPadding = MarkdownTokenValidation.insets(headerPadding)
        value.contentPadding = MarkdownTokenValidation.insets(contentPadding)
        value.metadataPadding = MarkdownTokenValidation.insets(metadataPadding)
        value.cornerRadius = MarkdownTokenValidation.dimension(cornerRadius)
        value.borderWidth = MarkdownTokenValidation.dimension(borderWidth)
        value.dividerThickness = MarkdownTokenValidation.dimension(dividerThickness)
        value.iconSpacing = MarkdownTokenValidation.dimension(iconSpacing)
        value.metadataSpacing = MarkdownTokenValidation.dimension(metadataSpacing)
        value.minimumControlSize = MarkdownTokenValidation.dimension(minimumControlSize)
        value.maximumContentHeight = MarkdownTokenValidation.dimension(maximumContentHeight)
        value.statusIndicatorSize = MarkdownTokenValidation.dimension(statusIndicatorSize)
        value.sectionSpacing = MarkdownTokenValidation.dimension(sectionSpacing)
        value.copyFeedbackSeconds = MarkdownTokenValidation.dimension(copyFeedbackSeconds)
        return value
    }
}

public extension MarkdownAdmonitionTokens {
    /// Returns a safe copy without altering the caller's configuration.
    func normalized() -> Self {
        var value = self
        value.outerPadding = MarkdownTokenValidation.insets(outerPadding)
        value.contentPadding = MarkdownTokenValidation.insets(contentPadding)
        value.contentSpacing = MarkdownTokenValidation.dimension(contentSpacing)
        value.cornerRadius = MarkdownTokenValidation.dimension(cornerRadius)
        value.borderWidth = MarkdownTokenValidation.dimension(borderWidth)
        value.backgroundAlpha = MarkdownTokenValidation.opacity(backgroundAlpha)
        value.accentWidth = MarkdownTokenValidation.dimension(accentWidth)
        return value
    }
}

public extension MarkdownPluginTokens {
    /// Returns a safe copy without altering the caller's configuration.
    func normalized() -> Self {
        var value = self
        value.mentionStyle = mentionStyle.normalized()
        value.hashtagStyle = hashtagStyle.normalized()
        value.admonition = admonition.normalized()
        value.thinking = thinking.normalized()
        value.artifact = artifact.normalized()
        value.toolCall = toolCall.normalized()
        return value
    }
}

public extension MarkdownMermaidTokens {
    /// Returns a safe copy without altering the caller's configuration.
    func normalized() -> Self {
        var value = self
        value.outerPadding = MarkdownTokenValidation.insets(outerPadding)
        value.maxHeight = MarkdownTokenValidation.positive(maxHeight, fallback: 420)
        return value
    }
}

public extension MarkdownInlineTextStyle {
    func normalized() -> Self {
        var value = self
        value.fontSize = fontSize.map { MarkdownTokenValidation.positive($0, fallback: 17) }
        return value
    }
}

public extension MarkdownStyleSheet {
    /// Resolution order: explicit semantic decoration/inline style, legacy fallback,
    /// then platform default. Component designTokens govern component chrome;
    /// explicit typography tokens override opaque legacy paragraph/heading fonts.
    func normalized() -> Self {
        var value = self
        value.designTokens = designTokens.normalized()
        value.blockSpacing = MarkdownTokenValidation.dimension(blockSpacing)
        value.contentPadding = MarkdownTokenValidation.dimension(contentPadding)
        value.quoteSpacing = MarkdownTokenValidation.dimension(quoteSpacing)
        value.listSpacing = MarkdownTokenValidation.dimension(listSpacing)
        value.listIndent = MarkdownTokenValidation.dimension(listIndent)
        value.codePadding = MarkdownTokenValidation.dimension(codePadding)
        value.tableCellPadding = MarkdownTokenValidation.dimension(tableCellPadding)
        value.horizontalRuleThickness = MarkdownTokenValidation.dimension(horizontalRuleThickness)
        value.blockquotePadding = MarkdownTokenValidation.insets(blockquotePadding)
        value.codeBlockPadding = codeBlockPadding.map(MarkdownTokenValidation.insets)
        if var quote = blockquoteDecoration {
            quote.borderWidth = MarkdownTokenValidation.dimension(quote.borderWidth)
            value.blockquoteDecoration = quote
        }
        if var code = codeBlockDecoration {
            code.borderWidth = MarkdownTokenValidation.dimension(code.borderWidth)
            code.cornerRadius = MarkdownTokenValidation.dimension(code.cornerRadius)
            value.codeBlockDecoration = code
        }
        value.boldStyle = boldStyle?.normalized(); value.italicStyle = italicStyle?.normalized()
        value.strikethroughStyle = strikethroughStyle?.normalized(); value.linkStyle = linkStyle?.normalized()
        value.inlineCodeStyle = inlineCodeStyle?.normalized(); value.subscriptStyle = subscriptStyle?.normalized()
        value.superscriptStyle = superscriptStyle?.normalized(); value.kbdStyle = kbdStyle?.normalized()
        value.underlineStyle = underlineStyle?.normalized(); value.highlightStyle = highlightStyle?.normalized()
        value.smallStyle = smallStyle?.normalized()
        if var border = tableBorder {
            func safe(_ side: MarkdownTableBorderSide?) -> MarkdownTableBorderSide? {
                guard var side else { return nil }
                side.width = MarkdownTokenValidation.dimension(side.width); return side
            }
            border.top = safe(border.top); border.bottom = safe(border.bottom)
            border.left = safe(border.left); border.right = safe(border.right)
            border.horizontalInside = safe(border.horizontalInside); border.verticalInside = safe(border.verticalInside)
            value.tableBorder = border
        }
        return value
    }
}
