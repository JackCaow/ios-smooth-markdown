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

    /// Matches a native extension parsed outside swift-markdown's Markup tree.
    func canBuild(_ node: MarkdownExtensionNode) -> Bool

    /// Replaces an extension node such as math, a footnote, or details.
    func build(_ node: MarkdownExtensionNode, context: MarkdownRenderContext) -> AnyView
}

public extension MarkdownWidgetBuilder {
    func canBuild(_ node: MarkdownPluginNode) -> Bool { false }
    func build(_ node: MarkdownPluginNode, context: MarkdownRenderContext) -> AnyView {
        AnyView(Text(node.source))
    }
    func canBuild(_ node: MarkdownExtensionNode) -> Bool { false }
    func build(_ node: MarkdownExtensionNode, context: MarkdownRenderContext) -> AnyView {
        AnyView(Text(node.source))
    }
}

/// A parsed extension that has no corresponding swift-markdown `Markup` node.
/// `content` is the inner formula or Markdown body; `source` is normalized
/// Markdown spelling and may differ from the author's original whitespace.
public struct MarkdownExtensionNode {
    public enum Kind { case inline, block }

    public let kind: Kind
    public let type: String
    public let source: String
    public let content: String
    public let attributes: [String: String]

    public init(kind: Kind, type: String, source: String, content: String,
                attributes: [String: String] = [:]) {
        self.kind = kind
        self.type = type
        self.source = source
        self.content = content
        self.attributes = attributes
    }

    public static func inlineMath(_ latex: String) -> Self {
        .init(kind: .inline, type: "inline_math", source: "$\(latex)$", content: latex)
    }

    public static func blockMath(_ latex: String) -> Self {
        .init(kind: .block, type: "block_math", source: "$$\n\(latex)\n$$", content: latex)
    }

    public static func footnoteReference(_ label: String) -> Self {
        .init(kind: .inline, type: "footnote_reference", source: "[^\(label)]", content: label,
              attributes: ["label": label])
    }

    public static func footnoteDefinition(label: String, content: String) -> Self {
        .init(kind: .block, type: "footnote_definition", source: "[^\(label)]: \(content)",
              content: content, attributes: ["label": label])
    }

    public static func details(summary: String, content: String, isOpen: Bool) -> Self {
        .init(kind: .block, type: "details", source: "<details\(isOpen ? " open" : "")>\n<summary>\(summary)</summary>\n\(content)\n</details>",
              content: content, attributes: ["summary": summary, "open": isOpen ? "true" : "false"])
    }

    /// A rendered HTML style run. Raw opening/closing tags are stateful parser
    /// tokens, so builders receive their styled text instead of a token alone.
    public static func htmlStyle(type: String, tag: String, text: String,
                                 attributes: [String: String] = [:]) -> Self {
        var attributes = attributes
        attributes["tag"] = tag
        return .init(kind: .inline, type: type, source: text, content: text,
                     attributes: attributes)
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

    public func findBuilder(_ node: MarkdownExtensionNode) -> (any MarkdownWidgetBuilder)? {
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
