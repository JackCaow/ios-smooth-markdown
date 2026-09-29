import Foundation
import Markdown

/// Swift Markdown parses Markdown markers inside HTML code tags. Restore the
/// original source of those children before the reader builds inline runs.
enum HTMLCodeLiteralSyntax {
    static func restore(_ document: Document, source: String) -> Document {
        let sourceBytes = Array(source.utf8)
        var lineStarts = [0]
        for (index, byte) in sourceBytes.enumerated() where byte == 0x0A {
            lineStarts.append(index + 1)
        }
        return rewrite(document, bytes: sourceBytes, lineStarts: lineStarts) as? Document ?? document
    }

    private static func rewrite(_ node: Markup, bytes: [UInt8], lineStarts: [Int]) -> Markup {
        let children = Array(node.children)
        guard !children.isEmpty else { return node }
        var result: [Markup] = []
        var changed = false
        var index = 0
        while index < children.count {
            let child = children[index]
            guard isOpeningCode(child) else {
                let rewritten = rewrite(child, bytes: bytes, lineStarts: lineStarts)
                if !rewritten.isIdentical(to: child) { changed = true }
                result.append(rewritten)
                index += 1
                continue
            }
            changed = true
            let close = ((index + 1)..<children.count).first { isClosingCode(children[$0]) }
            let end = close ?? children.count
            let content = ((index + 1)..<end).map { partIndex in
                let part = children[partIndex]
                if part is SoftBreak || part is LineBreak {
                    return sourceBreak(after: children[partIndex - 1], bytes: bytes,
                                       lineStarts: lineStarts) ?? "\n"
                }
                return sourceText(for: part, bytes: bytes, lineStarts: lineStarts) ?? part.format()
            }.joined()
            result.append(InlineCode(content))
            index = end + (close == nil ? 0 : 1)
        }
        return changed ? node.withUncheckedChildren(result) : node
    }

    private static func isOpeningCode(_ node: Markup) -> Bool {
        guard let html = node as? InlineHTML,
              let tag = SafeHTML.lexTag(html.rawHTML),
              tag.end == (html.rawHTML as NSString).length else { return false }
        return tag.name == "code" && !tag.isClosing && !tag.isSelfClosing
    }

    private static func isClosingCode(_ node: Markup) -> Bool {
        guard let html = node as? InlineHTML,
              let tag = SafeHTML.lexTag(html.rawHTML),
              tag.end == (html.rawHTML as NSString).length else { return false }
        return tag.name == "code" && tag.isClosing
    }

    private static func sourceText(for node: Markup, bytes: [UInt8], lineStarts: [Int]) -> String? {
        guard let range = node.range,
              let start = offset(range.lowerBound, bytes: bytes, lineStarts: lineStarts),
              let end = offset(range.upperBound, bytes: bytes, lineStarts: lineStarts),
              start <= end else { return nil }
        return String(decoding: bytes[start..<end], as: UTF8.self)
    }

    private static func sourceBreak(after node: Markup, bytes: [UInt8], lineStarts: [Int]) -> String? {
        guard let upper = node.range?.upperBound,
              let start = offset(upper, bytes: bytes, lineStarts: lineStarts),
              start < bytes.count,
              let newline = bytes[start...].firstIndex(of: 0x0A) else { return nil }
        // Keep a backslash or hard-break spaces before the newline. Container
        // markers after it (for example `> `) belong to the surrounding block.
        return String(decoding: bytes[start...newline], as: UTF8.self)
    }

    private static func offset(_ location: SourceLocation, bytes: [UInt8], lineStarts: [Int]) -> Int? {
        guard location.line > 0, location.line <= lineStarts.count, location.column > 0 else { return nil }
        let offset = lineStarts[location.line - 1] + location.column - 1
        return offset <= bytes.count ? offset : nil
    }
}
