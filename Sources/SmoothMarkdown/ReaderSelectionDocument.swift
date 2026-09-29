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

    private static func inlineRuns(_ node: Markup, enableHTML: Bool, plugins: ParserPluginRegistry?) -> [Run]? {
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
}

enum ReaderSelectionGroup {
    case selectable([Markup])
    case individual(Markup)

    static func group(_ nodes: [Markup], enableHTML: Bool, plugins: ParserPluginRegistry?, enabled: Bool = true) -> [ReaderSelectionGroup] {
        guard enabled else { return nodes.map(ReaderSelectionGroup.individual) }
        var result: [ReaderSelectionGroup] = []
        var pending: [Markup] = []
        func flush() {
            if pending.count > 1 { result.append(.selectable(pending)) }
            else if let one = pending.first {
                let lineCount = ReaderSelectionDocument.compose([one], enableHTML: enableHTML, plugins: plugins)?.lines.count ?? 0
                result.append(lineCount > 1 ? .selectable(pending) : .individual(one))
            }
            pending.removeAll()
        }
        for node in nodes {
            if ReaderSelectionDocument.isSelectable(node, enableHTML: enableHTML, plugins: plugins) {
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
