import Foundation

/// Locations follow CommonMark's one-based UTF-8 byte columns.
public struct SourceLocation: Comparable, Hashable {
    public let line: Int
    public let column: Int
    public init(line: Int, column: Int) { self.line = line; self.column = column }
    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.line, lhs.column) < (rhs.line, rhs.column)
    }
}

/// The reader-facing node model is built from NativeMarkdownASTParser.
public class Markup {
    public let children: [Markup]
    public let range: Range<SourceLocation>?
    private var originalSource: String?

    public init(_ children: [Markup] = [], range: Range<SourceLocation>? = nil, source: String? = nil) {
        self.children = children
        self.range = range
        originalSource = source
    }

    public func child(at index: Int) -> Markup? { children.indices.contains(index) ? children[index] : nil }
    public var childCount: Int { children.count }
    public func isIdentical(to other: Markup) -> Bool { self === other }
    public func withUncheckedChildren(_ children: [Markup]) -> Markup {
        switch self {
        case is Document: return Document(children, range: range, source: originalSource)
        case let heading as Heading:
            return Heading(level: heading.level, children: children, range: range, source: originalSource)
        case is Paragraph: return Paragraph(children, range: range, source: originalSource)
        case is Strong: return Strong(children, range: range, source: originalSource)
        case is Emphasis: return Emphasis(children, range: range, source: originalSource)
        case is Strikethrough: return Strikethrough(children, range: range, source: originalSource)
        case is BlockQuote: return BlockQuote(children, range: range, source: originalSource)
        case let list as OrderedList:
            return OrderedList(startIndex: list.startIndex, children: children, range: range, source: originalSource)
        case is UnorderedList: return UnorderedList(children, range: range, source: originalSource)
        case let item as Markdown.ListItem:
            return Markdown.ListItem(checkbox: item.checkbox, children: children, range: range, source: originalSource)
        case let link as Markdown.Link:
            return Markdown.Link(destination: link.destination, title: link.title, children: children, range: range, source: originalSource)
        case let image as Markdown.Image:
            return Markdown.Image(source: image.source, title: image.title, children: children, range: range, rawSource: originalSource)
        case let text as Markdown.Text: return Markdown.Text(text.string, range: range, source: originalSource)
        case let code as InlineCode: return InlineCode(code.code, range: range, source: originalSource)
        case let html as InlineHTML: return InlineHTML(html.rawHTML, range: range, source: originalSource)
        case let html as HTMLBlock: return HTMLBlock(html.rawHTML, range: range, source: originalSource)
        case let code as CodeBlock:
            return CodeBlock(code: code.code, language: code.language, range: range, source: originalSource)
        case is SoftBreak: return SoftBreak(range: range, source: originalSource)
        case is LineBreak: return LineBreak(range: range, source: originalSource)
        case is ThematicBreak: return ThematicBreak(range: range, source: originalSource)
        case let table as Markdown.Table:
            let head = children.first as? Markdown.Table.Head ?? table.head
            let body = children.dropFirst().first as? Markdown.Table.Body ?? table.body
            return Markdown.Table(head: head, body: body, alignments: table.columnAlignments, range: range, source: originalSource)
        case is Markdown.Table.Head: return Markdown.Table.Head(children, range: range, source: originalSource)
        case is Markdown.Table.Body: return Markdown.Table.Body(children, range: range, source: originalSource)
        case is Markdown.Table.Row: return Markdown.Table.Row(children, range: range, source: originalSource)
        case is Markdown.Table.Cell: return Markdown.Table.Cell(children, range: range, source: originalSource)
        default: return Markup(children, range: range, source: originalSource)
        }
    }
    public func format() -> String { originalSource ?? children.map { $0.format() }.joined() }
}

