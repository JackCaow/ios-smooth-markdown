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

    enum Run: Equatable {
        case text(String, Style, [SafeHTML.Tag], code: Bool)
        case image(SafeHTML.ImageSpec)
    }

    static func runs(in node: Markup, enableHTML: Bool) -> [Run] {
        var result: [Run] = []
        var tags: [SafeHTML.Tag] = []
        append(node, style: Style(), tags: &tags, enableHTML: enableHTML, to: &result)
        return result
    }

    private static func append(
        _ node: Markup, style: Style, tags: inout [SafeHTML.Tag],
        enableHTML: Bool, to result: inout [Run]
    ) {
        for child in node.children {
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
                result.append(.text(text.string, style, tags, code: false))
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
                append(child, style: nested, tags: &tags, enableHTML: enableHTML, to: &result)
            }
        }
    }

    private static func plainText(_ node: Markup) -> String {
        if let text = node as? Markdown.Text { return text.string }
        if let code = node as? InlineCode { return code.code }
        return node.children.map(plainText).joined()
    }
}
