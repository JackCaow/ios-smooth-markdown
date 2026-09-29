import Markdown
import SwiftUI

/// A host-supplied renderer for a parsed Markdown node.
public protocol MarkdownWidgetBuilder {
    /// Allows a builder registered under another key to handle this node too.
    func canBuild(_ node: Markup) -> Bool

    /// Builds the replacement view. Render nested block nodes with `context.renderBlock`.
    func build(_ node: Markup, context: MarkdownRenderContext) -> AnyView

    /// Matches a parser-plugin result. Default is false for builders of ordinary Markdown nodes.
    func canBuild(_ node: MarkdownPluginNode) -> Bool

    /// Replaces a parser-plugin view when `canBuild` accepts its result.
    func build(_ node: MarkdownPluginNode, context: MarkdownRenderContext) -> AnyView
}

public extension MarkdownWidgetBuilder {
    func canBuild(_ node: MarkdownPluginNode) -> Bool { false }
    func build(_ node: MarkdownPluginNode, context: MarkdownRenderContext) -> AnyView {
        AnyView(Text(node.source))
    }
}

/// A plugin result before its plugin's SwiftUI `render` method is called.
public struct MarkdownPluginNode {
    public enum Kind { case inline, block }

    public let kind: Kind
    public let type: String
    public let source: String
    public let content: String
    public let attributes: [String: String]

    public init(plugin: any InlineParserPlugin, match: InlinePluginMatch) {
        kind = .inline
        type = plugin.id
        source = match.text
        content = match.text
        attributes = match.attributes
    }

    public init(plugin: any BlockParserPlugin, match: BlockPluginMatch) {
        kind = .block
        type = plugin.id
        source = match.source
        content = match.content
        attributes = match.attributes
    }
}

/// Inherited Markdown formatting at an inline override point.
public struct MarkdownInlineStyle {
    public let bold: Bool
    public let italic: Bool
    public let strike: Bool
    public let link: URL?

    public init(bold: Bool = false, italic: Bool = false, strike: Bool = false, link: URL? = nil) {
        self.bold = bold
        self.italic = italic
        self.strike = strike
        self.link = link
    }
}

/// Information and nested rendering available to a custom builder.
public struct MarkdownRenderContext {
    public let styleSheet: MarkdownStyleSheet
    public let selectable: Bool
    public let renderBlock: (Markup) -> AnyView
    /// Renders an inline container's children through this reader and registry.
    public let renderInline: ((Markup) -> AnyView)?
    /// Renders plugin-provided Markdown content through this reader and registry.
    public let renderMarkdown: ((String) -> AnyView)?
    public let inlineStyle: MarkdownInlineStyle?

    public init(styleSheet: MarkdownStyleSheet, selectable: Bool,
                renderBlock: @escaping (Markup) -> AnyView,
                renderInline: ((Markup) -> AnyView)? = nil,
                renderMarkdown: ((String) -> AnyView)? = nil,
                inlineStyle: MarkdownInlineStyle? = nil) {
        self.styleSheet = styleSheet
        self.selectable = selectable
        self.renderBlock = renderBlock
        self.renderInline = renderInline
        self.renderMarkdown = renderMarkdown
        self.inlineStyle = inlineStyle
    }
}

/// Mutable, insertion-ordered registry matching Flutter's exact-key-then-`canBuild` lookup.
/// An empty registry keeps every native renderer; registering one type overrides only its matches.
public final class BuilderRegistry {
    private var builders: [String: any MarkdownWidgetBuilder] = [:]
    private var keys: [String] = []

    public init() {}

    public func register(_ nodeType: String, builder: any MarkdownWidgetBuilder) {
        if builders[nodeType] == nil { keys.append(nodeType) }
        builders[nodeType] = builder
    }

    public func unregister(_ nodeType: String) {
        builders.removeValue(forKey: nodeType)
        keys.removeAll { $0 == nodeType }
    }

    public func clear() {
        builders.removeAll()
        keys.removeAll()
    }

    public func hasBuilder(_ nodeType: String) -> Bool { builders[nodeType] != nil }

    public func getBuilder(_ nodeType: String) -> (any MarkdownWidgetBuilder)? { builders[nodeType] }

    public func findBuilder(_ node: Markup) -> (any MarkdownWidgetBuilder)? {
        if let exact = builders[Self.nodeType(for: node)], exact.canBuild(node) { return exact }
        for key in keys {
            if let builder = builders[key], builder.canBuild(node) { return builder }
        }
        return nil
    }

    public func findBuilder(_ node: MarkdownPluginNode) -> (any MarkdownWidgetBuilder)? {
        if let exact = builders[node.type], exact.canBuild(node) { return exact }
        for key in keys {
            if let builder = builders[key], builder.canBuild(node) { return builder }
        }
        return nil
    }

    /// Flutter-compatible keys for parsed Markdown nodes supported by the native reader.
    public static func nodeType(for node: Markup) -> String {
        switch node {
        case is Markdown.Text: "text"
        case is Heading: "header"
        case is Paragraph: "paragraph"
        case is CodeBlock: "code_block"
        case is InlineCode: "inline_code"
        case is Strong: "bold"
        case is Emphasis: "italic"
        case is Strikethrough: "strikethrough"
        case is Markdown.Link: "link"
        case is Markdown.Image: "image"
        case is LineBreak: "hard_break"
        case is Markdown.ListItem: "list_item"
        case is BlockQuote: "blockquote"
        case is OrderedList, is UnorderedList: "list"
        case is Markdown.Table: "table"
        case is ThematicBreak: "horizontal_rule"
        case is HTMLBlock: "html_block"
        default: String(describing: type(of: node))
        }
    }
}