public final class Document: Markup {
    public convenience init(parsing source: String) {
        let adapter = NativeMarkdownMarkupAdapter(source: source)
        self.init(adapter.convert(NativeMarkdownASTParser().parse(source)).children,
                  range: adapter.range(NSRange(location: 0, length: (source as NSString).length)), source: source)
    }
}
public final class Paragraph: Markup {}
public final class Heading: Markup {
    public let level: Int
    public init(level: Int, children: [Markup] = [], range: Range<SourceLocation>? = nil, source: String? = nil) {
        self.level = level
        super.init(children, range: range, source: source)
    }
}
public final class Strong: Markup {}
public final class Emphasis: Markup {}
public final class Strikethrough: Markup {}
public final class InlineCode: Markup {
    public let code: String
    public init(_ code: String, range: Range<SourceLocation>? = nil, source: String? = nil) {
        self.code = code
        super.init(range: range, source: source ?? code)
    }
}
public final class InlineHTML: Markup {
    public let rawHTML: String
    public init(_ rawHTML: String, range: Range<SourceLocation>? = nil, source: String? = nil) {
        self.rawHTML = rawHTML
        super.init(range: range, source: source ?? rawHTML)
    }
}
public final class HTMLBlock: Markup {
    public let rawHTML: String
    public init(_ rawHTML: String, range: Range<SourceLocation>? = nil, source: String? = nil) {
        self.rawHTML = rawHTML
        super.init(range: range, source: source)
    }
}
public final class CodeBlock: Markup {
    public let code: String
    public let language: String?
    public init(code: String, language: String? = nil, range: Range<SourceLocation>? = nil, source: String? = nil) {
        self.code = code
        self.language = language
        super.init(range: range, source: source)
    }
}
public final class BlockQuote: Markup {}
public final class OrderedList: Markup {
    public let startIndex: UInt
    public init(startIndex: UInt = 1, children: [Markup] = [], range: Range<SourceLocation>? = nil, source: String? = nil) {
        self.startIndex = startIndex
        super.init(children, range: range, source: source)
    }
}
public final class UnorderedList: Markup {}
public final class ThematicBreak: Markup {}
public final class SoftBreak: Markup {}
public final class LineBreak: Markup {}
public typealias ListItem = Markdown.ListItem
public typealias NativeCodeBlock = CodeBlock

public enum Markdown {
    public typealias CodeBlock = NativeCodeBlock
    public final class Text: Markup {
        public let string: String
        public init(_ string: String, range: Range<SourceLocation>? = nil, source: String? = nil) {
            self.string = string
            super.init(range: range, source: source ?? string)
        }
    }
    public final class Link: Markup {
        public let destination: String?
        public let title: String?
        public init(destination: String?, title: String? = nil, children: [Markup] = [], range: Range<SourceLocation>? = nil, source: String? = nil) {
            self.destination = destination; self.title = title
            super.init(children, range: range, source: source)
        }
    }
    public final class Image: Markup {
        public let source: String?
        public let title: String?
        public var alt: String { children.map { ($0 as? Text)?.string ?? $0.format() }.joined() }
        public init(source: String?, title: String? = nil, children: [Markup] = [], range: Range<SourceLocation>? = nil, rawSource: String? = nil) {
            self.source = source; self.title = title
            super.init(children, range: range, source: rawSource)
        }
    }
    public final class ListItem: Markup {
        public enum Checkbox { case checked, unchecked }
        public let checkbox: Checkbox?
        public init(checkbox: Checkbox? = nil, children: [Markup] = [], range: Range<SourceLocation>? = nil, source: String? = nil) {
            self.checkbox = checkbox
            super.init(children, range: range, source: source)
        }
    }
    public final class Table: Markup {
        public enum ColumnAlignment { case left, center, right }
        public final class Head: Markup {}
        public final class Body: Markup {}
        public final class Row: Markup {}
        public final class Cell: Markup {}
        public let head: Head
        public let body: Body
        public let columnAlignments: [ColumnAlignment?]
        public init(head: Head = Head(), body: Body = Body(), alignments: [ColumnAlignment?] = [], range: Range<SourceLocation>? = nil, source: String? = nil) {
            self.head = head; self.body = body; columnAlignments = alignments
            super.init([head, body], range: range, source: source)
        }
    }
}

private struct NativeMarkdownMarkupAdapter {
    let source: String
    private let locations: [SourceLocation]
    init(source: String) {
        self.source = source
        var positions = [SourceLocation(line: 1, column: 1)]
        var line = 1
        var column = 1
        for scalar in source.unicodeScalars {
            let spelling = String(scalar)
            let utf16Count = spelling.utf16.count
            for _ in 1..<utf16Count { positions.append(SourceLocation(line: line, column: column)) }
            if scalar == "\n" { line += 1; column = 1 }
            else { column += spelling.utf8.count }
            positions.append(SourceLocation(line: line, column: column))
        }
        locations = positions
    }

    func range(_ utf16: NSRange) -> Range<SourceLocation>? {
        guard utf16.location >= 0, NSMaxRange(utf16) < locations.count else { return nil }
        return locations[utf16.location]..<locations[NSMaxRange(utf16)]
    }

