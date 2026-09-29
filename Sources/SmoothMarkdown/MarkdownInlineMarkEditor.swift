import Foundation
import Markdown

/// Inline source edits supported by paragraph and ATX heading rows in Blocks mode.
public enum MarkdownInlineMark: Equatable {
    case bold
    case italic
    case strikethrough
    case code
    case link(destination: String)
}

struct MarkdownInlineMarkEdit: Equatable {
    let markdown: String
    /// UTF-16 selection within the edited block body.
    let selection: NSRange
}

enum MarkdownInlineMarkEditor {
    struct VisibleBoundary {
        let sourceOffset: Int
        let closeTokens: String
        let openTokens: String
    }

    struct VisibleStyle: Equatable {
        let bold: Int
        let italic: Int
        let strike: Int
        let code: Int
        let links: [URL]
    }

    private enum MappedKind: Equatable {
        case bold, italic, strikethrough, code, link(URL)
    }

    private struct MappedMark {
        let kind: MappedKind
        let visibleStart: Int
        let visibleEnd: Int
        let sourceStart: Int
        let sourceEnd: Int
        let opening: String
        let closing: String
    }

    private struct SourceBoundary {
        let offset: Int
        let closeTokens: String
        let openTokens: String
    }

    private struct InlineMap {
        let units: [UInt16]
        let starts: [Int]
        let ends: [Int]
        let marks: [MappedMark]
        let sourceLength: Int

        func boundary(at visibleOffset: Int) -> SourceBoundary? {
            guard visibleOffset >= 0, visibleOffset <= units.count else { return nil }
            let fallback = visibleOffset == 0 ? 0 : visibleOffset == units.count ? sourceLength : ends[visibleOffset - 1]
            let ending = marks.filter { $0.visibleEnd == visibleOffset && $0.visibleStart < visibleOffset }
            let starting = marks.filter { $0.visibleStart == visibleOffset && $0.visibleEnd > visibleOffset }
            let offset = ending.map(\.sourceEnd).max() ?? starting.map(\.sourceStart).min() ?? fallback
            let active = marks.filter { $0.visibleStart < visibleOffset && visibleOffset < $0.visibleEnd }
                .sorted { $0.sourceStart == $1.sourceStart ? $0.sourceEnd > $1.sourceEnd : $0.sourceStart < $1.sourceStart }
            return SourceBoundary(offset: offset,
                                  closeTokens: active.reversed().map(\.closing).joined(),
                                  openTokens: active.map(\.opening).joined())
        }

        func coverage() -> [(bold: Int, italic: Int, strike: Int, code: Int, links: [URL])] {
            var result = Array(repeating: (bold: 0, italic: 0, strike: 0, code: 0, links: [URL]()), count: units.count)
            for mark in marks {
                for index in mark.visibleStart..<mark.visibleEnd {
                    switch mark.kind {
                    case .bold: result[index].bold += 1
                    case .italic: result[index].italic += 1
                    case .strikethrough: result[index].strike += 1
                    case .code: result[index].code += 1
                    case let .link(url): result[index].links.append(url)
                    }
                }
            }
            return result
        }
    }

    static func visibleUTF16Length(of markdown: String) -> Int? {
        inlineMap(markdown, allowCode: true)?.units.count
    }

    static func visibleText(of markdown: String) -> String? {
        guard let mapped = inlineMap(markdown, allowCode: true) else { return nil }
        return String(decoding: mapped.units, as: UTF16.self)
    }

    static func visibleStyles(of markdown: String) -> [VisibleStyle]? {
        inlineMap(markdown, allowCode: true)?.coverage().map {
            .init(bold: $0.bold, italic: $0.italic, strike: $0.strike,
                  code: $0.code, links: $0.links)
        }
    }

    static func visibleBoundary(in markdown: String, at offset: Int) -> VisibleBoundary? {
        guard let map = inlineMap(markdown, allowCode: true),
              scalarBoundary(offset, in: map.units),
              let boundary = map.boundary(at: offset) else { return nil }
        return .init(sourceOffset: boundary.offset, closeTokens: boundary.closeTokens,
                     openTokens: boundary.openTokens)
    }

