import Foundation

/// A source-preserving tree owned by SmoothMarkdown. The source ranges use UTF-16 offsets.
struct NativeMarkdownNode: Equatable {
    enum Kind: Equatable {
        case document, paragraph, heading(Int), fencedCode(String), table, tableRow, tableCell
        case list(ordered: Bool), listItem(checked: Bool?), blockQuote, thematicBreak
        case text, strong, emphasis, strikethrough, inlineCode, inlineMath
        case blockMath, footnoteReference(String), footnoteDefinition(String)
        case link(String), image(String), htmlBlock, raw
    }

    let kind: Kind
    let source: String
    let sourceRange: NSRange
    let children: [NativeMarkdownNode]

    init(kind: Kind, source: String, sourceRange: NSRange, children: [NativeMarkdownNode] = []) {
        self.kind = kind
        self.source = source
        self.sourceRange = sourceRange
        self.children = children
    }
}

/// The first native AST pass reuses the editor's source-preserving block scanner.
/// It deliberately keeps unrecognized blocks as raw nodes, rather than dropping source.
struct NativeMarkdownASTParser {
    init() {}

    func parse(_ source: String) -> NativeMarkdownNode {
        let document = MarkdownDocumentCodec().parse(source)
        let blocks = document.blocks.compactMap { block -> NativeMarkdownNode? in
            guard let range = document.sourceRange(of: block.id) else { return nil }
            return parse(block, range: range)
        }
        return NativeMarkdownNode(kind: .document, source: source,
                                  sourceRange: NSRange(location: 0, length: (source as NSString).length),
                                  children: blocks)
    }

