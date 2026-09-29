import Foundation
import Markdown

/// Markdown blocks that can share one native selection surface.
struct ReaderSelectionDocument {
    /// A selectable anchor for a visually drawn thematic break. Removed on copy.
    static let ruleAnchor = "\u{FFFC}"
    struct Run: Equatable {
        let text: String
        let style: InlineContent.Style
        let code: Bool
    }

    struct Line: Equatable {
        enum Kind: Equatable { case paragraph, heading(Int), list, quote, rule }
        let kind: Kind
        let runs: [Run]
        let indent: Int
        let quoteDepth: Int
        /// IDs of enclosing quote blocks, from the outermost to the innermost.
        let quoteIDs: [Int]
    }

    let lines: [Line]

    var copiedText: String {
        lines.map { $0.kind == .rule ? "" : $0.runs.map(\.text).joined() }.joined(separator: "\n")
    }

    static func compose(_ nodes: [Markup], enableHTML: Bool, plugins: ParserPluginRegistry?) -> ReaderSelectionDocument? {
        var lines: [Line] = []
        var nextQuoteID = 0
        for node in nodes {
            guard let part = linesForBlock(node, enableHTML: enableHTML, plugins: plugins,
                                           indent: 0, quoteIDs: [], nextQuoteID: &nextQuoteID) else { return nil }
            lines.append(contentsOf: part)
        }
        return lines.isEmpty ? nil : .init(lines: lines)
    }

    static func isSelectable(_ node: Markup, enableHTML: Bool, plugins: ParserPluginRegistry?) -> Bool {
        compose([node], enableHTML: enableHTML, plugins: plugins) != nil
    }

    private static func linesForBlock(_ node: Markup, enableHTML: Bool, plugins: ParserPluginRegistry?,
                                      indent: Int, quoteIDs: [Int], nextQuoteID: inout Int) -> [Line]? {
        if node is ThematicBreak {
            // Nested rules need their enclosing list or quote layout; keep those in SwiftUI.
            guard indent == 0, quoteIDs.isEmpty else { return nil }
            return [.init(kind: .rule, runs: [.init(text: ruleAnchor, style: .init(), code: false)],
                          indent: indent, quoteDepth: quoteIDs.count, quoteIDs: quoteIDs)]
        }
        if let heading = node as? Heading {
            guard let runs = inlineRuns(heading, enableHTML: enableHTML, plugins: plugins) else { return nil }
            return [.init(kind: .heading(heading.level), runs: runs, indent: indent,
                          quoteDepth: quoteIDs.count, quoteIDs: quoteIDs)]
        }
        if let paragraph = node as? Paragraph {
            guard let runs = inlineRuns(paragraph, enableHTML: enableHTML, plugins: plugins) else { return nil }
            return [.init(kind: quoteIDs.isEmpty ? .paragraph : .quote, runs: runs,
                          indent: indent, quoteDepth: quoteIDs.count, quoteIDs: quoteIDs)]
        }
        if let quote = node as? BlockQuote {
            let quoteID = nextQuoteID
            nextQuoteID += 1
            var lines: [Line] = []
            for child in quote.children {
                guard let part = linesForBlock(child, enableHTML: enableHTML, plugins: plugins,
                                               indent: indent, quoteIDs: quoteIDs + [quoteID],
                                               nextQuoteID: &nextQuoteID) else { return nil }
                lines.append(contentsOf: part)
            }
            return lines.isEmpty ? nil : lines
        }
        if let ordered = node as? OrderedList {
            return listLines(ordered, start: Int(ordered.startIndex), enableHTML: enableHTML,
                             plugins: plugins, indent: indent, quoteIDs: quoteIDs, nextQuoteID: &nextQuoteID)
        }
        if let unordered = node as? UnorderedList {
            return listLines(unordered, start: nil, enableHTML: enableHTML,
                             plugins: plugins, indent: indent, quoteIDs: quoteIDs, nextQuoteID: &nextQuoteID)
        }
        return nil
    }

    private static func listLines(_ list: Markup, start: Int?, enableHTML: Bool,
                                  plugins: ParserPluginRegistry?, indent: Int, quoteIDs: [Int],
                                  nextQuoteID: inout Int) -> [Line]? {
        var output: [Line] = []
        for (index, child) in list.children.enumerated() {
            guard let item = child as? ListItem else { return nil }
            let marker: String
            if let checkbox = item.checkbox { marker = checkbox == .checked ? "☑ " : "☐ " }
            else if let start { marker = "\(start + index). " }
            else { marker = "• " }
            var first = true
            for block in item.children {
                guard let part = linesForBlock(block, enableHTML: enableHTML, plugins: plugins,
                                               indent: indent + 1, quoteIDs: quoteIDs,
                                               nextQuoteID: &nextQuoteID) else { return nil }
                for line in part {
                    if first {
                        let prefix = Run(text: marker, style: .init(), code: false)
                        output.append(.init(kind: .list, runs: [prefix] + line.runs,
                                            indent: line.indent, quoteDepth: line.quoteDepth,
                                            quoteIDs: line.quoteIDs))
                        first = false
                    } else { output.append(line) }
                }
            }
        }
        return output.isEmpty ? nil : output
    }

    static func copyableInlineRuns(_ node: Markup, enableHTML: Bool, plugins: ParserPluginRegistry?) -> [Run]? {
        var output: [Run] = []
        for part in InlineContent.runs(in: node, enableHTML: enableHTML, plugins: plugins) {
            switch part {
            case let .text(value, style, tags, code):
                if !tags.isEmpty { return nil }
                output.append(.init(text: value, style: style, code: code))
            case .image, .footnote, .math, .plugin: return nil
            }
        }
        return output
    }

