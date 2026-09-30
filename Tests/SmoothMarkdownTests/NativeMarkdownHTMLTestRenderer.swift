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
        let content = node.children.map(render).joined()
        let title = node.title.map { " title=\"" + escape($0) + "\"" } ?? ""
        switch node.kind {
        case .text: return escape(node.semanticText ?? node.source)
        case .inlineCode: return "<code>" + escape(node.semanticText ?? node.source) + "</code>"
        case .paragraph: return "<p>" + content + "</p>\n"
        case let .heading(level): return "<h\(level)>" + content + "</h\(level)>\n"
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
        default: return "UNSUPPORTED(\(node.kind))"
        }
    }
}