    /// Extracts a self-contained Markdown fragment from rendered coordinates.
    /// An inline mark cut by either endpoint is balanced in the fragment.
    static func copyVisibleRange(in markdown: String, range: NSRange) -> String? {
        guard let map = inlineMap(markdown, allowCode: true),
              range.location != NSNotFound, range.location >= 0, range.length >= 0,
              NSMaxRange(range) <= map.units.count,
              scalarBoundary(range.location, in: map.units),
              scalarBoundary(NSMaxRange(range), in: map.units),
              let start = map.boundary(at: range.location),
              let end = map.boundary(at: NSMaxRange(range)),
              start.offset <= end.offset else { return nil }
        if range.length == 0 { return "" }
        let source = markdown as NSString
        let selected = String(decoding: map.units[range.location..<NSMaxRange(range)], as: UTF16.self)
        let fragment = start.openTokens + source.substring(with: NSRange(location: start.offset,
                                                                          length: end.offset - start.offset))
            + end.closeTokens
        guard visibleText(of: fragment) == selected else { return nil }
        return fragment
    }

    /// A block paste may split raw Markdown only outside an existing inline
    /// mark. Splitting inside emphasis, code, or a link would leave unmatched
    /// delimiters in the before/after sibling blocks.
    static func canSplitForBlockPaste(_ markdown: String, range: NSRange) -> Bool {
        let length = (markdown as NSString).length
        guard range.location != NSNotFound, range.location >= 0, range.length >= 0,
              NSMaxRange(range) <= length else { return false }
        if isSimpleRangeSource(markdown) { return true }
        guard let mapped = inlineMap(markdown, allowCode: true) else { return false }
        return mapped.marks.allSatisfy { mark in
            !(mark.sourceStart < range.location && range.location < mark.sourceEnd) &&
                !(mark.sourceStart < NSMaxRange(range) && NSMaxRange(range) < mark.sourceEnd)
        }
    }

    /// Wraps visible UTF-16 text only when reparsing preserves every original
    /// text unit and existing mark, including code spans outside the selection.
    static func applyVerifiedVisibleRange(_ mark: MarkdownInlineMark, to markdown: String,
                                          selection: NSRange) -> String? {
        guard let before = inlineMap(markdown, allowCode: true), selection.location != NSNotFound,
              selection.location >= 0, selection.length > 0,
              NSMaxRange(selection) <= before.units.count,
              scalarBoundary(selection.location, in: before.units),
              scalarBoundary(NSMaxRange(selection), in: before.units),
              before.coverage()[selection.location..<NSMaxRange(selection)].allSatisfy({ $0.code == 0 }),
              let start = before.boundary(at: selection.location),
              let end = before.boundary(at: NSMaxRange(selection)), start.offset <= end.offset else { return nil }

        let addition: MappedKind
        let delimiters: [(String, String)]
        switch mark {
        case .bold:
            addition = .bold
            delimiters = [("**", "**"), ("__", "__")]
        case .italic:
            addition = .italic
            delimiters = [("*", "*"), ("_", "_")]
        case .strikethrough:
            addition = .strikethrough
            delimiters = [("~~", "~~")]
        case .code:
            let selected = String(decoding: before.units[selection.location..<NSMaxRange(selection)], as: UTF16.self)
            let delimiter = String(repeating: "`", count: longestBacktickRun(in: selected) + 1)
            let padding = selected.contains("`") ? " " : ""
            addition = .code
            delimiters = [(delimiter + padding, padding + delimiter)]
        case let .link(destination):
            guard let url = safeDestination(destination),
                  !before.marks.contains(where: {
                      if case .link = $0.kind {
                          return $0.visibleStart < NSMaxRange(selection) && selection.location < $0.visibleEnd
                      }
                      return false
                  }) else { return nil }
            addition = .link(url)
            let escaped = url.absoluteString.replacingOccurrences(of: "(", with: "%28")
                .replacingOccurrences(of: ")", with: "%29")
            delimiters = [("[", "](" + escaped + ")")]
        }

        let oldCoverage = before.coverage()
        let source = markdown as NSString
        for split in [false, true] {
            for (opening, closing) in delimiters {
                let candidate = source.substring(to: start.offset)
                    + (split ? start.closeTokens : "") + opening + (split ? start.openTokens : "")
                    + source.substring(with: NSRange(location: start.offset, length: end.offset - start.offset))
                    + (split ? end.closeTokens : "") + closing + (split ? end.openTokens : "")
                    + source.substring(from: end.offset)
                guard let after = inlineMap(candidate, allowCode: true),
                      after.units == before.units else { continue }
                let newCoverage = after.coverage()
                let valid = oldCoverage.indices.allSatisfy { index in
                    let old = oldCoverage[index]
                    let new = newCoverage[index]
                    let selected = selection.location <= index && index < NSMaxRange(selection)
                    switch addition {
                    case .bold:
                        return new.bold == old.bold + (selected ? 1 : 0) &&
                            new.italic == old.italic && new.strike == old.strike &&
                            new.code == old.code && new.links == old.links
                    case .italic:
                        return new.bold == old.bold &&
                            new.italic == old.italic + (selected ? 1 : 0) &&
                            new.strike == old.strike && new.code == old.code && new.links == old.links
                    case .strikethrough:
                        return new.bold == old.bold && new.italic == old.italic &&
                            new.strike == old.strike + (selected ? 1 : 0) &&
                            new.code == old.code && new.links == old.links
                    case .code:
                        return new.bold == old.bold && new.italic == old.italic &&
                            new.strike == old.strike && new.code == old.code + (selected ? 1 : 0) &&
                            new.links == old.links
                    case let .link(url):
                        return new.bold == old.bold && new.italic == old.italic &&
                            new.strike == old.strike && new.code == old.code &&
                            new.links == (selected ? old.links + [url] : old.links)
                    }
                }
                if valid { return candidate }
            }
        }
        return nil
    }

