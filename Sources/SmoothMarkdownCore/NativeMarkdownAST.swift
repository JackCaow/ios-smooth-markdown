import Foundation

/// A source-preserving tree owned by SmoothMarkdown. The source ranges use UTF-16 offsets.
public struct NativeMarkdownNode: Equatable {
    public enum Kind: Equatable {
        case document, paragraph, heading(Int), fencedCode(String), indentedCode, table, tableRow, tableCell
        case list(ordered: Bool), listItem(checked: Bool?), blockQuote, thematicBreak
        case text, strong, emphasis, strikethrough, inlineCode, inlineMath
        case softBreak, hardBreak, inlineHTML
        case blockMath, footnoteReference(String), footnoteDefinition(String)
        case referenceDefinition(String, String)
        case link(String), image(String), htmlBlock, raw
    }

    public let kind: Kind
    public let source: String
    public let sourceRange: NSRange
    public let children: [NativeMarkdownNode]
    public let title: String?
    public let isTight: Bool?
    public let listStart: Int?
    public let literalText: String?
    public let tableAlignments: [String?]

    public var semanticText: String? {
        switch kind {
        case .text: literalText ?? NativeMarkdownTextDecoder.decode(source)
        case .inlineCode: literalText ?? NativeMarkdownTextDecoder.codeSpan(source)
        case .fencedCode: literalText ?? NativeMarkdownCodeSemantics.text(source: source, fenced: true)
        case .indentedCode: literalText ?? NativeMarkdownCodeSemantics.text(source: source, fenced: false)
        case .inlineHTML, .htmlBlock: literalText
        default: nil
        }
    }

    public init(kind: Kind, source: String, sourceRange: NSRange,
         children: [NativeMarkdownNode] = [], title: String? = nil,
         isTight: Bool? = nil, listStart: Int? = nil, literalText: String? = nil,
         tableAlignments: [String?] = []) {
        self.kind = kind
        self.source = source
        self.sourceRange = sourceRange
        self.children = children
        self.title = title
        self.isTight = isTight
        self.listStart = listStart
        self.literalText = literalText
        self.tableAlignments = tableAlignments
    }
}

/// Source-preserving CommonMark/GFM block scanner, independent of the editor codec.
public struct NativeMarkdownASTParser {
    private struct Reference {
        let destination: String
        let title: String?
    }

    private struct Line {
        let text: String
        let raw: String
        let start: Int
        var sourceEnd: Int? = nil
        var projected = false
        var lazyContinuation = false
        var virtualIndent = 0
        var end: Int { sourceEnd ?? start + (raw as NSString).length }
        var isBlank: Bool { text.allSatisfy { $0 == " " || $0 == "\t" } }
    }

    private let enableGFM: Bool

    private let enableNativeExtensions: Bool
    public init(enableGFM: Bool = true) { self.enableGFM = enableGFM; self.enableNativeExtensions = true }
    public init(enableGFM: Bool = true, enableNativeExtensions: Bool) {
        self.enableGFM = enableGFM; self.enableNativeExtensions = enableNativeExtensions
    }

    public func parse(_ source: String) -> NativeMarkdownNode {
        if let native = RustMarkdownBridge.parse(source, enableGFM: enableGFM, enableExtensions: enableNativeExtensions) { return filterHTML(native) }
        let lines = sourceLines(source)
        let references = referenceDefinitions(in: scan(lines, source: source, references: [:]))
        return .init(kind: .document, source: source,
                     sourceRange: NSRange(location: 0, length: (source as NSString).length),
                     children: scan(lines, source: source, references: references).map(filterHTML))
    }

