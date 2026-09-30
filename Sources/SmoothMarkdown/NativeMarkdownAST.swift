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

/// Source-preserving CommonMark/GFM block scanner, independent of the editor codec.
struct NativeMarkdownASTParser {
    private struct Reference {
        let destination: String
        let title: String?
    }

    private struct Line {
        let text: String
        let raw: String
        let start: Int
        var end: Int { start + (raw as NSString).length }
        var isBlank: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    init() {}

    func parse(_ source: String) -> NativeMarkdownNode {
        let lines = sourceLines(source)
        let references = referenceDefinitions(in: lines)
        return .init(kind: .document, source: source,
                     sourceRange: NSRange(location: 0, length: (source as NSString).length),
                     children: scan(lines, source: source, references: references))
    }

    private func sourceLines(_ source: String) -> [Line] {
        let parts = source.components(separatedBy: "\n")
        var offset = 0
        return parts.enumerated().map { index, part in
            let raw = part + (index + 1 < parts.count ? "\n" : "")
            let line = Line(text: part.hasSuffix("\r") ? String(part.dropLast()) : part,
                            raw: raw, start: offset)
            offset += (raw as NSString).length
            return line
        }
    }

    private func scan(_ lines: [Line], source: String,
                      references: [String: Reference]) -> [NativeMarkdownNode] {
        var result: [NativeMarkdownNode] = []
        var index = 0
        func node(_ kind: NativeMarkdownNode.Kind, _ first: Int, _ limit: Int,
                  _ children: [NativeMarkdownNode] = []) -> NativeMarkdownNode {
            let start = lines[first].start
            let end = lines[limit - 1].end
            let range = NSRange(location: start, length: end - start)
            return .init(kind: kind, source: (source as NSString).substring(with: range),
                         sourceRange: range, children: children)
        }
        while index < lines.count {
            if lines[index].isBlank { index += 1; continue }
            let start = index
            let text = lines[index].text
            if let definition = referenceDefinition(text), !definition.label.hasPrefix("^") {
                result.append(node(.referenceDefinition(definition.label, definition.destination), start, start + 1))
                index += 1; continue
            }
            if let label = footnoteLabel(text) {
                index += 1
                while index < lines.count, !lines[index].isBlank,
                      (lines[index].text.hasPrefix("    ") || lines[index].text.hasPrefix("\t")) { index += 1 }
                result.append(node(.footnoteDefinition(label), start, index)); continue
            }
            if let fence = fenceOpen(text) {
                index += 1
                while index < lines.count, !fenceClose(lines[index].text, marker: fence.marker, count: fence.count) {
                    index += 1
                }
                if index < lines.count { index += 1 }
                result.append(node(.fencedCode(fence.info), start, index)); continue
            }
            if text.trimmingCharacters(in: .whitespaces).hasPrefix("$$") {
                index += 1
                while index < lines.count, !lines[index].text.contains("$$") { index += 1 }
                if index < lines.count { index += 1 }
                result.append(node(.blockMath, start, index)); continue
            }
            if let heading = heading(text) {
                let body = heading.body
                let offset = lines[start].start + (heading.prefix as NSString).length
                result.append(node(.heading(heading.level), start, start + 1,
                                   inline(body, offset: offset, references: references)))
                index += 1; continue
            }
            if isThematic(text) {
                result.append(node(.thematicBreak, start, start + 1)); index += 1; continue
            }
            if isTable(at: index, lines: lines) {
                index += 2
                while index < lines.count, !lines[index].isBlank, lines[index].text.contains("|") {
                    index += 1
                }
                let rowIndices = [start] + Array((start + 2)..<index)
                let rows = rowIndices.map { rowIndex -> NativeMarkdownNode in
                    let row = lines[rowIndex]
                    let cells = tableCells(row, references: references)
                    return .init(kind: .tableRow, source: row.text,
                                 sourceRange: NSRange(location: row.start, length: (row.text as NSString).length),
                                 children: cells)
                }
                result.append(node(.table, start, index, rows)); continue
            }
            if listMarker(text) != nil {
                let parsed = list(at: index, lines: lines, source: source, references: references)
                result.append(parsed.node)
                index = parsed.next; continue
            }
            if quotePrefix(text) != nil {
                index += 1
                while index < lines.count, !lines[index].isBlank,
                      (quotePrefix(lines[index].text) != nil || !interruptsParagraph(at: index, lines: lines)) {
                    index += 1
                }
                let paragraphs = (start..<index).compactMap { cursor -> NativeMarkdownNode? in
                    let line = lines[cursor]
                    guard let prefix = quotePrefix(line.text) else { return nil }
                    let body = String(line.text.dropFirst(prefix.count))
                    guard !body.isEmpty else { return nil }
                    let offset = line.start + (prefix as NSString).length
                    return .init(kind: .paragraph, source: body,
                                 sourceRange: NSRange(location: offset, length: (body as NSString).length),
                                 children: inline(body, offset: offset, references: references))
                }
                result.append(node(.blockQuote, start, index, paragraphs)); continue
            }
            if text.hasPrefix("    ") || text.hasPrefix("\t") {
                index += 1
                while index < lines.count,
                      lines[index].isBlank || lines[index].text.hasPrefix("    ") || lines[index].text.hasPrefix("\t") {
                    index += 1
                }
                result.append(node(.indentedCode, start, index)); continue
            }
            if htmlStart(text) {
                index += 1
                while index < lines.count, !lines[index].isBlank { index += 1 }
                result.append(node(.htmlBlock, start, index)); continue
            }
            index += 1
            while index < lines.count, !lines[index].isBlank,
                  setextLevel(lines[index].text) == nil,
                  !interruptsParagraph(at: index, lines: lines) { index += 1 }
            if index < lines.count, let level = setextLevel(lines[index].text) {
                let content = lines[start..<index].map(\.text).joined(separator: "\n")
                let offset = lines[start].start
                result.append(node(.heading(level), start, index + 1,
                                   inline(content, offset: offset, references: references)))
                index += 1; continue
            }
            let end = index
            let content = lines[start..<end].map {
                $0.text + ($0.raw.hasSuffix("\r\n") ? "\r" : "")
            }.joined(separator: "\n")
            result.append(node(.paragraph, start, end,
                               inline(content, offset: lines[start].start, references: references)))
        }
        return result
    }

