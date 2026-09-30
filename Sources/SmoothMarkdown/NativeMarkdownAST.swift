import Foundation

/// A source-preserving tree owned by SmoothMarkdown. The source ranges use UTF-16 offsets.
struct NativeMarkdownNode: Equatable {
    enum Kind: Equatable {
        case document, paragraph, heading(Int), fencedCode(String), indentedCode, table, tableRow, tableCell
        case list(ordered: Bool), listItem(checked: Bool?), blockQuote, thematicBreak
        case text, strong, emphasis, strikethrough, inlineCode, inlineMath
        case softBreak, hardBreak, inlineHTML
        case blockMath, footnoteReference(String), footnoteDefinition(String)
        case referenceDefinition(String, String)
        case link(String), image(String), htmlBlock, raw
    }

    let kind: Kind
    let source: String
    let sourceRange: NSRange
    let children: [NativeMarkdownNode]

    var semanticText: String? {
        switch kind {
        case .text: NativeMarkdownTextDecoder.decode(source)
        case .inlineCode: NativeMarkdownTextDecoder.codeSpan(source)
        default: nil
        }
    }

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
        let references = referenceDefinitions(in: document)
        var blocks: [NativeMarkdownNode] = []
        var index = 0
        while index < document.blocks.count {
            let block = document.blocks[index]
            guard let range = document.sourceRange(of: block.id) else { index += 1; continue }
            if index + 1 < document.blocks.count {
                let next = document.blocks[index + 1]
                if case let .paragraph(markdown) = block.kind,
                   case .horizontalRule = next.kind,
                   next.leadingTrivia.isEmpty,
                   next.source.trimmingCharacters(in: .whitespacesAndNewlines)
                    .range(of: #"^ {0,3}-{3,}$"#, options: .regularExpression) != nil,
                   let nextRange = document.sourceRange(of: next.id),
                   NSMaxRange(range) == nextRange.location {
                    let combined = (source as NSString).substring(with: NSRange(
                        location: range.location, length: NSMaxRange(nextRange) - range.location))
                    blocks.append(.init(kind: .heading(2), source: combined,
                                        sourceRange: NSRange(location: range.location,
                                                             length: (combined as NSString).length),
                                        children: inline(markdown, offset: range.location, references: references)))
                    index += 2
                    continue
                }
            }
            blocks.append(parse(block, range: range, references: references))
            index += 1
        }
        return NativeMarkdownNode(kind: .document, source: source,
                                  sourceRange: NSRange(location: 0, length: (source as NSString).length),
                                  children: blocks)
    }

    private func parse(_ block: MarkdownDocumentBlock, range: NSRange,
                       references: [String: String]) -> NativeMarkdownNode {
        func node(_ kind: NativeMarkdownNode.Kind, _ children: [NativeMarkdownNode] = []) -> NativeMarkdownNode {
            NativeMarkdownNode(kind: kind, source: block.source, sourceRange: range, children: children)
        }
        let trimmed = block.source.trimmingCharacters(in: .whitespacesAndNewlines)
        if let definition = referenceDefinition(trimmed), !definition.label.hasPrefix("^") {
            return node(.referenceDefinition(definition.label, definition.destination))
        }
        if trimmed.hasPrefix("[^"), let close = trimmed.range(of: "]:") {
            let label = String(trimmed[trimmed.index(trimmed.startIndex, offsetBy: 2)..<close.lowerBound])
            if !label.isEmpty { return node(.footnoteDefinition(label)) }
        }
        if trimmed.hasPrefix("$$"), trimmed.hasSuffix("$$"), trimmed.count >= 4 {
            return node(.blockMath)
        }
        let lines = trimmed.components(separatedBy: "\n")
        if let last = lines.last, lines.count > 1,
           last.range(of: #"^ {0,3}=+[ \t]*$"#, options: .regularExpression) != nil,
           case let .paragraph(markdown) = block.kind {
            let body = markdown.components(separatedBy: "\n").dropLast().joined(separator: "\n")
            return node(.heading(1), inline(body, offset: bodyOffset(body, in: block.source, base: range.location),
                                            references: references))
        }
        if lines.count == 2, !lines[0].contains("|"),
           lines[1].range(of: #"^ {0,3}-{3,}[ \t]*$"#, options: .regularExpression) != nil,
           case .table = block.kind {
            return node(.heading(2), inline(lines[0], offset: bodyOffset(lines[0], in: block.source,
                                                                          base: range.location),
                                            references: references))
        }
        let sourceLines = block.source.components(separatedBy: "\n")
        if !sourceLines.isEmpty, sourceLines.allSatisfy({ line in
            line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                line.hasPrefix("    ") || line.hasPrefix("\t")
        }) {
            return node(.indentedCode)
        }
        switch block.kind {
        case let .paragraph(markdown):
            return node(.paragraph, inline(markdown, offset: bodyOffset(markdown, in: block.source, base: range.location), references: references))
        case let .heading(level, markdown):
            let body = markdown.replacingOccurrences(of: #"[ \t]+#+[ \t]*$"#, with: "",
                                                      options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            return node(.heading(level), inline(body, offset: bodyOffset(body, in: block.source,
                                                                         base: range.location),
                                                references: references))
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
                                              children: inline(cell, offset: cellRange.location, references: references))
                }
                return NativeMarkdownNode(kind: .tableRow, source: line, sourceRange: rowRange,
                                          children: cellNodes)
            })
        case let .list(list):
            return node(.list(ordered: list.items.first?.kind == .ordered),
                        listNodes(list, source: block.source, base: range.location,
                                  references: references))
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
                                              children: inline(content, offset: contentRange.location, references: references))
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