    func convert(_ node: NativeMarkdownNode) -> Markup {
        let converted = coalesce(node.children.compactMap(convertVisible))
        let position = range(node.sourceRange)
        switch node.kind {
        case .document: return Markup(converted, range: position, source: node.source)
        case .paragraph: return Paragraph(converted, range: position, source: node.source)
        case let .heading(level): return Heading(level: level, children: converted, range: position, source: node.source)
        case .strong: return Strong(converted, range: position, source: node.source)
        case .emphasis: return Emphasis(converted, range: position, source: node.source)
        case .strikethrough: return Strikethrough(converted, range: position, source: node.source)
        case .inlineCode: return InlineCode(node.semanticText ?? "", range: position, source: node.source)
        case .inlineHTML: return InlineHTML(node.semanticText ?? node.source, range: position, source: node.source)
        case .htmlBlock: return HTMLBlock(node.semanticText ?? node.source, range: position, source: node.source)
        case let .fencedCode(info): return CodeBlock(code: node.semanticText ?? "", language: info.isEmpty ? nil : info, range: position, source: node.source)
        case .indentedCode: return CodeBlock(code: node.semanticText ?? "", language: nil, range: position, source: node.source)
        case .blockQuote: return BlockQuote(converted, range: position, source: node.source)
        case let .list(ordered):
            let items = node.isTight == true ? node.children.map(convertTightListItem) : converted
            return ordered ? OrderedList(startIndex: UInt(max(0, node.listStart ?? 1)), children: items, range: position, source: node.source) : UnorderedList(items, range: position, source: node.source)
        case let .listItem(checked):
            let checkbox: Markdown.ListItem.Checkbox? = checked.map { $0 ? .checked : .unchecked }
            return Markdown.ListItem(checkbox: checkbox, children: converted, range: position, source: node.source)
        case .thematicBreak: return ThematicBreak(range: position, source: node.source)
        case .softBreak: return SoftBreak(range: position, source: node.source)
        case .hardBreak: return LineBreak(range: position, source: node.source)
        case let .link(destination): return Markdown.Link(destination: destination, title: node.title, children: converted, range: position, source: node.source)
        case let .image(source): return Markdown.Image(source: source, title: node.title, children: converted, range: position, rawSource: node.source)
        case .table:
            let rows = node.children.map(convert)
            let head = Markdown.Table.Head(rows.first?.children ?? [], range: rows.first?.range, source: rows.first?.format())
            let body = Markdown.Table.Body(Array(rows.dropFirst()), range: position, source: nil)
            let alignments: [Markdown.Table.ColumnAlignment?] = node.tableAlignments.map {
                switch $0 { case "left": .left; case "center": .center; case "right": .right; default: nil }
            }
            return Markdown.Table(head: head, body: body, alignments: alignments, range: position, source: node.source)
        case .tableRow: return Markdown.Table.Row(converted, range: position, source: node.source)
        case .tableCell: return Markdown.Table.Cell(converted, range: position, source: node.source)
        case .footnoteDefinition, .blockMath:
            let text = Markdown.Text(node.source, range: position, source: node.source)
            return Paragraph([text], range: position, source: node.source)
        case .text, .inlineMath, .footnoteReference, .raw:
            return Markdown.Text(node.semanticText ?? node.source, range: position, source: node.source)
        case .referenceDefinition: return Markup(range: position, source: node.source)
        }
    }

    private func convertVisible(_ node: NativeMarkdownNode) -> Markup? {
        if case .referenceDefinition = node.kind { return nil }
        return convert(node)
    }

    private func convertTightListItem(_ node: NativeMarkdownNode) -> Markup {
        guard case let .listItem(checked) = node.kind else { return convert(node) }
        let children = node.children.compactMap(convertVisible)
        var blocks: [Markup] = []
        var inlines: [Markup] = []
        func flush() {
            guard !inlines.isEmpty else { return }
            blocks.append(Paragraph(inlines,
                                    range: inlines.first?.range.flatMap { first in
                                        inlines.last?.range.map { first.lowerBound..<$0.upperBound }
                                    }, source: inlines.map { $0.format() }.joined()))
            inlines.removeAll()
        }
        for child in children {
            if child is BlockQuote || child is OrderedList || child is UnorderedList ||
                child is CodeBlock || child is HTMLBlock || child is ThematicBreak ||
                child is Markdown.Table || child is Paragraph {
                flush()
                blocks.append(child)
            } else { inlines.append(child) }
        }
        flush()
        let checkbox: Markdown.ListItem.Checkbox? = checked.map { $0 ? .checked : .unchecked }
        return Markdown.ListItem(checkbox: checkbox, children: blocks,
                                 range: range(node.sourceRange), source: node.source)
    }

    private func coalesce(_ children: [Markup]) -> [Markup] {
        var result: [Markup] = []
        for child in children {
            if let text = child as? Markdown.Text, let previous = result.last as? Markdown.Text {
                result.removeLast()
                let joined = previous.string + text.string
                let mergedRange = previous.range.flatMap { first in text.range.map { first.lowerBound..<$0.upperBound } }
                result.append(Markdown.Text(joined, range: mergedRange, source: previous.format() + text.format()))
            } else { result.append(child) }
        }
        return result
    }
}
