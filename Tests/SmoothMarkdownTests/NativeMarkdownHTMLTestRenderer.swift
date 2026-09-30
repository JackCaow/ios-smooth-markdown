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
        case .strikethrough: return "<del>" + content + "</del>"
        case .emphasis: return "<em>" + content + "</em>"
        case .softBreak: return "\n"
        case .hardBreak: return "<br />\n"
        case .inlineHTML: return node.semanticText ?? node.source
        case let .link(url): return "<a href=\"" + destination(url) + "\"" + title + ">" + content + "</a>"
        case let .image(url):
            return "<img src=\"" + destination(url) + "\" alt=\"" + escape(plainText(node)) + "\"" + title + " />"
        case .document: return content
        case .referenceDefinition: return ""
        case let .fencedCode(info):
            let language = info.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
            let attribute = language.isEmpty ? "" : " class=\"language-" + escape(language) + "\""
            return "<pre><code" + attribute + ">" + escape(node.semanticText ?? "") + "</code></pre>\n"
        case .indentedCode: return "<pre><code>" + escape(node.semanticText ?? "") + "</code></pre>\n"
        case .htmlBlock:
            let html = node.semanticText ?? node.source
            return html.hasSuffix("\n") ? html : html + "\n"
        case .table:
            func row(_ row: NativeMarkdownNode, header: Bool) -> String {
                let tag = header ? "th" : "td"
                let cells = row.children.enumerated().map { index, cell in
                    let alignment = index < node.tableAlignments.count ? node.tableAlignments[index] : nil
                    let attribute = alignment.map { " align=\"" + $0 + "\"" } ?? ""
                    return "<" + tag + attribute + ">" + cell.children.map(render).joined() + "</" + tag + ">\n"
                }.joined()
                return "<tr>\n" + cells + "</tr>\n"
            }
            guard let header = node.children.first else { return "" }
            let body = node.children.dropFirst().map { row($0, header: false) }.joined()
            return "<table>\n<thead>\n" + row(header, header: true) + "</thead>\n" + (body.isEmpty ? "" : "<tbody>\n" + body + "</tbody>\n") + "</table>\n"
        case .thematicBreak: return "<hr />\n"
        default: return "UNSUPPORTED(\(node.kind))"
        }
    }
}
