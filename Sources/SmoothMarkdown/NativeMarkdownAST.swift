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
    let title: String?

    var semanticText: String? {
        switch kind {
        case .text: NativeMarkdownTextDecoder.decode(source)
        case .inlineCode: NativeMarkdownTextDecoder.codeSpan(source)
        default: nil
        }
    }

    init(kind: Kind, source: String, sourceRange: NSRange,
         children: [NativeMarkdownNode] = [], title: String? = nil) {
        self.kind = kind
        self.source = source
        self.sourceRange = sourceRange
        self.children = children
        self.title = title
    }
}

/// The first native AST pass reuses the editor's source-preserving block scanner.
/// It deliberately keeps unrecognized blocks as raw nodes, rather than dropping source.
struct NativeMarkdownASTParser {
    private struct Reference {
        let destination: String
        let title: String?
    }

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
                       references: [String: Reference]) -> NativeMarkdownNode {
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
                           references: [String: Reference]) -> [NativeMarkdownNode] {
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
                        references: [String: Reference]) -> [NativeMarkdownNode] {
        let characters = Array(source)
        var utf16Positions = [Int](repeating: 0, count: characters.count + 1)
        for position in characters.indices {
            utf16Positions[position + 1] = utf16Positions[position] + String(characters[position]).utf16.count
        }
        var result: [NativeMarkdownNode] = []
        var index = 0
        var plainStart = 0

        func utf16Offset(_ position: Int) -> Int { utf16Positions[position] }
        func isLineEnding(_ character: Character) -> Bool {
            character == "\n" || character == "\r" || character == "\r\n"
        }
        func append(_ kind: NativeMarkdownNode.Kind, start: Int, end: Int,
                    contentStart: Int? = nil, contentEnd: Int? = nil,
                    parseContent: Bool = true, title: String? = nil) {
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
                                                     length: (spelling as NSString).length),
                                children: children, title: title))
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
        func closingBracket(after start: Int) -> Int? {
            var depth = 0
            var cursor = start
            while cursor < characters.count {
                if characters[cursor] == "\\" {
                    cursor += min(2, characters.count - cursor)
                    continue
                }
                if characters[cursor] == "`" {
                    let run = characters[cursor...].prefix(while: { $0 == "`" }).count
                    if let end = closingBackticks(run, after: cursor + run) {
                        cursor = end + run
                        continue
                    }
                }
                if characters[cursor] == "[" { depth += 1 }
                if characters[cursor] == "]" {
                    if depth == 0 { return cursor }
                    depth -= 1
                }
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
        func closingBackticks(_ count: Int, after start: Int) -> Int? {
            var cursor = start
            while cursor < characters.count {
                guard characters[cursor] == "`" else { cursor += 1; continue }
                let run = characters[cursor...].prefix(while: { $0 == "`" }).count
                if run == count { return cursor }
                cursor += run
            }
            return nil
        }
        func isPunctuation(_ character: Character?) -> Bool {
            guard let character else { return false }
            return character.unicodeScalars.allSatisfy {
                CharacterSet.punctuationCharacters.contains($0) || CharacterSet.symbols.contains($0)
            }
        }
        func delimiterFlags(at position: Int, run: Int, marker: Character)
            -> (opens: Bool, closes: Bool) {
            let previous = position > 0 ? characters[position - 1] : nil
            let next = position + run < characters.count ? characters[position + run] : nil
            let previousSpace = previous?.isWhitespace ?? true
            let nextSpace = next?.isWhitespace ?? true
            let previousPunctuation = isPunctuation(previous)
            let nextPunctuation = isPunctuation(next)
            let left = !nextSpace && (!nextPunctuation || previousSpace || previousPunctuation)
            let right = !previousSpace && (!previousPunctuation || nextSpace || nextPunctuation)
            if marker == "_" {
                return (left && (!right || previousPunctuation),
                        right && (!left || nextPunctuation))
            }
            return (left, right)
        }
        func closingEmphasis(_ marker: Character, count: Int, after start: Int) -> Int? {
            var cursor = start
            while cursor < characters.count {
                if characters[cursor] == "\\" {
                    cursor += min(2, characters.count - cursor)
                    continue
                }
                guard characters[cursor] == marker else { cursor += 1; continue }
                let run = characters[cursor...].prefix(while: { $0 == marker }).count
                if run >= count, delimiterFlags(at: cursor, run: run, marker: marker).closes {
                    return cursor
                }
                cursor += run
            }
            return nil
        }
        func linkTail(after opening: Int) -> (destination: String, title: String?, end: Int)? {
            guard characters.indices.contains(opening), characters[opening] == "(" else { return nil }
            var cursor = opening + 1
            func skipSpace() -> Bool {
                var lineEndings = 0
                while cursor < characters.count, characters[cursor] == " " ||
                    characters[cursor] == "\t" || isLineEnding(characters[cursor]) {
                    if isLineEnding(characters[cursor]) { lineEndings += 1 }
                    if lineEndings > 1 { return false }
                    cursor += 1
                }
                return true
            }
            guard skipSpace(), cursor < characters.count else { return nil }
            let destinationStart: Int
            let destinationEnd: Int
            if characters[cursor] == "<" {
                cursor += 1
                destinationStart = cursor
                while cursor < characters.count {
                    if characters[cursor] == "\\", cursor + 1 < characters.count {
                        cursor += 2; continue
                    }
                    if isLineEnding(characters[cursor]) || characters[cursor] == "<" { return nil }
                    if characters[cursor] == ">" { break }
                    cursor += 1
                }
                guard cursor < characters.count, characters[cursor] == ">" else { return nil }
                destinationEnd = cursor
                cursor += 1
            } else {
                destinationStart = cursor
                var depth = 0
                while cursor < characters.count {
                    let character = characters[cursor]
                    if character == "\\", cursor + 1 < characters.count {
                        cursor += 2; continue
                    }
                    if character.isWhitespace || character == "<" || character == ">" ||
                        character.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }) {
                        break
                    }
                    if character == "(" {
                        depth += 1
                        if depth > 32 { return nil }
                    } else if character == ")" {
                        if depth == 0 { break }
                        depth -= 1
                    }
                    cursor += 1
                }
                guard depth == 0 else { return nil }
                destinationEnd = cursor
            }
            let destination = NativeMarkdownTextDecoder.decode(
                String(characters[destinationStart..<destinationEnd]))
            let separatorStart = cursor
            guard skipSpace(), cursor < characters.count else { return nil }
            var title: String?
            let titleDelimiter = characters[cursor] == "\"" || characters[cursor] == "'" ||
                characters[cursor] == "("
            if cursor > separatorStart && titleDelimiter {
                let delimiter = characters[cursor] == "(" ? ")" : characters[cursor]
                cursor += 1
                let titleStart = cursor
                var previousNewline = false
                while cursor < characters.count {
                    if characters[cursor] == "\\", cursor + 1 < characters.count {
                        cursor += 2; previousNewline = false; continue
                    }
                    if characters[cursor] == delimiter { break }
                    if isLineEnding(characters[cursor]) {
                        if previousNewline { return nil }
                        previousNewline = true
                    } else if characters[cursor] != " " && characters[cursor] != "\t" {
                        previousNewline = false
                    }
                    cursor += 1
                }
                guard cursor < characters.count else { return nil }
                title = NativeMarkdownTextDecoder.decode(String(characters[titleStart..<cursor]))
                cursor += 1
                guard skipSpace(), cursor < characters.count else { return nil }
            }
            guard characters[cursor] == ")" else { return nil }
            return (destination, title, cursor + 1)
        }

        while index < characters.count {
            if characters[index] == "\\", index + 1 < characters.count {
                if isLineEnding(characters[index + 1]) {
                    flushPlain(until: index)
                    append(.hardBreak, start: index, end: index + 2)
                    index += 2; plainStart = index; continue
                }
                index += 2; continue
            }
            if isLineEnding(characters[index]) {
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
                if let end = closingBackticks(run, after: index + run) {
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
                   let close = closingBracket(after: open + 1) {
                    let label = String(characters[(open + 1)..<close])
                    var destination: String?
                    var title: String?
                    var end = close + 1
                    if end < characters.count, characters[end] == "(",
                       let parsed = linkTail(after: end) {
                        destination = parsed.destination
                        title = parsed.title
                        end = parsed.end
                    } else if end < characters.count, characters[end] == "[",
                              let referenceEnd = closing(["]"], after: end + 1) {
                        let reference = String(characters[(end + 1)..<referenceEnd])
                        let match = references[normalizeReference(reference.isEmpty ? label : reference)]
                        destination = match?.destination
                        title = match?.title
                        end = referenceEnd + 1
                    } else {
                        let match = references[normalizeReference(label)]
                        destination = match?.destination
                        title = match?.title
                    }
                    let labelChildren = inline(label, offset: offset + utf16Offset(open + 1),
                                               references: references)
                    let containsLink = labelChildren.contains { child in
                        if case .link = child.kind { return true }
                        return child.children.contains { if case .link = $0.kind { return true }; return false }
                    }
                    if let destination, image || !containsLink {
                        flushPlain(until: index)
                        append(image ? .image(destination) : .link(destination), start: index,
                               end: end, contentStart: open + 1, contentEnd: close, title: title)
                        index = end; plainStart = index; continue
                    }
                }
            }
            if characters[index] == "~" {
                let run = characters[index...].prefix(while: { $0 == "~" }).count
                guard run <= 2, let end = closingTildes(run, after: index + run),
                      end > index + run else { index += max(1, run); continue }
                flushPlain(until: index)
                append(.strikethrough, start: index, end: end + run,
                       contentStart: index + run, contentEnd: end)
                index = end + run; plainStart = index; continue
            }
            guard characters[index] == "*" || characters[index] == "_" else {
                index += 1; continue
            }
            let marker = characters[index]
            let run = characters[index...].prefix(while: { $0 == marker }).count
            guard delimiterFlags(at: index, run: run, marker: marker).opens else {
                index += run; continue
            }
            let count = min(run, 2)
            if let end = closingEmphasis(marker, count: count, after: index + count),
               end > index + count {
                flushPlain(until: index)
                append(count == 2 ? .strong : .emphasis, start: index, end: end + count,
                       contentStart: index + count, contentEnd: end)
                index = end + count; plainStart = index; continue
            }
            index += run
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

    private func referenceDefinitions(in document: MarkdownDocument) -> [String: Reference] {
        var result: [String: Reference] = [:]
        for block in document.blocks {
            if case .fencedCode = block.kind { continue }
            for line in block.source.components(separatedBy: "\n") {
                guard let definition = referenceDefinition(line), !definition.label.hasPrefix("^") else { continue }
                let key = normalizeReference(definition.label)
                if result[key] == nil {
                    result[key] = Reference(destination: definition.destination, title: definition.title)
                }
            }
        }
        return result
    }

    private func referenceDefinition(_ line: String) -> (label: String, destination: String, title: String?)? {
        let pattern = #"^ {0,3}\[([^\]]+)\]:[ \t]*<?([^\s>]+)>?(?:[ \t]+(?:"([^"]*)"|'([^']*)'|\(([^)]*)\)))?[ \t]*$"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)),
              match.range(at: 1).location != NSNotFound,
              match.range(at: 2).location != NSNotFound else { return nil }
        let text = line as NSString
        let title = (3...5).first(where: { match.range(at: $0).location != NSNotFound })
            .map { NativeMarkdownTextDecoder.decode(text.substring(with: match.range(at: $0))) }
        return (text.substring(with: match.range(at: 1)),
                NativeMarkdownTextDecoder.decode(text.substring(with: match.range(at: 2))), title)
    }
}
