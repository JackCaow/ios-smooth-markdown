import Foundation
import Markdown

/// Keeps image nodes in their original position among styled inline text.
enum InlineContent {
    struct Style: Equatable {
        var bold = false
        var italic = false
        var strike = false
        var link: URL?
    }

    enum Run {
        case text(String, Style, [SafeHTML.Tag], code: Bool)
        case image(SafeHTML.ImageSpec)
        case footnote(String)
        case math(String)
        case plugin(any InlineParserPlugin, InlinePluginMatch)
    }

    static func runs(in node: Markup, enableHTML: Bool, plugins: ParserPluginRegistry? = nil) -> [Run] {
        var result: [Run] = []
        var tags: [SafeHTML.Tag] = []
        append(node, style: Style(), tags: &tags, enableHTML: enableHTML, plugins: plugins, to: &result)
        return result
    }

    private static func append(
        _ node: Markup, style: Style, tags: inout [SafeHTML.Tag],
        enableHTML: Bool, plugins: ParserPluginRegistry?, to result: inout [Run]
    ) {
        for child in node.children {
            // Flutter treats the body of an HTML <code> tag as one verbatim inline
            // span. swift-markdown has already parsed markers such as **bold**
            // into child nodes, so reconstruct their Markdown spelling here.
            if enableHTML, tags.contains(where: { $0.name == "code" }) {
                if let html = child as? InlineHTML,
                   let tag = SafeHTML.lexTag(html.rawHTML), tag.name == "code",
                   tag.isClosing, tag.end == (html.rawHTML as NSString).length {
                    if let match = tags.lastIndex(where: { $0.name == "code" }) {
                        tags.removeSubrange(match...)
                    }
                } else {
                    let raw = (child as? Markdown.Text)?.string ?? child.format()
                    result.append(.text(raw, style, tags, code: true))
                }
                continue
            }
            if let html = child as? InlineHTML {
                if enableHTML, let tag = SafeHTML.lexTag(html.rawHTML),
                   tag.end == (html.rawHTML as NSString).length {
                    if tag.isClosing {
                        if let match = tags.lastIndex(where: { $0.name == tag.name }) {
                            tags.removeSubrange(match...)
                        }
                    } else if SafeHTML.voidTags.contains(tag.name) {
                        if tag.name == "br" {
                            result.append(.text("\n", style, tags, code: false))
                        } else if tag.name == "img" {
                            if let image = SafeHTML.imageTag(html.rawHTML) {
                                result.append(.image(image))
                            } else if let alt = tag.attributes["alt"], !alt.isEmpty {
                                result.append(.text(alt, style, tags, code: false))
                            }
                        }
                    } else if !tag.isSelfClosing {
                        tags.append(tag)
                    }
                } else {
                    result.append(.text(html.rawHTML, style, tags, code: false))
                }
                continue
            }
            if let text = child as? Markdown.Text {
                for pluginPart in PluginInlineSyntax.parts(in: text.string, registry: plugins) {
                    switch pluginPart {
                    case let .plugin(plugin, match): result.append(.plugin(plugin, match))
                    case let .text(source):
                        for part in FootnoteSyntax.parts(in: source) {
                            switch part {
                            case let .text(value):
                                for math in MathSyntax.inlineParts(in: value) {
                                    switch math {
                                    case let .text(plain): result.append(.text(plain, style, tags, code: false))
                                    case let .math(latex): result.append(.math(latex))
                                    }
                                }
                            case let .reference(label): result.append(.footnote(label))
                            }
                        }
                    }
                }
            } else if let code = child as? InlineCode {
                result.append(.text(code.code, style, tags, code: true))
            } else if child is SoftBreak || child is LineBreak {
                result.append(.text("\n", style, tags, code: false))
            } else if let image = child as? Markdown.Image {
                if let source = image.source, SafeHTML.isSafeImageSource(source) {
                    result.append(.image(.init(source: source, alt: plainText(image), title: image.title, width: nil, height: nil)))
                } else {
                    result.append(.text(plainText(image), style, tags, code: false))
                }
            } else {
                var nested = style
                if child is Strong { nested.bold = true }
                if child is Emphasis { nested.italic = true }
                if child is Strikethrough { nested.strike = true }
                if let link = child as? Markdown.Link, let destination = link.destination,
                   let url = URL(string: destination), MarkdownSyntax.isSafeLink(url) {
                    nested.link = url
                }
                append(child, style: nested, tags: &tags, enableHTML: enableHTML, plugins: plugins, to: &result)
            }
        }
    }

    private static func plainText(_ node: Markup) -> String {
        if let text = node as? Markdown.Text { return text.string }
        if let code = node as? InlineCode { return code.code }
        return node.children.map(plainText).joined()
    }
}
