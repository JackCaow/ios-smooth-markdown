import SwiftUI

/// Panel typography, colors, spacing, and decoration. Nil colors/fonts preserve platform defaults; zero border/divider width hides decoration.
public struct MarkdownPluginPanelTokens {
    public var outerPadding: EdgeInsets
    public var headerPadding: EdgeInsets
    public var contentPadding: EdgeInsets
    public var metadataPadding: EdgeInsets
    public var cornerRadius: CGFloat
    public var borderWidth: CGFloat
    public var borderColor: Color?
    public var backgroundColor: Color?
    public var headerBackgroundColor: Color?
    public var titleColor: Color?
    public var contentColor: Color?
    public var metadataColor: Color?
    public var accentColor: Color?
    public var titleFont: Font?
    public var contentFont: Font?
    public var metadataFont: Font?
    public var statusFont: Font?
    public var iconFont: Font?
    public var dividerThickness: CGFloat
    public var iconSpacing: CGFloat
    public var metadataSpacing: CGFloat
    public var minimumControlSize: CGFloat
    public var maximumContentHeight: CGFloat
    public var statusIndicatorSize: CGFloat
    public var sectionSpacing: CGFloat
    public var copyFeedbackSeconds: Double
    public var statusColors: [ToolCallStatus: Color]

    public init(outerPadding: EdgeInsets = EdgeInsets(),
                headerPadding: EdgeInsets = EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12),
                contentPadding: EdgeInsets = EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12),
                metadataPadding: EdgeInsets = EdgeInsets(),
                cornerRadius: CGFloat = 8,
                borderWidth: CGFloat = 1,
                borderColor: Color? = nil,
                backgroundColor: Color? = nil,
                headerBackgroundColor: Color? = nil,
                titleColor: Color? = nil,
                contentColor: Color? = nil,
                metadataColor: Color? = nil,
                accentColor: Color? = nil,
                titleFont: Font? = nil,
                contentFont: Font? = nil,
                metadataFont: Font? = nil,
                statusFont: Font? = nil,
                iconFont: Font? = nil,
                dividerThickness: CGFloat = 1,
                iconSpacing: CGFloat = 8,
                metadataSpacing: CGFloat = 2,
                minimumControlSize: CGFloat = 44,
                maximumContentHeight: CGFloat = 400,
                statusIndicatorSize: CGFloat = 8,
                sectionSpacing: CGFloat = 4,
                copyFeedbackSeconds: Double = 2,
                statusColors: [ToolCallStatus: Color] = [.running: Color(red: 0.96, green: 0.62, blue: 0.04), .completed: Color(red: 0.06, green: 0.73, blue: 0.51), .failed: .red, .cancelled: .gray, .pending: .blue]) {
        self.outerPadding = outerPadding
        self.headerPadding = headerPadding
        self.contentPadding = contentPadding
        self.metadataPadding = metadataPadding
        self.cornerRadius = max(0, cornerRadius.isFinite ? cornerRadius : 0)
        self.borderWidth = max(0, borderWidth.isFinite ? borderWidth : 0)
        self.borderColor = borderColor
        self.backgroundColor = backgroundColor
        self.headerBackgroundColor = headerBackgroundColor
        self.titleColor = titleColor
        self.contentColor = contentColor
        self.metadataColor = metadataColor
        self.accentColor = accentColor
        self.titleFont = titleFont
        self.contentFont = contentFont
        self.metadataFont = metadataFont
        self.statusFont = statusFont
        self.iconFont = iconFont
        self.dividerThickness = max(0, dividerThickness.isFinite ? dividerThickness : 0)
        self.iconSpacing = max(0, iconSpacing.isFinite ? iconSpacing : 0)
        self.metadataSpacing = max(0, metadataSpacing.isFinite ? metadataSpacing : 0)
        self.minimumControlSize = max(0, minimumControlSize.isFinite ? minimumControlSize : 0)
        self.maximumContentHeight = max(0, maximumContentHeight.isFinite ? maximumContentHeight : 0)
        self.statusIndicatorSize = max(0, statusIndicatorSize.isFinite ? statusIndicatorSize : 0)
        self.sectionSpacing = max(0, sectionSpacing.isFinite ? sectionSpacing : 0)
        self.copyFeedbackSeconds = max(0, copyFeedbackSeconds.isFinite ? copyFeedbackSeconds : 0)
        self.statusColors = statusColors
        self = normalized()
    }
}

/// Admonition semantic accents, title/body styles, spacing and decoration. Keys: note, tip, warning, danger, important, custom.
public struct MarkdownAdmonitionTokens {
    public var accentColors: [String: Color]
    public var outerPadding: EdgeInsets
    public var contentPadding: EdgeInsets
    public var contentSpacing: CGFloat
    public var cornerRadius: CGFloat
    public var borderWidth: CGFloat
    public var borderColor: Color?
    public var backgroundColor: Color?
    public var backgroundAlpha: Double
    public var accentWidth: CGFloat
    public var titleColor: Color?
    public var contentColor: Color?
    public var titleFont: Font?
    public var contentFont: Font?

