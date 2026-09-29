import Markdown
import SwiftUI

/// A host-supplied renderer for a parsed Markdown node.
public protocol MarkdownWidgetBuilder {
    /// Allows a builder registered under another key to handle this node too.
    func canBuild(_ node: Markup) -> Bool

    /// Builds the replacement view. Render nested block nodes with `context.renderBlock`.
    func build(_ node: Markup, context: MarkdownRenderContext) -> AnyView
}

/// Information and nested rendering available to a custom builder.
public struct MarkdownRenderContext {
    public let styleSheet: MarkdownStyleSheet
    public let selectable: Bool
    public let renderBlock: (Markup) -> AnyView

    public init(styleSheet: MarkdownStyleSheet, selectable: Bool,
                renderBlock: @escaping (Markup) -> AnyView) {
        self.styleSheet = styleSheet
        self.selectable = selectable
        self.renderBlock = renderBlock
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

    /// Flutter-compatible keys for the block nodes supported by the native reader.
    public static func nodeType(for node: Markup) -> String {
        switch node {
        case is Heading: "header"
        case is Paragraph: "paragraph"
        case is CodeBlock: "code_block"
        case is BlockQuote: "blockquote"
        case is OrderedList, is UnorderedList: "list"
        case is Markdown.Table: "table"
        case is ThematicBreak: "horizontal_rule"
        case is HTMLBlock: "html_block"
        default: String(describing: type(of: node))
        }
    }
}