    private static func safeDestination(_ value: String) -> URL? {
        guard !value.isEmpty,
              !value.contains(where: { $0.isWhitespace || $0.isNewline || "<>[]\\".contains($0) }),
              let url = URL(string: value), MarkdownSyntax.isSafeLink(url) else { return nil }
        return url
    }

    private static func scalarBoundary(_ offset: Int, in units: [UInt16]) -> Bool {
        guard offset > 0, offset < units.count else { return true }
        return !(0xD800...0xDBFF).contains(units[offset - 1]) || !(0xDC00...0xDFFF).contains(units[offset])
    }

    private static func inlineMap(_ source: String, allowCode: Bool = false) -> InlineMap? {
        let document = MarkdownSyntax.parse(source, useCache: false)
        let blocks = Array(document.children)
        guard blocks.count == 1, let paragraph = blocks.first as? Paragraph,
              supportedInlineTree(paragraph, allowCode: allowCode),
              inlineSignature(source, allowCode: allowCode) != nil else { return nil }
        let nsSource = source as NSString
        let utf8 = Array(source.utf8)
        func offset(_ location: SourceLocation) -> Int? {
            guard location.line == 1, location.column >= 1, location.column - 1 <= utf8.count,
                  let prefix = String(bytes: utf8.prefix(location.column - 1), encoding: .utf8) else { return nil }
            return prefix.utf16.count
        }
        func sourceRange(_ node: Markup) -> NSRange? {
            guard let range = node.range, let start = offset(range.lowerBound),
                  let end = offset(range.upperBound), end >= start else { return nil }
            return NSRange(location: start, length: end - start)
        }
        var units: [UInt16] = []
        var starts: [Int] = []
        var ends: [Int] = []
        var marks: [MappedMark] = []
        func visit(_ node: Markup) -> Bool {
            for child in node.children {
                if let text = child as? Markdown.Text {
                    guard let range = sourceRange(text),
                          range.length == (text.string as NSString).length,
                          nsSource.substring(with: range) == text.string else { return false }
                    for (index, unit) in text.string.utf16.enumerated() {
                        units.append(unit)
                        starts.append(range.location + index)
                        ends.append(range.location + index + 1)
                    }
                    continue
                }
                let kind: MappedKind
                if child is Strong { kind = .bold }
                else if child is Emphasis { kind = .italic }
                else if child is Strikethrough { kind = .strikethrough }
                else if allowCode, child is InlineCode { kind = .code }
                else if let link = child as? Markdown.Link,
                        let destination = link.destination,
                        let url = safeDestination(destination), link.title == nil { kind = .link(url) }
                else { return false }
                guard let range = sourceRange(child), range.length > 1 else { return false }
                let raw = nsSource.substring(with: range)
                let opening: String
                let closing: String
                switch kind {
                case .bold:
                    guard raw.hasPrefix("**") && raw.hasSuffix("**") ||
                          raw.hasPrefix("__") && raw.hasSuffix("__") else { return false }
                    opening = String(raw.prefix(2)); closing = String(raw.suffix(2))
                case .italic:
                    guard raw.hasPrefix("*") && raw.hasSuffix("*") ||
                          raw.hasPrefix("_") && raw.hasSuffix("_") else { return false }
                    opening = String(raw.prefix(1)); closing = String(raw.suffix(1))
                case .strikethrough:
                    guard raw.hasPrefix("~~"), raw.hasSuffix("~~") else { return false }
                    opening = "~~"; closing = "~~"
                case .code:
                    guard let code = child as? InlineCode, !code.code.isEmpty else { return false }
                    let count = raw.prefix(while: { $0 == "`" }).count
                    let delimiter = String(repeating: "`", count: count)
                    guard count > 0, raw.hasSuffix(delimiter) else { return false }
                    let inner = String(raw.dropFirst(count).dropLast(count))
                    if inner == code.code {
                        opening = delimiter; closing = delimiter
                    } else if inner.hasPrefix(" "), inner.hasSuffix(" "),
                              String(inner.dropFirst().dropLast()) == code.code {
                        opening = delimiter + " "; closing = " " + delimiter
                    } else { return false }
                case .link:
                    guard raw.hasPrefix("["), raw.hasSuffix(")"),
                          let suffix = raw.range(of: "](", options: .backwards) else { return false }
                    opening = "["; closing = String(raw[suffix.lowerBound...])
                }
                let visibleStart = units.count
                if let code = child as? InlineCode {
                    // Map the exact code payload so later selections outside this span
                    // still resolve to source offsets after rendering the new code mark.
                    let payloadStart = range.location + (opening as NSString).length
                    for (index, unit) in code.code.utf16.enumerated() {
                        units.append(unit)
                        starts.append(payloadStart + index)
                        ends.append(payloadStart + index + 1)
                    }
                } else {
                    guard visit(child) else { return false }
                }
                guard units.count > visibleStart else { return false }
                marks.append(MappedMark(kind: kind, visibleStart: visibleStart, visibleEnd: units.count,
                                        sourceStart: range.location, sourceEnd: NSMaxRange(range),
                                        opening: opening, closing: closing))
            }
            return true
        }
        guard visit(paragraph), !units.isEmpty,
              inlineSignature(source, allowCode: allowCode)?.map(\.unit) == units else { return nil }
        return InlineMap(units: units, starts: starts, ends: ends, marks: marks, sourceLength: nsSource.length)
    }