    private func filterHTML(_ node: NativeMarkdownNode) -> NativeMarkdownNode {
        guard enableGFM else { return node }
        let filtered = node.kind == .inlineHTML || node.kind == .htmlBlock
            ? NativeMarkdownHTMLTagFilter.filter(node.literalText ?? node.source) : node.literalText
        return .init(kind: node.kind, source: node.source, sourceRange: node.sourceRange,
                     children: node.children.map(filterHTML), title: node.title,
                     isTight: node.isTight, listStart: node.listStart,
                     literalText: filtered, tableAlignments: node.tableAlignments)
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
                  _ children: [NativeMarkdownNode] = [], title: String? = nil,
                  literalText: String? = nil) -> NativeMarkdownNode {
            let start = lines[first].start
            let end = lines[limit - 1].end
            let range = NSRange(location: start, length: end - start)
            return .init(kind: kind, source: (source as NSString).substring(with: range),
                         sourceRange: range, children: children, title: title,
                         literalText: literalText)
        }
        while index < lines.count {
            if lines[index].isBlank { index += 1; continue }
            let start = index
            let text = lines[index].text
            if let parsed = referenceDefinition(at: index, in: lines), !parsed.definition.label.hasPrefix("^") {
                let definition = parsed.definition
                result.append(node(.referenceDefinition(definition.label, definition.destination), start, parsed.next,
                                   title: definition.title))
                index = parsed.next; continue
            }
            if enableNativeExtensions, let label = footnoteLabel(text) {
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
                result.append(node(.fencedCode(fence.info), start, index,
                                   literalText: projectedCodeText(lines[start..<index], fenced: true)))
                continue
            }
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            if enableNativeExtensions, trimmed.hasPrefix("$$") || backslashMathOpen(trimmed) {
                let closing = trimmed.hasPrefix("$$") ? "$$" : "\\]"
                var body = String(trimmed.dropFirst(2))
                index += 1
                while mathClosing(body, delimiter: closing) == nil, index < lines.count {
                    body += "\n" + lines[index].text; index += 1
                }
                let close = mathClosing(body, delimiter: closing)
                let literal = (close.map { String(body[..<$0.lowerBound]) } ?? body).trimmingCharacters(in: .whitespacesAndNewlines)
                var math = node(.blockMath, start, index, literalText: literal)
                var trailing: NativeMarkdownNode?
                if closing == #"\]"#, close != nil {
                    let last = lines[index - 1]
                    let prefix = index == start + 1 ? last.text.count - last.text.trimmingCharacters(in: .whitespaces).count + 2 : 0
                    let searchStart = last.text.index(last.text.startIndex, offsetBy: prefix)
                    let suffix = String(last.text[searchStart...])
                    let end = prefix + suffix.distance(from: suffix.startIndex, to: mathClosing(suffix, delimiter: closing)!.upperBound)
                    let endIndex = last.text.index(last.text.startIndex, offsetBy: end)
                    let sourceEnd = last.start + String(last.text[..<endIndex]).utf16.count - last.virtualIndent
                    let range = NSRange(location: math.sourceRange.location, length: sourceEnd - math.sourceRange.location)
                    math = .init(kind: .blockMath, source: (source as NSString).substring(with: range), sourceRange: range, literalText: literal)
                    let text = String(last.text[endIndex...])
                    if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        let line = Line(text: text, raw: text + (last.raw.hasSuffix("\n") ? "\n" : ""), start: sourceEnd, sourceEnd: last.end, projected: last.projected)
                        let range = NSRange(location: sourceEnd, length: last.end - sourceEnd)
                        trailing = .init(kind: .paragraph, source: (source as NSString).substring(with: range), sourceRange: range,
                            children: paragraphInlines([line], source: source, references: references))
                    }
                }
                result.append(math)
                if let trailing { result.append(trailing) }
                continue
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
            if enableGFM, isTable(at: index, lines: lines) {
                let alignments = tableSpans(lines[index + 1].text).map { span -> String? in
                    let cell = (lines[index + 1].text as NSString).substring(with: span)
                    if cell.hasPrefix(":") && cell.hasSuffix(":") { return "center" }
                    if cell.hasPrefix(":") { return "left" }
                    if cell.hasSuffix(":") { return "right" }
                    return nil
                }
                index += 2
                while index < lines.count, !lines[index].isBlank, !interruptsParagraph(at: index, lines: lines) {
                    index += 1
                }
                let rowIndices = [start] + Array((start + 2)..<index)
                let rows = rowIndices.map { rowIndex -> NativeMarkdownNode in
                    let row = lines[rowIndex]
                    var cells = Array(tableCells(row, references: references).prefix(alignments.count))
                    while cells.count < alignments.count {
                        cells.append(.init(kind: .tableCell, source: "", sourceRange: NSRange(location: row.start + (row.text as NSString).length, length: 0)))
                    }
                    return .init(kind: .tableRow, source: row.text,
                                 sourceRange: NSRange(location: row.start, length: (row.text as NSString).length),
                                 children: cells)
                }
                let table = node(.table, start, index, rows)
                result.append(.init(kind: .table, source: table.source, sourceRange: table.sourceRange, children: rows, tableAlignments: alignments)); continue
            }
            if listMarker(text) != nil {
                let parsed = list(at: index, lines: lines, source: source, references: references)
                result.append(parsed.node)
                index = parsed.next; continue
            }
            if quotePrefix(text) != nil {
                index += 1
                var priorWasParagraph = quoteParagraphCanContinue(
                    String(text.dropFirst(quotePrefix(text)!.count)))
                while index < lines.count {
                    if let prefix = quotePrefix(lines[index].text) {
                        priorWasParagraph = quoteParagraphCanContinue(
                            String(lines[index].text.dropFirst(prefix.count)))
                        index += 1
                    } else if priorWasParagraph, !lines[index].isBlank,
                              !interruptsParagraph(at: index, lines: lines) {
                        index += 1
                    } else { break }
                }
                let contents = lines[start..<index].map(projectQuoteLine)
                result.append(node(.blockQuote, start, index,
                                   scan(contents, source: source, references: references))); continue
            }
            if indentation(text) >= 4 {
                index += 1
                while index < lines.count,
                      lines[index].isBlank || indentation(lines[index].text) >= 4 {
                    index += 1
                }
                result.append(node(.indentedCode, start, index,
                                   literalText: projectedCodeText(lines[start..<index], fenced: false)))
                continue
            }
            if let ending = NativeMarkdownHTMLBlock.end(for: text) {
                index += 1
                if !ending.matches(text) {
                    while index < lines.count {
                        if ending.matches(lines[index].text) {
                            if case .marker = ending { index += 1 }
                            break
                        }
                        index += 1
                    }
                }
                let projected = lines[start..<index].contains(where: \.projected)
                result.append(node(.htmlBlock, start, index,
                                   literalText: projected ? lines[start..<index].map(\.raw).joined() : nil))
                continue
            }
            index += 1
            while index < lines.count, !lines[index].isBlank,
                  !(enableNativeExtensions && (lines[index].text.trimmingCharacters(in: .whitespaces).hasPrefix("$$") || backslashMathOpen(lines[index].text.trimmingCharacters(in: .whitespaces)))),
                  (lines[index].lazyContinuation ||
                   (setextLevel(lines[index].text) == nil &&
                    !interruptsParagraph(at: index, lines: lines))) { index += 1 }
            if index < lines.count, !lines[index].lazyContinuation,
               let level = setextLevel(lines[index].text) {
                let content = lines[start..<index].map(\.text).joined(separator: "\n")
                let offset = lines[start].start
                result.append(node(.heading(level), start, index + 1,
                                   inline(content, offset: offset, references: references,
                                          trimTrailingWhitespace: true, trimLeadingWhitespace: true)))
                index += 1; continue
            }
            let end = index
            result.append(node(.paragraph, start, end,
                               paragraphInlines(Array(lines[start..<end]), source: source,
                                                references: references)))
        }
        return result
    }

    private func projectedCodeText(_ lines: ArraySlice<Line>, fenced: Bool) -> String? {
        guard lines.contains(where: \.projected) else { return nil }
        let markdown = lines.map(\.raw).joined()
        return NativeMarkdownCodeSemantics.text(source: markdown, fenced: fenced)
    }

    private func paragraphInlines(_ lines: [Line], source: String,
                                  references: [String: Reference]) -> [NativeMarkdownNode] {
        guard let first = lines.first else { return [] }
        if lines.count > 1, !first.projected, first.text.contains("](") {
            let content = lines.map { $0.text + ($0.raw.hasSuffix("\r\n") ? "\r" : "") }
                .joined(separator: "\n")
            return inline(content, offset: first.start, references: references,
                          trimTrailingWhitespace: true, trimLeadingWhitespace: true)
        }
        if lines.allSatisfy({ !$0.projected && indentation($0.text) == 0 }) {
            let content = lines.map {
                $0.text + ($0.raw.hasSuffix("\r\n") ? "\r" : "")
            }.joined(separator: "\n")
            return inline(content, offset: first.start, references: references,
                          trimTrailingWhitespace: true)
        }
        var children: [NativeMarkdownNode] = []
        for (position, line) in lines.enumerated() {
            let leading = line.text.prefix { $0 == " " || $0 == "\t" }
            let removed = line.projected || position > 0 ? leading.count : min(3, leading.count)
            let prefix = String(leading.prefix(removed))
            let body = String(line.text.dropFirst(removed))
            let trailing = body.reversed().prefix { $0 == " " || $0 == "\t" }.count
            let hardBreak = position + 1 < lines.count &&
                (trailing >= 2 || (trailing == 0 && body.hasSuffix("\\")))
            let visible = String(body.dropLast(trailing + (hardBreak && trailing == 0 ? 1 : 0)))
            children += inline(visible, offset: line.start + (prefix as NSString).length - line.virtualIndent,
                               references: references,
                               trimTrailingWhitespace: position == lines.count - 1)
            if position + 1 < lines.count {
                let breakStart = line.start + (prefix as NSString).length + (visible as NSString).length
                let breakRange = NSRange(location: breakStart, length: max(0, line.end - breakStart))
                if breakRange.length > 0 {
                    let spelling = (source as NSString).substring(with: breakRange)
                    children.append(.init(kind: hardBreak ? .hardBreak : .softBreak,
                                          source: spelling, sourceRange: breakRange))
                }
            }
        }
        return children
    }

    private func heading(_ line: String) -> (level: Int, prefix: String, body: String)? {
        guard let match = match(#"^( {0,3})(#{1,6})(?:[ \t]+|$)(.*)$"#, line) else { return nil }
        let prefix = match[1] + match[2] + String(line.dropFirst(match[1].count + match[2].count)
            .prefix(while: { $0 == " " || $0 == "\t" }))
        let body = match[3].replacingOccurrences(of: #"[ \t]+#+[ \t]*$"#, with: "",
                                                   options: .regularExpression)
            .replacingOccurrences(of: #"[ \t]+$"#, with: "", options: .regularExpression)
        return (match[2].count, prefix, body.allSatisfy({ $0 == "#" }) ? "" : body)
    }

    private func indentation(_ line: String) -> Int {
        var width = 0
        for character in line {
            if character == " " { width += 1 }
            else if character == "\t" { width += 4 - width % 4 }
            else { break }
        }
        return width
    }

    private func displayColumn(_ text: String) -> Int {
        text.reduce(0) { column, character in
            column + (character == "\t" ? 4 - column % 4 : 1)
        }
    }

    private func fenceOpen(_ line: String) -> (marker: Character, count: Int, info: String)? {
        let trimmed = String(line.drop(while: { $0 == " " }))
        guard line.count - trimmed.count <= 3, let marker = trimmed.first,
              marker == "`" || marker == "~" else { return nil }
        let count = trimmed.prefix(while: { $0 == marker }).count
        guard count >= 3 else { return nil }
        let info = String(trimmed.dropFirst(count)).trimmingCharacters(in: .whitespaces)
        guard marker != "`" || !info.contains("`") else { return nil }
        return (marker, count, NativeMarkdownTextDecoder.decode(info))
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

    private func backslashMathOpen(_ text: String) -> Bool {
        guard text.hasPrefix(#"\["#) else { return false }
        let payload = String(text.dropFirst(2))
        if mathClosing(payload, delimiter: #"\]"#) != nil { return true }
        var depth = 0
        var escaped = false
        for ch in payload {
            if escaped { escaped = false; continue }
            if ch == "\\" { escaped = true }
            else if ch == "[" { depth += 1 }
            else if ch == "]" {
                if depth == 0 { return false }
                depth -= 1
            }
        }
        return true
    }
    private func mathClosing(_ source: String, delimiter: String) -> Range<String.Index>? {
        if delimiter == "$$" { return source.range(of: delimiter) }
        var cursor = source.startIndex
        while cursor < source.endIndex, let found = source.range(of: delimiter, range: cursor..<source.endIndex) {
            var before = found.lowerBound; var escapes = 0
            while before > source.startIndex {
                let previous = source.index(before: before)
                guard source[previous] == "\\" else { break }
                escapes += 1; before = previous
            }
            if escapes % 2 == 0 { return found }
            cursor = found.upperBound
        }
        return nil
    }

    private func footnoteLabel(_ line: String) -> String? {
        match(#"^ {0,3}\[\^([^]]+)\]:"#, line)?[1]
    }

    private func quotePrefix(_ line: String) -> String? {
        match(#"^( {0,3}>)"#, line)?[1]
    }

    private func projectQuoteLine(_ line: Line) -> Line {
        guard let prefix = quotePrefix(line.text) else {
            return Line(text: line.text, raw: line.raw, start: line.start,
                        sourceEnd: line.end, projected: true, lazyContinuation: true,
                        virtualIndent: line.virtualIndent)
        }
        var body = String(line.text.dropFirst(prefix.count))
        var column = prefix.count
        var offset = (prefix as NSString).length
        var virtualIndent = line.virtualIndent
        if body.first == " " || body.first == "\t" {
            let first = body.removeFirst()
            offset += String(first).utf16.count
            let width = first == "\t" ? 4 - column % 4 : 1
            column += 1
            let remaining = width - 1
            body = String(repeating: " ", count: remaining) + body
            virtualIndent += remaining
        }
        var expanded = ""
        var initialWhitespace = true
        for character in body {
            if character == "\t", initialWhitespace {
                let width = 4 - column % 4
                expanded += String(repeating: " ", count: width)
                virtualIndent += width - 1
                column += width
            } else {
                expanded.append(character)
                if character == " " { column += 1 }
                else { initialWhitespace = false }
            }
        }
        return Line(text: expanded, raw: expanded + (line.raw.hasSuffix("\n") ? "\n" : ""),
                    start: line.start + offset, sourceEnd: line.end, projected: true,
                    virtualIndent: virtualIndent)
    }

    private func quoteParagraphCanContinue(_ body: String) -> Bool {
        var content = body
        while let prefix = quotePrefix(content) {
            content = String(content.dropFirst(prefix.count))
        }
        if let marker = listMarker(content) {
            content = String(content.dropFirst(marker.prefix.count))
            while let prefix = quotePrefix(content) {
                content = String(content.dropFirst(prefix.count))
            }
        }
        guard !content.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        let line = Line(text: content, raw: content, start: 0)
        return !interruptsParagraph(at: 0, lines: [line]) &&
            !content.hasPrefix("    ") && !content.hasPrefix("\t")
    }

    private func interruptsParagraph(at index: Int, lines: [Line]) -> Bool {
        let text = lines[index].text
        return heading(text) != nil || fenceOpen(text) != nil || isThematic(text) ||
            quotePrefix(text) != nil || NativeMarkdownHTMLBlock.end(for: text, interruptingParagraph: true) != nil ||
            (listMarker(text).map {
                text.count > $0.prefix.count && (!$0.ordered || $0.number == 1)
            } ?? false)
    }

    private func isTable(at index: Int, lines: [Line]) -> Bool {
        guard index + 1 < lines.count, lines[index].text.contains("|") else { return false }
        let cells = tableSpans(lines[index + 1].text)
        return !cells.isEmpty && cells.count == tableSpans(lines[index].text).count && cells.allSatisfy {
            (lines[index + 1].text as NSString).substring(with: $0)
                .range(of: #"^:?-+:?$"#, options: .regularExpression) != nil
        }
    }

    private func tableSpans(_ line: String) -> [NSRange] {
        let text = line as NSString
        var spans: [NSRange] = []
        var start = 0
        var slashes = 0
        for index in 0..<text.length {
            let character = text.character(at: index)
            if character == 124 && slashes % 2 == 0 {
                spans.append(NSRange(location: start, length: index - start))
                start = index + 1
            }
            slashes = character == 92 ? slashes + 1 : 0
        }
        spans.append(NSRange(location: start, length: text.length - start))
        func trim(_ span: NSRange) -> NSRange {
            var location = span.location
            var length = span.length
            while length > 0, [UInt16(32), 9].contains(text.character(at: location)) { location += 1; length -= 1 }
            while length > 0, [UInt16(32), 9].contains(text.character(at: location + length - 1)) { length -= 1 }
            return NSRange(location: location, length: length)
        }
        spans = spans.map(trim)
        if spans.count > 1, spans.first?.length == 0 { spans.removeFirst() }
        if spans.count > 1, spans.last?.length == 0 { spans.removeLast() }
        return spans
    }

    private func tableCells(_ line: Line, references: [String: Reference]) -> [NativeMarkdownNode] {
        let text = line.text as NSString
        func normalizeCode(_ node: NativeMarkdownNode) -> NativeMarkdownNode {
            .init(kind: node.kind, source: node.source, sourceRange: node.sourceRange,
                  children: node.children.map(normalizeCode), title: node.title,
                  isTight: node.isTight, listStart: node.listStart,
                  literalText: node.kind == .inlineCode ? NativeMarkdownTextDecoder.codeSpan(node.source.replacingOccurrences(of: "\\|", with: "|")) : node.literalText,
                  tableAlignments: node.tableAlignments)
        }
        return tableSpans(line.text).map { span in
            let content = text.substring(with: span)
            let offset = line.start + span.location
            return .init(kind: .tableCell, source: content,
                         sourceRange: NSRange(location: offset, length: span.length),
                         children: inline(content, offset: offset, references: references).map(normalizeCode))
        }
    }

    private func listMarker(_ line: String, maxIndent: Int = 3)
        -> (indent: Int, prefix: String, ordered: Bool, number: Int,
            style: Character, overflowSpaces: Int)? {
        guard let parts = match(#"^([ \t]*)([-+*]|[0-9]{1,9}[.)])([ \t]+|$)(.*)$"#, line) else { return nil }
        let indent = indentation(parts[1])
        guard indent <= maxIndent else { return nil }
        let marker = parts[2]
        let spacing = parts[3]
        var column = indent + marker.count
        for character in spacing {
            column += character == "\t" ? 4 - column % 4 : 1
        }
        let spacingWidth = column - indent - marker.count
        let overflow = spacingWidth > 4
        let consumed = overflow || parts[4].isEmpty ? min(1, spacing.count) : spacing.count
        return (indent, parts[1] + marker + String(spacing.prefix(consumed)),
                marker.last == "." || marker.last == ")",
                Int(marker.dropLast()) ?? 1, marker.last!, overflow ? spacingWidth - 1 : 0)
    }

    private func list(at start: Int, lines: [Line], source: String,
                      references: [String: Reference]) -> (node: NativeMarkdownNode, next: Int) {
        let first = listMarker(lines[start].text)!
        var siblingLimit = displayColumn(first.prefix)
        var index = start
        var loose = false
        var parsedItems: [(range: NSRange, checked: Bool?, blocks: [NativeMarkdownNode])] = []
        while index < lines.count, let marker = listMarker(lines[index].text),
              !isThematic(lines[index].text),
              marker.indent < siblingLimit, marker.ordered == first.ordered,
              marker.style == first.style {
            let itemStart = index
            let itemLine = lines[index]
            index += 1
            var body = String(itemLine.text.dropFirst(marker.prefix.count))
            if marker.overflowSpaces > 0 {
                body = String(repeating: " ", count: marker.overflowSpaces) +
                    String(body.drop(while: { $0 == " " || $0 == "\t" }))
            }
            let task = enableGFM ? match(#"^\[([ xX])\][ \t]+"#, body) : nil
            let checked: Bool?
            if let task {
                checked = task[1].lowercased() == "x"
                body = String(body.dropFirst(task[0].count))
            } else { checked = nil }
            let prefixWidth = (marker.prefix as NSString).length +
                (task.map { ($0[0] as NSString).length } ?? 0)
            let contentIndent = max(displayColumn(marker.prefix), marker.indent +
                (marker.ordered ? String(marker.number).count + 1 : 1) + 1)
            siblingLimit = contentIndent
            var contents = [Line(text: body, raw: body + (itemLine.raw.hasSuffix("\n") ? "\n" : ""),
                                 start: itemLine.start + prefixWidth, sourceEnd: itemLine.end,
                                 projected: true)]
            var lastContent = itemStart
            var activeFence = fenceOpen(body)
            while index < lines.count {
                let current = lines[index]
                if let next = listMarker(current.text), next.indent < contentIndent { break }
                if current.isBlank {
                    var following = index + 1
                    while following < lines.count, lines[following].isBlank { following += 1 }
                    if following < lines.count, let next = listMarker(lines[following].text),
                       next.indent < contentIndent {
                        loose = true
                        index = following
                        break
                    }
                    if body.trimmingCharacters(in: .whitespaces).isEmpty,
                       lastContent == itemStart { break }
                    if following >= lines.count ||
                        indentation(lines[following].text) < contentIndent { break }
                    let previousNested = listMarker(lines[lastContent].text, maxIndent: Int.max).map {
                        $0.indent >= contentIndent && indentation(lines[following].text) > $0.indent
                    } ?? false
                    if activeFence == nil && !previousNested { loose = true }
                    while index < following {
                        contents.append(project(lines[index], removing: 0))
                        index += 1
                    }
                    continue
                }
                let indent = indentation(current.text)
                if indent >= contentIndent {
                    let projected = project(current, removing: min(contentIndent, indent))
                    contents.append(projected)
                    if let fence = activeFence {
                        if fenceClose(projected.text, marker: fence.marker, count: fence.count) {
                            activeFence = nil
                        }
                    } else { activeFence = fenceOpen(projected.text) }
                    lastContent = index
                    index += 1
                    continue
                }
                if !interruptsParagraph(at: index, lines: lines), !body.isEmpty {
                    var continuation = project(current, removing: min(indent, contentIndent))
                    continuation.lazyContinuation = true
                    contents.append(continuation)
                    lastContent = index
                    index += 1
                    continue
                }
                break
            }
            let end = lines[lastContent].end
            let itemRange = NSRange(location: itemLine.start, length: end - itemLine.start)
            parsedItems.append((itemRange, checked,
                                scan(contents, source: source, references: references)))
            if index >= lines.count || isThematic(lines[index].text) ||
                (listMarker(lines[index].text)?.indent ?? Int.max) >= siblingLimit ||
                listMarker(lines[index].text)?.style != first.style { break }
        }
        let items = parsedItems.map { item -> NativeMarkdownNode in
            let children = loose ? item.blocks : item.blocks.flatMap { block -> [NativeMarkdownNode] in
                block.kind == .paragraph ? block.children : [block]
            }
            return .init(kind: .listItem(checked: item.checked),
                         source: (source as NSString).substring(with: item.range),
                         sourceRange: item.range, children: children)
        }
        let end = items.last.map { NSMaxRange($0.sourceRange) } ?? lines[start].end
        let range = NSRange(location: lines[start].start, length: end - lines[start].start)
        return (.init(kind: .list(ordered: first.ordered), source: (source as NSString).substring(with: range),
                      sourceRange: range, children: items, isTight: !loose,
                      listStart: first.ordered ? first.number : nil), index)
    }

    private func project(_ line: Line, removing width: Int) -> Line {
        var removed = 0
        var cursor = line.text.startIndex
        while cursor < line.text.endIndex, removed < width {
            let character = line.text[cursor]
            guard character == " " || character == "\t" else { break }
            removed += character == "\t" ? 4 - removed % 4 : 1
            cursor = line.text.index(after: cursor)
        }
        let prefix = String(line.text[..<cursor])
        let leading = line.text.prefix { $0 == " " || $0 == "\t" }
        let residual = max(0, indentation(line.text) - width)
        let content = String(line.text.dropFirst(leading.count))
        let body = String(repeating: " ", count: residual) + content
        let physicalRemaining = leading.count - prefix.count
        let offsetAdjustment = residual - physicalRemaining
        let projectedStart = max(line.start,
                                 line.start + (prefix as NSString).length - offsetAdjustment)
        return Line(text: body, raw: body + (line.raw.hasSuffix("\n") ? "\n" : ""),
                    start: projectedStart,
                    sourceEnd: line.end, projected: true)
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
                        references: [String: Reference], trimTrailingWhitespace: Bool = false,
                        trimLeadingWhitespace: Bool = false) -> [NativeMarkdownNode] {
        let characters = Array(source)
        var utf16Positions = [Int](repeating: 0, count: characters.count + 1)
        for position in characters.indices {
            utf16Positions[position + 1] = utf16Positions[position] + String(characters[position]).utf16.count
        }
        var result: [NativeMarkdownNode] = []
        var index = 0
        var plainStart = 0
        if trimLeadingWhitespace {
            while index < characters.count, characters[index] == " " || characters[index] == "\t" { index += 1 }
            plainStart = index
        }

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
                                                           length: (content as NSString).length),
                                      literalText: content)]
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
        func angleEnd(after start: Int) -> Int? {
            (start..<characters.count).first { characters[$0] == ">" }
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
                if characters[cursor] == "<" {
                    if let length = NativeMarkdownInlineHTML.length(in: characters, at: cursor) {
                        cursor += length
                        continue
                    }
                    if let end = angleEnd(after: cursor + 1),
                       autolinkDestination(String(characters[(cursor + 1)..<end])) != nil {
                        cursor = end + 1
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
                    if character == " " || character == "\t" || isLineEnding(character) || character == "<" || character == ">" ||
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
            if enableNativeExtensions, characters[index] == "\\", index + 1 < characters.count,
               characters[index + 1] == "(" {
                var end = index + 2
                while end + 1 < characters.count {
                    if characters[end] == "\\", characters[end + 1] == ")" { break }
                    end += characters[end] == "\\" ? 2 : 1
                }
                if end > index + 2, end + 1 < characters.count {
                    flushPlain(until: index)
                    append(.inlineMath, start: index, end: end + 2)
                    index = end + 2; plainStart = index; continue
                }
            }
            if characters[index] == "\\", index + 1 < characters.count {
                if isLineEnding(characters[index + 1]) {
                    flushPlain(until: index)
                    var end = index + 2
                    while end < characters.count, characters[end] == " " || characters[end] == "\t" { end += 1 }
                    append(.hardBreak, start: index, end: end)
                    index = end; plainStart = index; continue
                }
                index += 2; continue
            }
            if isLineEnding(characters[index]) {
                let hard = index >= 2 && characters[index - 1] == " " && characters[index - 2] == " "
                var start = index
                while start > plainStart, characters[start - 1] == " " || characters[start - 1] == "\t" {
                    start -= 1
                }
                var end = index + 1
                while end < characters.count, characters[end] == " " || characters[end] == "\t" { end += 1 }
                flushPlain(until: start)
                append(hard ? .hardBreak : .softBreak, start: start, end: end)
                index = end; plainStart = index; continue
            }
            if characters[index] == "<", let end = angleEnd(after: index + 1) {
                let content = String(characters[(index + 1)..<end])
                if let destination = autolinkDestination(content) {
                    flushPlain(until: index)
                    append(.link(destination), start: index, end: end + 1,
                           contentStart: index + 1, contentEnd: end, parseContent: false)
                    index = end + 1; plainStart = index; continue
                }
                if let length = NativeMarkdownInlineHTML.length(in: characters, at: index) {
                    flushPlain(until: index)
                    append(.inlineHTML, start: index, end: index + length)
                    index += length; plainStart = index; continue
                }
            }
            if enableGFM, (index == 0 || characters[index - 1].isWhitespace ||
                "*_~(".contains(characters[index - 1])),
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
                index += run; continue
            }
            if enableNativeExtensions, characters[index] == "$", index + 1 < characters.count,
               characters[index + 1] != "$", let end = closing(["$"], after: index + 1),
               end > index + 1, characters[end - 1] != " " {
                flushPlain(until: index)
                append(.inlineMath, start: index, end: end + 1)
                index = end + 1; plainStart = index; continue
            }
            if enableNativeExtensions, characters[index] == "[", index + 3 < characters.count,
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
            if enableGFM, characters[index] == "~" {
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
        var end = characters.count
        if trimTrailingWhitespace {
            while end > plainStart, characters[end - 1] == " " || characters[end - 1] == "\t" { end -= 1 }
        }
        flushPlain(until: end)
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
        let pattern = #"^(?:(?:https?|ftp)://|www\.)[^\s<>]+|^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9._-]+\.[A-Za-z0-9._-]+"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: candidate,
                                               range: NSRange(location: 0, length: (candidate as NSString).length)),
              match.range.location == 0 else { return nil }
        var spelling = (candidate as NSString).substring(with: match.range)
        if let entity = spelling.range(of: #"&[A-Za-z0-9]+;$"#, options: .regularExpression) {
            spelling = String(spelling[..<entity.lowerBound])
        }
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
        else if spelling.contains("@"), !spelling.contains("://") {
            guard let last = spelling.last, last.isASCII && (last.isLetter || last.isNumber),
                  let host = spelling.split(separator: "@").last,
                  !host.contains("_") else { return nil }
            destination = "mailto:" + spelling
        }
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

    private func referenceDefinitions(in nodes: [NativeMarkdownNode]) -> [String: Reference] {
        var result: [String: Reference] = [:]
        func collect(_ node: NativeMarkdownNode) {
            if case let .referenceDefinition(label, destination) = node.kind {
                let key = normalizeReference(label)
                if result[key] == nil { result[key] = Reference(destination: destination, title: node.title) }
            }
            node.children.forEach(collect)
        }
        nodes.forEach(collect)
        return result
    }

    private func referenceDefinition(at start: Int, in lines: [Line])
        -> (definition: (label: String, destination: String, title: String?), next: Int)? {
        guard lines.indices.contains(start),
              lines[start].text.range(of: #"^ {0,3}\["#, options: .regularExpression) != nil else { return nil }
        var spelling = lines[start].text
        var next = start + 1
        while next < lines.count, !lines[next].isBlank {
            spelling += "\n" + lines[next].text
            next += 1
        }
        guard let definition = NativeMarkdownReferenceParser.parse(spelling) else { return nil }
        return ((definition.label, definition.destination, definition.title), start + definition.lineCount)
    }
}