    private func heading(_ line: String) -> (level: Int, prefix: String, body: String)? {
        guard let match = match(#"^( {0,3})(#{1,6})(?:[ \t]+|$)(.*)$"#, line) else { return nil }
        let prefix = match[1] + match[2] + String(line.dropFirst(match[1].count + match[2].count)
            .prefix(while: { $0 == " " || $0 == "\t" }))
        let body = match[3].replacingOccurrences(of: #"[ \t]+#+[ \t]*$"#, with: "",
                                                   options: .regularExpression)
        return (match[2].count, prefix, body)
    }

    private func fenceOpen(_ line: String) -> (marker: Character, count: Int, info: String)? {
        let trimmed = String(line.drop(while: { $0 == " " }))
        guard line.count - trimmed.count <= 3, let marker = trimmed.first,
              marker == "`" || marker == "~" else { return nil }
        let count = trimmed.prefix(while: { $0 == marker }).count
        guard count >= 3 else { return nil }
        let info = String(trimmed.dropFirst(count)).trimmingCharacters(in: .whitespaces)
        guard marker != "`" || !info.contains("`") else { return nil }
        return (marker, count, info)
    }

    private func fenceClose(_ line: String, marker: Character, count: Int) -> Bool {
        let trimmed = String(line.drop(while: { $0 == " " }))
        guard line.count - trimmed.count <= 3 else { return false }
        let run = trimmed.prefix(while: { $0 == marker }).count
        return run >= count && trimmed.dropFirst(run).trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func isThematic(_ line: String) -> Bool {
        guard let match = match(#"^ {0,3}([*_-])(?:[ \t]*\1){2,}[ \t]*$"#, line) else { return false }
        return !match[0].isEmpty
    }

    private func setextLevel(_ line: String) -> Int? {
        if match(#"^ {0,3}=+[ \t]*$"#, line) != nil { return 1 }
        if match(#"^ {0,3}-+[ \t]*$"#, line) != nil { return 2 }
        return nil
    }

    private func htmlStart(_ line: String) -> Bool {
        match(#"^ {0,3}(?:<!--|<![A-Z]|<\?|</?(?:script|pre|style|div|table|section|details|p)(?:[ \t>/]))"#, line.lowercased()) != nil
    }

    private func footnoteLabel(_ line: String) -> String? {
        match(#"^ {0,3}\[\^([^]]+)\]:"#, line)?[1]
    }

    private func quotePrefix(_ line: String) -> String? {
        match(#"^( {0,3}>[ ]?)"#, line)?[1]
    }

    private func interruptsParagraph(at index: Int, lines: [Line]) -> Bool {
        let text = lines[index].text
        return heading(text) != nil || fenceOpen(text) != nil || isThematic(text) ||
            quotePrefix(text) != nil || htmlStart(text) ||
            (listMarker(text).map {
                text.count > $0.prefix.count && (!$0.ordered || $0.number == 1)
            } ?? false)
    }

    private func isTable(at index: Int, lines: [Line]) -> Bool {
        guard index + 1 < lines.count, lines[index].text.contains("|") else { return false }
        let cells = lines[index + 1].text.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "|"))
            .split(separator: "|", omittingEmptySubsequences: false)
        return !cells.isEmpty && cells.allSatisfy {
            $0.trimmingCharacters(in: .whitespaces)
                .range(of: #"^:?-{3,}:?$"#, options: .regularExpression) != nil
        }
    }

    private func tableCells(_ line: Line, references: [String: Reference]) -> [NativeMarkdownNode] {
        let text = line.text as NSString
        var spans: [NSRange] = []
        var start = 0
        for index in 0..<text.length where text.character(at: index) == 124 {
            spans.append(NSRange(location: start, length: index - start))
            start = index + 1
        }
        spans.append(NSRange(location: start, length: text.length - start))
        if spans.first?.length == 0 { spans.removeFirst() }
        if spans.last?.length == 0 { spans.removeLast() }
        return spans.map { span in
            var location = span.location
            var length = span.length
            while length > 0, [UInt16(32), 9].contains(text.character(at: location)) {
                location += 1; length -= 1
            }
            while length > 0, [UInt16(32), 9].contains(text.character(at: location + length - 1)) {
                length -= 1
            }
            let content = text.substring(with: NSRange(location: location, length: length))
            let offset = line.start + location
            return .init(kind: .tableCell, source: content,
                         sourceRange: NSRange(location: offset, length: length),
                         children: inline(content, offset: offset, references: references))
        }
    }

    private func listMarker(_ line: String) -> (indent: Int, prefix: String, ordered: Bool, number: Int, style: Character)? {
        guard let parts = match(#"^([ \t]*)([-+*]|[0-9]{1,9}[.)])([ \t]+|$)(.*)$"#, line) else { return nil }
        let indent = parts[1].reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
        let marker = parts[2]
        return (indent, parts[1] + marker + parts[3], marker.last == "." || marker.last == ")",
                Int(marker.dropLast()) ?? 1, marker.last!)
    }

    private func list(at start: Int, lines: [Line], source: String,
                      references: [String: Reference]) -> (node: NativeMarkdownNode, next: Int) {
        let first = listMarker(lines[start].text)!
        var index = start
        var items: [NativeMarkdownNode] = []
        while index < lines.count, let marker = listMarker(lines[index].text),
              marker.indent == first.indent, marker.ordered == first.ordered,
              marker.style == first.style {
            let itemStart = index
            index += 1
            var children: [NativeMarkdownNode] = []
            let itemLine = lines[itemStart]
            var body = String(itemLine.text.dropFirst(marker.prefix.count))
            let task = match(#"^\[([ xX])\][ \t]+"#, body)
            let checked: Bool?
            if let task {
                checked = task[1].lowercased() == "x"
                body = String(body.dropFirst(task[0].count))
            } else { checked = nil }
            let bodyOffset = itemLine.start + (marker.prefix as NSString).length +
                (task.map { ($0[0] as NSString).length } ?? 0)
            children += inline(body, offset: bodyOffset, references: references)
            while index < lines.count {
                if let nested = listMarker(lines[index].text), nested.indent > first.indent {
                    let parsed = list(at: index, lines: lines, source: source, references: references)
                    children.append(parsed.node)
                    index = parsed.next
                    continue
                }
                if lines[index].isBlank {
                    let next = index + 1
                    if next < lines.count, let nextMarker = listMarker(lines[next].text),
                       nextMarker.indent >= first.indent {
                        index = next
                    }
                    break
                }
                if let nextMarker = listMarker(lines[index].text), nextMarker.indent <= first.indent { break }
                if interruptsParagraph(at: index, lines: lines) { break }
                index += 1
            }
            let end = lines[index - 1].end
            let range = NSRange(location: itemLine.start, length: end - itemLine.start)
            items.append(.init(kind: .listItem(checked: checked),
                               source: (source as NSString).substring(with: range),
                               sourceRange: range, children: children))
            if index >= lines.count || listMarker(lines[index].text)?.indent != first.indent ||
                listMarker(lines[index].text)?.style != first.style { break }
        }
        let end = items.last.map { NSMaxRange($0.sourceRange) } ?? lines[start].end
        let range = NSRange(location: lines[start].start, length: end - lines[start].start)
        return (.init(kind: .list(ordered: first.ordered), source: (source as NSString).substring(with: range),
                      sourceRange: range, children: items), index)
    }

    private func match(_ pattern: String, _ source: String) -> [String]? {
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let result = expression.firstMatch(in: source,
                                                 range: NSRange(location: 0, length: (source as NSString).length))
        else { return nil }
        let text = source as NSString
        return (0..<result.numberOfRanges).map {
            result.range(at: $0).location == NSNotFound ? "" : text.substring(with: result.range(at: $0))
        }
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
            flushPlain(until: index)
            append(.text, start: index, end: index + run)
            index += run
            plainStart = index
        }
        flushPlain(until: characters.count)
        return NativeMarkdownEmphasisParser.resolve(result, source: source, offset: offset)
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
        label.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            .folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    private func referenceDefinitions(in lines: [Line]) -> [String: Reference] {
        var result: [String: Reference] = [:]
        var fence: (marker: Character, count: Int)?
        for line in lines {
            if let active = fence {
                if fenceClose(line.text, marker: active.marker, count: active.count) { fence = nil }
                continue
            }
            if let open = fenceOpen(line.text) {
                fence = (open.marker, open.count)
                continue
            }
            guard let definition = referenceDefinition(line.text), !definition.label.hasPrefix("^") else { continue }
            let key = normalizeReference(definition.label)
            if result[key] == nil {
                result[key] = Reference(destination: definition.destination, title: definition.title)
            }
        }
        return result
    }

    private func referenceDefinition(_ line: String) -> (label: String, destination: String, title: String?)? {
        let pattern = #"^ {0,3}\[((?:\\.|[^\\\]])+)\]:[ \t]*<?([^\s>]+)>?(?:[ \t]+(?:"([^"]*)"|'([^']*)'|\(([^)]*)\)))?[ \t]*$"#
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