    private func parse(_ block: MarkdownDocumentBlock, range: NSRange) -> NativeMarkdownNode {
        func node(_ kind: NativeMarkdownNode.Kind, _ children: [NativeMarkdownNode] = []) -> NativeMarkdownNode {
            NativeMarkdownNode(kind: kind, source: block.source, sourceRange: range, children: children)
        }
        let trimmed = block.source.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("[^"), let close = trimmed.range(of: "]:") {
            let label = String(trimmed[trimmed.index(trimmed.startIndex, offsetBy: 2)..<close.lowerBound])
            if !label.isEmpty { return node(.footnoteDefinition(label)) }
        }
        if trimmed.hasPrefix("$$"), trimmed.hasSuffix("$$"), trimmed.count >= 4 {
            return node(.blockMath)
        }
        switch block.kind {
        case let .paragraph(markdown):
            return node(.paragraph, inline(markdown, offset: bodyOffset(markdown, in: block.source, base: range.location)))
        case let .heading(level, markdown):
            return node(.heading(level), inline(markdown, offset: bodyOffset(markdown, in: block.source, base: range.location)))
        case let .fencedCode(_, info, _):
            return node(.fencedCode(info.trimmingCharacters(in: .whitespacesAndNewlines)))
        case let .table(table):
            let rows = [table.headers] + table.rows
            let lines = block.source.components(separatedBy: "\n")
            return node(.table, rows.enumerated().map { rowIndex, cells in
                let lineIndex = rowIndex == 0 ? 0 : rowIndex + 1
                let line = lines.indices.contains(lineIndex) ? lines[lineIndex] : ""
                let lineOffset = lines[..<min(lineIndex, lines.count)].reduce(0) {
                    $0 + ($1 as NSString).length + 1
                }
                let rowRange = NSRange(location: range.location + lineOffset,
                                       length: (line as NSString).length)
                var searchStart = line.startIndex
                let cellNodes = cells.map { cell -> NativeMarkdownNode in
                    let found = line.range(of: cell, range: searchStart..<line.endIndex)
                    let cellOffset = found.map { (String(line[..<$0.lowerBound]) as NSString).length } ?? 0
                    if let found { searchStart = found.upperBound }
                    let cellRange = NSRange(location: rowRange.location + cellOffset,
                                            length: (cell as NSString).length)
                    return NativeMarkdownNode(kind: .tableCell, source: cell, sourceRange: cellRange,
                                              children: inline(cell, offset: cellRange.location))
                }
                return NativeMarkdownNode(kind: .tableRow, source: line, sourceRange: rowRange,
                                          children: cellNodes)
            })
        case let .list(list):
            let ordered = list.items.first?.kind == .ordered
            var searchStart = block.source.startIndex
            let items = list.items.map { item -> NativeMarkdownNode in
                let itemSource = item.source
                let found = block.source.range(of: itemSource, range: searchStart..<block.source.endIndex)
                let itemOffset = found.map { (String(block.source[..<$0.lowerBound]) as NSString).length } ?? 0
                if let found { searchStart = found.upperBound }
                let itemRange = NSRange(location: range.location + itemOffset,
                                        length: (itemSource as NSString).length)
                let prefix = item.indent + item.marker + item.spacing + (item.taskMarker ?? "") + item.taskSpacing
                let body = item.content
                return NativeMarkdownNode(kind: .listItem(checked: item.checked), source: itemSource,
                                          sourceRange: itemRange,
                                          children: inline(body, offset: itemRange.location + (prefix as NSString).length))
            }
            return node(.list(ordered: ordered), items)
        case .horizontalRule: return node(.thematicBreak)
        case .plugin, .raw:
            if trimmed.hasPrefix("<"), trimmed.hasSuffix(">") { return node(.htmlBlock) }
            if trimmed.hasPrefix(">") {
                var lineOffset = 0
                let paragraphs = block.source.components(separatedBy: "\n").compactMap { line -> NativeMarkdownNode? in
                    defer { lineOffset += (line as NSString).length + 1 }
                    let content = line.replacingOccurrences(of: #"^ {0,3}> ?"#, with: "", options: .regularExpression)
                    guard !content.isEmpty else { return nil }
                    let prefixLength = (line as NSString).length - (content as NSString).length
                    let contentRange = NSRange(location: range.location + lineOffset + prefixLength,
                                               length: (content as NSString).length)
                    return NativeMarkdownNode(kind: .paragraph, source: content, sourceRange: contentRange,
                                              children: inline(content, offset: contentRange.location))
                }
                return node(.blockQuote, paragraphs)
            }
            return node(.raw)
        }
    }

    private func bodyOffset(_ body: String, in source: String, base: Int) -> Int {
        guard let range = source.range(of: body) else { return base }
        return base + (String(source[..<range.lowerBound]) as NSString).length
    }

    private func inline(_ source: String, offset: Int) -> [NativeMarkdownNode] {
        let characters = Array(source)
        var result: [NativeMarkdownNode] = []
        var index = 0
        var plainStart = 0

        func utf16Offset(_ position: Int) -> Int { (String(characters[..<position]) as NSString).length }
        func append(_ kind: NativeMarkdownNode.Kind, start: Int, end: Int,
                    contentStart: Int? = nil, contentEnd: Int? = nil) {
            let spelling = String(characters[start..<end])
            let children: [NativeMarkdownNode]
            if let contentStart, let contentEnd {
                children = inline(String(characters[contentStart..<contentEnd]),
                                  offset: offset + utf16Offset(contentStart))
            } else { children = [] }
            result.append(.init(kind: kind, source: spelling,
                                sourceRange: NSRange(location: offset + utf16Offset(start),
                                                     length: (spelling as NSString).length), children: children))
        }
        func flushPlain(until end: Int) {
            if plainStart < end { append(.text, start: plainStart, end: end) }
        }
        func closing(_ marker: [Character], after start: Int) -> Int? {
            guard !marker.isEmpty, start < characters.count else { return nil }
            var cursor = start
            while cursor + marker.count <= characters.count {
                if characters[cursor] == "\\" { cursor += min(2, characters.count - cursor); continue }
                if Array(characters[cursor..<(cursor + marker.count)]) == marker { return cursor }
                cursor += 1
            }
            return nil
        }

        while index < characters.count {
            if characters[index] == "\\", index + 1 < characters.count { index += 2; continue }
            if characters[index] == "`" {
                let run = characters[index...].prefix(while: { $0 == "`" }).count
                if let end = closing(Array(repeating: "`", count: run), after: index + run) {
                    flushPlain(until: index)
                    append(.inlineCode, start: index, end: end + run)
                    index = end + run; plainStart = index; continue
                }
            }
            if characters[index] == "$", index + 1 < characters.count,
               characters[index + 1] != "$", let end = closing(["$"], after: index + 1),
               end > index + 1, characters[end - 1] != " " {
                flushPlain(until: index)
                append(.inlineMath, start: index, end: end + 1)
                index = end + 1; plainStart = index; continue
            }
            if characters[index] == "[", index + 3 < characters.count,
               characters[index + 1] == "^", let close = closing(["]"], after: index + 2),
               close > index + 2 {
                let label = String(characters[(index + 2)..<close])
                flushPlain(until: index)
                append(.footnoteReference(label), start: index, end: close + 1)
                index = close + 1; plainStart = index; continue
            }
            if characters[index] == "!" || characters[index] == "[" {
                let image = characters[index] == "!"
                let open = image ? index + 1 : index
                if open < characters.count, characters[open] == "[",
                   let close = closing(["]"], after: open + 1),
                   close + 1 < characters.count, characters[close + 1] == "(",
                   let destinationEnd = closing([")"], after: close + 2) {
                    let destination = String(characters[(close + 2)..<destinationEnd])
                    flushPlain(until: index)
                    append(image ? .image(destination) : .link(destination), start: index,
                           end: destinationEnd + 1, contentStart: open + 1, contentEnd: close)
                    index = destinationEnd + 1; plainStart = index; continue
                }
            }
            let marker: [Character]
            let kind: NativeMarkdownNode.Kind
            if index + 1 < characters.count, characters[index] == "~", characters[index + 1] == "~" {
                marker = ["~", "~"]; kind = .strikethrough
            } else if index + 1 < characters.count, characters[index] == "*", characters[index + 1] == "*" {
                marker = ["*", "*"]; kind = .strong
            } else if index + 1 < characters.count, characters[index] == "_", characters[index + 1] == "_" {
                marker = ["_", "_"]; kind = .strong
            } else if characters[index] == "*" || characters[index] == "_" {
                marker = [characters[index]]; kind = .emphasis
            } else {
                index += 1; continue
            }
            if let end = closing(marker, after: index + marker.count), end > index + marker.count {
                flushPlain(until: index)
                append(kind, start: index, end: end + marker.count,
                       contentStart: index + marker.count, contentEnd: end)
                index = end + marker.count; plainStart = index
            } else { index += 1 }
        }
        flushPlain(until: characters.count)
        return result
    }
}
