import Foundation
@testable import SmoothMarkdown

/// A test adapter for comparing AST semantics with the official CommonMark HTML oracle.
enum NativeMarkdownHTMLTestRenderer {
    static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    static func destination(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~:/?#@!$&'()*+,;=%")
        return escape(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)
    }

    static func plainText(_ node: NativeMarkdownNode) -> String {
        if let text = node.semanticText { return text }
        if node.kind == .softBreak || node.kind == .hardBreak { return "\n" }
        return node.children.map(plainText).joined()
    }

    static func render(_ node: NativeMarkdownNode) -> String {
        render(node, tightList: false)
    }

    private static func render(_ node: NativeMarkdownNode, tightList: Bool) -> String {
        let content = node.children.map { render($0, tightList: false) }.joined()
        let title = node.title.map { " title=\"" + escape($0) + "\"" } ?? ""
        switch node.kind {
        case .text: return escape(node.semanticText ?? node.source)
        case .inlineCode: return "<code>" + escape(node.semanticText ?? node.source) + "</code>"
        case .paragraph: return "<p>" + content + "</p>\n"
        case let .heading(level): return "<h\(level)>" + content + "</h\(level)>\n"
        case .thematicBreak: return "<hr />\n"
        case .strong: return "<strong>" + content + "</strong>"
        case .emphasis: return "<em>" + content + "</em>"
        case .softBreak: return "\n"
        case .hardBreak: return "<br />\n"
        case .inlineHTML: return node.source
        case let .link(url): return "<a href=\"" + destination(url) + "\"" + title + ">" + content + "</a>"
        case let .image(url):
            return "<img src=\"" + destination(url) + "\" alt=\"" + escape(plainText(node)) + "\"" + title + " />"
        case .document: return content
        case .referenceDefinition: return ""
        case .htmlBlock: return node.source.hasSuffix("\n") ? node.source : node.source + "\n"
        case .blockQuote: return "<blockquote>\n" + content + "</blockquote>\n"
        case let .list(ordered):
            let tag = ordered ? "ol" : "ul"
            let start = ordered && node.listStart != nil && node.listStart != 1
                ? " start=\"\(node.listStart!)\"" : ""
            let items = node.children.map { render($0, tightList: node.isTight ?? true) }.joined()
            return "<\(tag)\(start)>\n" + items + "</\(tag)>\n"
        case .listItem:
            if node.children.isEmpty { return "<li></li>\n" }
            if !tightList { return "<li>\n" + content + "</li>\n" }
            let inline = node.children.prefix { !isBlock($0) }.map { render($0, tightList: false) }.joined()
            let blocks = node.children.dropFirst(node.children.prefix { !isBlock($0) }.count)
            let body = blocks.map { render($0, tightList: false) }.joined()
            if body.isEmpty { return "<li>" + inline + "</li>\n" }
            return "<li>" + inline + (inline.isEmpty ? "\n" : "\n") + body + "</li>\n"
        default: return "UNSUPPORTED(\(node.kind))"
        }
    }

    private static func isBlock(_ node: NativeMarkdownNode) -> Bool {
        switch node.kind {
        case .paragraph, .heading, .fencedCode, .indentedCode, .thematicBreak,
             .blockQuote, .list, .htmlBlock, .raw: return true
        default: return false
        }
    }
}