    public init(accentColors: [String: Color] = ["note": .blue, "tip": .green, "warning": .orange, "danger": .red, "important": .purple, "custom": .blue],
                outerPadding: EdgeInsets = EdgeInsets(),
                contentPadding: EdgeInsets = EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12),
                contentSpacing: CGFloat = 6,
                cornerRadius: CGFloat = 6,
                borderWidth: CGFloat = 0,
                borderColor: Color? = nil,
                backgroundColor: Color? = nil,
                backgroundAlpha: Double = 0.08,
                accentWidth: CGFloat = 3,
                titleColor: Color? = nil,
                contentColor: Color? = nil,
                titleFont: Font? = nil,
                contentFont: Font? = nil) {
        self.accentColors = accentColors
        self.outerPadding = outerPadding
        self.contentPadding = contentPadding
        self.contentSpacing = max(0, contentSpacing.isFinite ? contentSpacing : 0)
        self.cornerRadius = max(0, cornerRadius.isFinite ? cornerRadius : 0)
        self.borderWidth = max(0, borderWidth.isFinite ? borderWidth : 0)
        self.borderColor = borderColor
        self.backgroundColor = backgroundColor
        self.backgroundAlpha = min(1, max(0, backgroundAlpha.isFinite ? backgroundAlpha : 0))
        self.accentWidth = max(0, accentWidth.isFinite ? accentWidth : 0)
        self.titleColor = titleColor
        self.contentColor = contentColor
        self.titleFont = titleFont
        self.contentFont = contentFont
        self = normalized()
    }
}

/// Public styles for opt-in built-in plugins. Theme values are scoped to each reader.
public struct MarkdownPluginTokens {
    public var mentionStyle: MarkdownInlineTextStyle
    public var hashtagStyle: MarkdownInlineTextStyle
    public var admonition: MarkdownAdmonitionTokens
    public var thinking: MarkdownPluginPanelTokens
    public var artifact: MarkdownPluginPanelTokens
    public var toolCall: MarkdownPluginPanelTokens

    public init(mentionStyle: MarkdownInlineTextStyle = MarkdownInlineTextStyle(textColor: .blue),
                hashtagStyle: MarkdownInlineTextStyle = MarkdownInlineTextStyle(textColor: .blue),
                admonition: MarkdownAdmonitionTokens = MarkdownAdmonitionTokens(),
                thinking: MarkdownPluginPanelTokens = MarkdownPluginPanelTokens(borderWidth: 0, dividerThickness: 0),
                artifact: MarkdownPluginPanelTokens = MarkdownPluginPanelTokens(),
                toolCall: MarkdownPluginPanelTokens = MarkdownPluginPanelTokens()) {
        self.mentionStyle = mentionStyle
        self.hashtagStyle = hashtagStyle
        self.admonition = admonition
        self.thinking = thinking
        self.artifact = artifact
        self.toolCall = toolCall
        self = normalized()
    }
}

private struct MarkdownDesignTokensKey: EnvironmentKey {
    static let defaultValue = MarkdownDesignTokens()
}

extension EnvironmentValues {
    var markdownDesignTokens: MarkdownDesignTokens {
        get { self[MarkdownDesignTokensKey.self] }
        set { self[MarkdownDesignTokensKey.self] = newValue.normalized() }
    }
}

struct MarkdownPluginInlineText: View {
    @Environment(\.markdownStrings) private var strings
    let text: String
    let mention: Bool
    @Environment(\.markdownDesignTokens) private var tokens
    var body: some View {
        let style = mention ? tokens.plugins.mentionStyle : tokens.plugins.hashtagStyle
        Text(text)
            .font(style.fontSize.map { .system(size: $0) })
            .foregroundColor(style.textColor)
            .background(style.backgroundColor ?? .clear)
            .bold(style.bold ?? false).italic(style.italic ?? false)
            .underline(style.underline ?? false).strikethrough(style.strikethrough ?? false)
            .monospaced(style.monospaced ?? false)
            .accessibilityLabel("\(mention ? strings["Mention"] : strings["Hashtag"]) \(text)")
    }
}

struct MarkdownAdmonitionCard: View {
    @Environment(\.markdownStrings) private var strings
    let type: String
    let title: String
    let content: String
    @Environment(\.markdownDesignTokens) private var designTokens
    var body: some View {
        let tokens = designTokens.plugins.admonition
        let accent = tokens.accentColors[type] ?? .accentColor
        VStack(alignment: .leading, spacing: tokens.contentSpacing) {
            Text(title == type.capitalized ? strings[title] : title).font(tokens.titleFont ?? .body.bold()).foregroundColor(tokens.titleColor ?? accent)
            if !content.isEmpty { Text(content).font(tokens.contentFont).foregroundColor(tokens.contentColor) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(tokens.contentPadding)
        .background(tokens.backgroundColor ?? accent.opacity(tokens.backgroundAlpha), in: RoundedRectangle(cornerRadius: tokens.cornerRadius))
        .overlay(alignment: .leading) { Rectangle().fill(accent).frame(width: tokens.accentWidth) }
        .overlay(RoundedRectangle(cornerRadius: tokens.cornerRadius).stroke(tokens.borderColor ?? accent, lineWidth: tokens.borderWidth))
        .padding(tokens.outerPadding)
        .accessibilityElement(children: .combine)
    }
}