    private func listNodes(_ list: MarkdownSourceList, source: String, base: Int,
                           references: [String: String]) -> [NativeMarkdownNode] {
        let text = source as NSString
        func width(_ indent: String) -> Int {
            indent.reduce(0) { value, character in
                character == "\t" ? ((value / 4) + 1) * 4 : value + 1
            }
        }
        func position(_ index: Int) -> Int { list.sourceOffset(ofItemAt: index) ?? text.length }
        func slice(_ start: Int, _ end: Int) -> String {
            text.substring(with: NSRange(location: start, length: max(0, end - start)))
        }
        func nodes(from first: Int, through limit: Int) -> [NativeMarkdownNode] {
            guard first < limit else { return [] }
            let level = width(list.items[first].indent)
            var result: [NativeMarkdownNode] = []
            var index = first
            while index < limit {
                let item = list.items[index]
                let start = position(index)
                var next = index + 1
                while next < limit && width(list.items[next].indent) > level { next += 1 }
                let end = next < list.items.count ? position(next) : text.length
                let prefix = item.indent + item.marker + item.spacing + (item.taskMarker ?? "") + item.taskSpacing
                var children = inline(item.content, offset: base + start + (prefix as NSString).length,
                                      references: references)
                if index + 1 < next {
                    let childStart = position(index + 1)
                    let last = list.items[next - 1]
                    let childEnd = position(next - 1) + (last.source as NSString).length +
                        last.trailingContinuations.reduce(0) { $0 + ($1.source as NSString).length }
                    let ordered = list.items[index + 1].kind == .ordered
                    children.append(.init(kind: .list(ordered: ordered),
                                          source: slice(childStart, childEnd),
                                          sourceRange: NSRange(location: base + childStart,
                                                               length: childEnd - childStart),
                                          children: nodes(from: index + 1, through: next)))
                }
                result.append(.init(kind: .listItem(checked: item.checked), source: slice(start, end),
                                    sourceRange: NSRange(location: base + start, length: end - start),
                                    children: children))
                index = next
            }
            return result
        }
        return nodes(from: 0, through: list.items.count)
    }