    /// Simple source can use raw offsets. Existing inline syntax needs the
    /// full-body semantic validation in applyVerifiedRange instead.
    /// An escaped table pipe is the one source escape handled by this editor.
    static func isSimpleRangeSource(_ source: String) -> Bool {
        let characters = Array(source)
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character == "\\" {
                guard index + 1 < characters.count, characters[index + 1] == "|" else { return false }
                index += 2
                continue
            }
            if "\r\n*~_`[]<>".contains(character) { return false }
            index += 1
        }
        return true
    }

    /// A full-body range can include existing emphasis or links when wrapping
    /// its source produces exactly the intended visible style change. Partial
    /// ranges still need a source-to-visible offset map, so remain conservative.
    static func applyVerifiedRange(_ mark: MarkdownInlineMark, to markdown: String,
                                   selection: NSRange) -> MarkdownInlineMarkEdit? {
        if isSimpleRangeSource(markdown) {
            return apply(mark, to: markdown, selection: selection)
        }
        guard selection == NSRange(location: 0, length: (markdown as NSString).length) else { return nil }
        switch mark {
        case .bold, .italic: break
        default: return nil
        }
        guard let before = inlineSignature(markdown),
              let edit = apply(mark, to: markdown, selection: selection),
              let after = inlineSignature(edit.markdown), before.count == after.count else { return nil }
        var gainedMark = false
        for (old, new) in zip(before, after) {
            guard old.unit == new.unit, old.strike == new.strike,
                  old.link == new.link else { return nil }
            switch mark {
            case .bold:
                guard old.italic == new.italic, new.bold else { return nil }
                gainedMark = gainedMark || !old.bold
            case .italic:
                guard old.bold == new.bold, new.italic else { return nil }
                gainedMark = gainedMark || !old.italic
            default: return nil
            }
        }
        return gainedMark ? edit : nil
    }

    private struct InlineUnit {
        let unit: UInt16
        let bold: Bool
        let italic: Bool
        let strike: Bool
        let link: URL?
    }

    private static func inlineSignature(_ source: String, allowCode: Bool = false) -> [InlineUnit]? {
        let document = MarkdownSyntax.parse(source, useCache: false)
        let blocks = Array(document.children)
        guard blocks.count == 1, let paragraph = blocks.first as? Paragraph,
              supportedInlineTree(paragraph, allowCode: allowCode) else { return nil }
        var signature: [InlineUnit] = []
        for run in InlineContent.runs(in: paragraph, enableHTML: false) {
            guard case let .text(value, style, tags, code) = run, tags.isEmpty,
                  allowCode || !code else { return nil }
            signature += value.utf16.map {
                InlineUnit(unit: $0, bold: style.bold, italic: style.italic,
                           strike: style.strike, link: style.link)
            }
        }
        return signature.isEmpty ? nil : signature
    }

    private static func supportedInlineTree(_ node: Markup, allowCode: Bool = false) -> Bool {
        for child in node.children {
            if child is Markdown.Text || child is Strong || child is Emphasis ||
                child is Strikethrough || (allowCode && child is InlineCode) {
                // Accepted below after recursively checking nested children.
            } else if let link = child as? Markdown.Link {
                guard let destination = link.destination, let url = URL(string: destination),
                      MarkdownSyntax.isSafeLink(url) else { return false }
            } else {
                return false
            }
            guard supportedInlineTree(child, allowCode: allowCode) else { return false }
        }
        return true
    }

    static func apply(_ mark: MarkdownInlineMark, to markdown: String, selection: NSRange) -> MarkdownInlineMarkEdit? {
        let source = markdown as NSString
        guard selection.location != NSNotFound, selection.location >= 0, selection.length > 0,
              NSMaxRange(selection) <= source.length,
              let swiftRange = Range(selection, in: markdown),
              NSRange(swiftRange, in: markdown) == selection,
              isScalarBoundary(selection.location, in: source),
              isScalarBoundary(NSMaxRange(selection), in: source) else { return nil }
        let selected = source.substring(with: selection)

        let prefix: String
        let suffix: String
        switch mark {
        case .bold: prefix = "**"; suffix = "**"
        case .italic: prefix = "*"; suffix = "*"
        case .strikethrough: prefix = "~~"; suffix = "~~"
        case .code:
            let delimiter = String(repeating: "`", count: longestBacktickRun(in: selected) + 1)
            let padding = selected.contains("`") ? " " : ""
            prefix = delimiter + padding
            suffix = padding + delimiter
        case let .link(destination):
            guard !selected.contains("["), !selected.contains("]"),
                  let url = URL(string: destination), MarkdownSyntax.isSafeLink(url),
                  !destination.contains(where: { $0.isWhitespace || $0 == "<" || $0 == ">" }) else { return nil }
            let escaped = url.absoluteString.replacingOccurrences(of: "(", with: "%28")
                .replacingOccurrences(of: ")", with: "%29")
            prefix = "["
            suffix = "](" + escaped + ")"
        }

        // Selecting the entire content of a simple existing mark toggles it off.
        if case .link = mark { /* Link always inserts a destination. */ }
        else if selection.location >= (prefix as NSString).length,
                NSMaxRange(selection) + (suffix as NSString).length <= source.length {
            let before = source.substring(with: NSRange(location: selection.location - (prefix as NSString).length,
                                                        length: (prefix as NSString).length))
            let after = source.substring(with: NSRange(location: NSMaxRange(selection),
                                                       length: (suffix as NSString).length))
            if before == prefix, after == suffix {
                let full = NSRange(location: selection.location - (prefix as NSString).length,
                                   length: (prefix as NSString).length + selection.length + (suffix as NSString).length)
                return .init(markdown: source.replacingCharacters(in: full, with: selected),
                             selection: NSRange(location: full.location, length: selection.length))
            }
        }

        let replacement = prefix + selected + suffix
        return .init(markdown: source.replacingCharacters(in: selection, with: replacement),
                     selection: NSRange(location: selection.location + (prefix as NSString).length,
                                        length: selection.length))
    }

    private static func longestBacktickRun(in source: String) -> Int {
        var longest = 0
        var current = 0
        for character in source {
            if character == "`" { current += 1; longest = max(longest, current) }
            else { current = 0 }
        }
        return longest
    }

    private static func isScalarBoundary(_ offset: Int, in source: NSString) -> Bool {
        guard offset > 0, offset < source.length else { return true }
        let previous = source.character(at: offset - 1)
        let next = source.character(at: offset)
        return !(0xD800...0xDBFF).contains(previous) || !(0xDC00...0xDFFF).contains(next)
    }
}