    private static func inlineRuns(_ node: Markup, enableHTML: Bool, plugins: ParserPluginRegistry?) -> [Run]? {
        copyableInlineRuns(node, enableHTML: enableHTML, plugins: plugins)
    }
}

/// A block range across content that must retain its SwiftUI rendering.
/// Images contribute no text; tables contribute their visible cell text.
struct ReaderBlockRangeDocument {
    struct Segment {
        enum Kind { case text, image, table }
        let nodes: [Markup]
        let kind: Kind
        var isImage: Bool { kind == .image }
        var isBridge: Bool { kind != .text }
    }

    let segments: [Segment]

    init?(_ nodes: [Markup], enableHTML: Bool, plugins: ParserPluginRegistry?) {
        var result: [Segment] = []
        var textRun: [Markup] = []
        func flushText() {
            if !textRun.isEmpty { result.append(.init(nodes: textRun, kind: .text)) }
            textRun.removeAll()
        }
        for node in nodes {
            if ReaderSelectionGroup.isStandaloneImage(node, enableHTML: enableHTML) {
                flushText()
                result.append(.init(nodes: [node], kind: .image))
            } else if node is Markdown.Table,
                      Self.tableText(node, enableHTML: enableHTML, plugins: plugins) != nil {
                flushText()
                result.append(.init(nodes: [node], kind: .table))
            } else if ReaderSelectionDocument.isSelectable(node, enableHTML: enableHTML, plugins: plugins) {
                textRun.append(node)
            } else { return nil }
        }
        flushText()
        guard result.contains(where: \.isBridge), result.count > 1 else { return nil }
        segments = result
    }

    func copiedText(in range: ClosedRange<Int>, enableHTML: Bool, plugins: ParserPluginRegistry?) -> String? {
        guard range.lowerBound >= 0, range.upperBound < segments.count else { return nil }
        var parts: [String] = []
        for segment in segments[range] {
            switch segment.kind {
            case .image: continue
            case .table:
                guard let node = segment.nodes.first,
                      let text = Self.tableText(node, enableHTML: enableHTML, plugins: plugins) else { return nil }
                parts.append(text)
            case .text:
                guard let text = ReaderSelectionDocument.compose(segment.nodes, enableHTML: enableHTML,
                                                                 plugins: plugins)?.copiedText else { return nil }
                parts.append(text)
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }

    static func tableText(_ node: Markup, enableHTML: Bool, plugins: ParserPluginRegistry?) -> String? {
        guard let table = node as? Markdown.Table else { return nil }
        let rows = [Array(table.head.children)] + table.body.children.map { Array($0.children) }
        var output: [String] = []
        for row in rows {
            var cells: [String] = []
            for cell in row {
                guard let runs = ReaderSelectionDocument.copyableInlineRuns(cell, enableHTML: enableHTML,
                                                                             plugins: plugins) else { return nil }
                cells.append(runs.map(\.text).joined())
            }
            output.append(cells.joined(separator: "\t"))
        }
        return output.joined(separator: "\n")
    }
}

enum ReaderSelectionGroup {
    case selectable([Markup])
    case blockBridge([Markup])
    case individual(Markup)

    static func isStandaloneImage(_ node: Markup, enableHTML: Bool) -> Bool {
        guard let paragraph = node as? Paragraph else { return false }
        let meaningful = Array(paragraph.children).filter { child in
            guard let text = child as? Markdown.Text else { return true }
            return !text.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard meaningful.count == 1, let only = meaningful.first else { return false }
        if let image = only as? Markdown.Image, let source = image.source {
            return ImageSource.parse(source) != nil
        }
        if enableHTML, let html = only as? InlineHTML,
           let image = SafeHTML.imageTag(html.rawHTML) {
            return ImageSource.parse(image.source) != nil
        }
        return false
    }

    static func group(_ nodes: [Markup], enableHTML: Bool, plugins: ParserPluginRegistry?, enabled: Bool = true) -> [ReaderSelectionGroup] {
        guard enabled else { return nodes.map(ReaderSelectionGroup.individual) }
        var result: [ReaderSelectionGroup] = []
        var pending: [Markup] = []
        func flush() {
            let hasBridge = pending.contains { isStandaloneImage($0, enableHTML: enableHTML) || $0 is Markdown.Table }
            let hasCopyable = pending.contains {
                ReaderSelectionDocument.isSelectable($0, enableHTML: enableHTML, plugins: plugins) || $0 is Markdown.Table
            }
            if hasBridge && hasCopyable && pending.count > 1 { result.append(.blockBridge(pending)) }
            else if pending.count > 1 && !hasBridge { result.append(.selectable(pending)) }
            else if pending.count > 1 { result.append(contentsOf: pending.map(ReaderSelectionGroup.individual)) }
            else if let one = pending.first {
                let lineCount = ReaderSelectionDocument.compose([one], enableHTML: enableHTML,
                                                                 plugins: plugins)?.lines.count ?? 0
                result.append(lineCount > 1 && !hasBridge ? .selectable(pending) : .individual(one))
            }
            pending.removeAll()
        }
        for node in nodes {
            if ReaderSelectionDocument.isSelectable(node, enableHTML: enableHTML, plugins: plugins) ||
                isStandaloneImage(node, enableHTML: enableHTML) ||
                ReaderBlockRangeDocument.tableText(node, enableHTML: enableHTML, plugins: plugins) != nil {
                pending.append(node)
            } else {
                flush()
                result.append(.individual(node))
            }
        }
        flush()
        return result
    }
}