    private func inline(_ source: String, offset: Int,
                        references: [String: String]) -> [NativeMarkdownNode] {
        let characters = Array(source)
        var utf16Positions = [Int](repeating: 0, count: characters.count + 1)
        for position in characters.indices {
            utf16Positions[position + 1] = utf16Positions[position] + String(characters[position]).utf16.count
        }
        var result: [NativeMarkdownNode] = []
        var index = 0
        var plainStart = 0

        func utf16Offset(_ position: Int) -> Int { utf16Positions[position] }
        func append(_ kind: NativeMarkdownNode.Kind, start: Int, end: Int,
                    contentStart: Int? = nil, contentEnd: Int? = nil,
                    parseContent: Bool = true) {
            let spelling = String(characters[start..<end])
            let children: [NativeMarkdownNode]
            if let contentStart, let contentEnd {
                let content = String(characters[contentStart..<contentEnd])
                if parseContent {
                    children = inline(content, offset: offset + utf16Offset(contentStart),
                                      references: references)
                } else {
                    children = [.init(kind: .text, source: content,
                                      sourceRange: NSRange(location: offset + utf16Offset(contentStart),
                                                           length: (content as NSString).length))]
                }
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
        func closingTildes(_ count: Int, after start: Int) -> Int? {
            var cursor = start
            while cursor + count <= characters.count {
                if characters[cursor] == "\\" { cursor += min(2, characters.count - cursor); continue }
                if characters[cursor] == "~",
                   (cursor == 0 || characters[cursor - 1] != "~"),
                   (cursor + count == characters.count || characters[cursor + count] != "~"),
                   characters[cursor..<(cursor + count)].allSatisfy({ $0 == "~" }) {
                    return cursor
                }
                cursor += 1
            }
            return nil
        }

        while index < characters.count {
            if characters[index] == "\\", index + 1 < characters.count {
                if characters[index + 1] == "\n" {
                    flushPlain(until: index)
                    append(.hardBreak, start: index, end: index + 2)
                    index += 2; plainStart = index; continue
                }
                index += 2; continue
            }
            if characters[index] == "\n" {
                let hard = index >= 2 && characters[index - 1] == " " && characters[index - 2] == " "
                let start = hard ? max(plainStart, index - 2) : index
                flushPlain(until: start)
                append(hard ? .hardBreak : .softBreak, start: start, end: index + 1)
                index += 1; plainStart = index; continue
            }
            if characters[index] == "<", let end = closing([">"], after: index + 1) {
                let content = String(characters[(index + 1)..<end])
                if let destination = autolinkDestination(content) {
                    flushPlain(until: index)
                    append(.link(destination), start: index, end: end + 1,
                           contentStart: index + 1, contentEnd: end, parseContent: false)
                    index = end + 1; plainStart = index; continue
                }
                if content.range(of: #"^/?[A-Za-z][A-Za-z0-9-]*(?:\s+[^<>]*)?/?$|^!--.*--$"#,
                                 options: .regularExpression) != nil {
                    flushPlain(until: index)
                    append(.inlineHTML, start: index, end: end + 1)
                    index = end + 1; plainStart = index; continue
                }
            }
            if index == 0 || characters[index - 1].isWhitespace ||
                "*_~(".contains(characters[index - 1]),
               let autolink = bareAutolink(in: characters, at: index) {
                flushPlain(until: index)
                append(.link(autolink.destination), start: index, end: autolink.end,
                       contentStart: index, contentEnd: autolink.end, parseContent: false)
                index = autolink.end; plainStart = index; continue
            }
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
                   let close = closing(["]"], after: open + 1) {
                    let label = String(characters[(open + 1)..<close])
                    var destination: String?
                    var end = close + 1
                    if end < characters.count, characters[end] == "(",
                       let destinationEnd = closing([")"], after: end + 1) {
                        destination = NativeMarkdownTextDecoder.decode(
                            String(characters[(end + 1)..<destinationEnd]))
                        end = destinationEnd + 1
                    } else if end < characters.count, characters[end] == "[",
                              let referenceEnd = closing(["]"], after: end + 1) {
                        let reference = String(characters[(end + 1)..<referenceEnd])
                        destination = references[normalizeReference(reference.isEmpty ? label : reference)]
                        end = referenceEnd + 1
                    } else if !image {
                        destination = references[normalizeReference(label)]
                    }
                    if let destination {
                        flushPlain(until: index)
                        append(image ? .image(destination) : .link(destination), start: index,
                               end: end, contentStart: open + 1, contentEnd: close)
                        index = end; plainStart = index; continue
                    }
                }
            }
            let marker: [Character]
            let kind: NativeMarkdownNode.Kind
            if characters[index] == "~" {
                let run = characters[index...].prefix(while: { $0 == "~" }).count
                guard run <= 2, let end = closingTildes(run, after: index + run),
                      end > index + run else { index += max(1, run); continue }
                flushPlain(until: index)
                append(.strikethrough, start: index, end: end + run,
                       contentStart: index + run, contentEnd: end)
                index = end + run; plainStart = index; continue
            } else if index + 1 < characters.count, characters[index] == "*", characters[index + 1] == "*" {
                marker = ["*", "*"]; kind = .strong
            } else if index + 1 < characters.count, characters[index] == "_", characters[index + 1] == "_" {
                if index > 0, index + 2 < characters.count,
                   characters[index - 1].isLetter || characters[index - 1].isNumber,
                   characters[index + 2].isLetter || characters[index + 2].isNumber {
                    index += 2; continue
                }
                marker = ["_", "_"]; kind = .strong
            } else if characters[index] == "*" || characters[index] == "_" {
                if characters[index] == "_", index > 0, index + 1 < characters.count,
                   (characters[index - 1].isLetter || characters[index - 1].isNumber),
                   (characters[index + 1].isLetter || characters[index + 1].isNumber) {
                    index += 1; continue
                }
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

    private func autolinkDestination(_ content: String) -> String? {
        guard !content.isEmpty, !content.contains(where: { $0.isWhitespace || $0 == "<" || $0 == ">" }) else {
            return nil
        }
        if content.range(of: #"^[A-Za-z][A-Za-z0-9+.-]{1,31}:"#, options: .regularExpression) != nil {
            return content
        }
        if content.range(of: #"^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?\.[A-Za-z]{2,}$"#,
                         options: .regularExpression) != nil {
            return "mailto:" + content
        }
        return nil
    }

    private func bareAutolink(in characters: [Character], at start: Int)
        -> (end: Int, destination: String)? {
        guard characters.indices.contains(start),
              characters[start] == "h" || characters[start] == "w" ||
                characters[start].isLetter || characters[start].isNumber else { return nil }
        let candidate = String(characters[start...])
        let pattern = #"^(?:https?://|www\.)[^\s<>]+|^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: candidate,
                                               range: NSRange(location: 0, length: (candidate as NSString).length)),
              match.range.location == 0 else { return nil }
        var spelling = (candidate as NSString).substring(with: match.range)
        while let last = spelling.last, ".,!?;:".contains(last) { spelling.removeLast() }
        while spelling.last == ")", spelling.filter({ $0 == ")" }).count > spelling.filter({ $0 == "(" }).count {
            spelling.removeLast()
        }
        guard !spelling.isEmpty else { return nil }
        let destination: String
        if spelling.hasPrefix("www.") {
            let host = String(spelling.dropFirst(4).prefix { !"/:?#".contains($0) })
            let labels = host.split(separator: ".", omittingEmptySubsequences: false)
            guard labels.count >= 2, labels.allSatisfy({ !$0.isEmpty }),
                  labels.suffix(2).allSatisfy({ !$0.contains("_") }) else { return nil }
            destination = "http://" + spelling
        }
        else if spelling.contains("@"), !spelling.contains("://") { destination = "mailto:" + spelling }
        else {
            guard let url = URLComponents(string: spelling),
                  url.host?.isEmpty == false else { return nil }
            destination = spelling
        }
        return (start + spelling.count, destination)
    }

    private func normalizeReference(_ label: String) -> String {
        label.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
    }

    private func referenceDefinitions(in document: MarkdownDocument) -> [String: String] {
        var result: [String: String] = [:]
        for block in document.blocks {
            if case .fencedCode = block.kind { continue }
            for line in block.source.components(separatedBy: "\n") {
                guard let definition = referenceDefinition(line), !definition.label.hasPrefix("^") else { continue }
                let key = normalizeReference(definition.label)
                if result[key] == nil { result[key] = definition.destination }
            }
        }
        return result
    }

    private func referenceDefinition(_ line: String) -> (label: String, destination: String)? {
        let pattern = #"^ {0,3}\[([^\]]+)\]:[ \t]*<?([^\s>]+)>?(?:[ \t]+(?:"[^"]*"|'[^']*'))?[ \t]*$"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)),
              match.range(at: 1).location != NSNotFound,
              match.range(at: 2).location != NSNotFound else { return nil }
        let text = line as NSString
        return (text.substring(with: match.range(at: 1)),
                NativeMarkdownTextDecoder.decode(text.substring(with: match.range(at: 2))))
    }
}
