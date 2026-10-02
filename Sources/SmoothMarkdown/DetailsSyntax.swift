import Foundation

/// The source package recognizes these two details openers as Markdown blocks,
/// independently of its optional generic HTML parser.
enum DetailsSyntax {
    struct Block: Equatable {
        let summary: String
        let content: String
        let isOpen: Bool
    }

    enum Section: Equatable {
        case markdown(String)
        case details(Block)
    }

    static func sections(_ markdown: String, enableInlineHTML: Bool = false) -> [Section] {
        let lines = markdown.components(separatedBy: "\n")
        var sections: [Section] = []
        var ordinary: [String] = []
        var fence: Character?
        var fenceLength = 0
        var index = 0
        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces).lowercased()
            if let marker = fence {
                ordinary.append(line)
                if let run = fenceRun(trimmed), run.0 == marker, run.1 >= fenceLength,
                   trimmed.dropFirst(run.1).trimmingCharacters(in: .whitespaces).isEmpty {
                    fence = nil
                }
                index += 1
                continue
            }
            if let run = fenceRun(trimmed) {
                fence = run.0
                fenceLength = run.1
                ordinary.append(line)
                index += 1
                continue
            }
            if enableInlineHTML, let parsed = inlineBlock(line) {
                if !ordinary.isEmpty {
                    sections.append(.markdown(ordinary.joined(separator: "\n")))
                    ordinary.removeAll()
                }
                sections.append(.details(parsed.block))
                if !parsed.trailing.isEmpty { ordinary.append(parsed.trailing) }
                index += 1
                continue
            }
            if trimmed == "<details>" || trimmed == "<details open>" {
                if !ordinary.isEmpty {
                    sections.append(.markdown(ordinary.joined(separator: "\n")))
                    ordinary.removeAll()
                }
                let parsed = block(lines: lines, startingAt: index, isOpen: trimmed == "<details open>")
                sections.append(.details(parsed.block))
                index = parsed.nextIndex
                continue
            }
            ordinary.append(line)
            index += 1
        }
        if !ordinary.isEmpty { sections.append(.markdown(ordinary.joined(separator: "\n"))) }
        return sections
    }

    /// Claims complete disclosure tokens in an existing inline AST. Code nodes
    /// are never HTML closers, so surrounding list/paragraph structure stays intact.
    static func inlineBlock(in children: [Markup], startingAt start: Int) -> (block: Block, source: String, endIndex: Int)? {
        guard let html = children[start] as? InlineHTML,
              let opener = SafeHTML.lexTag(html.rawHTML), opener.name == "details",
              !opener.isClosing, !opener.isSelfClosing else { return nil }
        var depth = 1
        var htmlCode = false
        for index in children.indices.dropFirst(start + 1) {
            guard let html = children[index] as? InlineHTML,
                  let tag = SafeHTML.lexTag(html.rawHTML) else { continue }
            if tag.name == "code" { htmlCode = !tag.isClosing; continue }
            guard !htmlCode, tag.name == "details" else { continue }
            if tag.isClosing { depth -= 1 } else if !tag.isSelfClosing { depth += 1 }
            if depth == 0 {
                let source = children[start...index].map { $0.format() }.joined()
                guard let parsed = inlineBlock(source), parsed.trailing.isEmpty else { return nil }
                return (parsed.block, source, index)
            }
        }
        return nil
    }

    /// Same-line HTML disclosure uses token offsets into the original line. The
    /// Markdown body is never rewritten; escaped and code-literal tags stay literal.
    private static func inlineBlock(_ line: String) -> (block: Block, trailing: String)? {
        let source = line as NSString
        var start = 0
        var indentation = 0
        while start < source.length, source.character(at: start) == 32 || source.character(at: start) == 9 {
            indentation += source.character(at: start) == 9 ? 4 - indentation % 4 : 1
            start += 1
        }
        guard indentation < 4 else { return nil }
        guard let opener = SafeHTML.lexTag(line, at: start), opener.name == "details",
              !opener.isClosing, !opener.isSelfClosing,
              opener.attributes.keys.allSatisfy({ $0 == "open" }) else { return nil }
        var depth = 1
        var cursor = opener.end
        var summaryStart: Int?
        var summaryEnd: Int?
        var contentStart = opener.end
        var codeRun = 0
        var htmlCode = false
        while cursor < source.length {
            let character = source.character(at: cursor)
            if character == 92 { cursor += min(2, source.length - cursor); continue }
            if character == 96, !htmlCode {
                var end = cursor + 1
                while end < source.length, source.character(at: end) == 96 { end += 1 }
                let run = end - cursor
                if codeRun == 0 {
                    // Unmatched backticks are ordinary Markdown text. A longer
                    // run cannot supply a same-length closing substring.
                    if hasClosingBacktick(in: source, after: end, length: run) { codeRun = run }
                } else if codeRun == run { codeRun = 0 }
                cursor = end
                continue
            }
            if codeRun == 0, character == 60, let tag = SafeHTML.lexTag(line, at: cursor) {
                if tag.name == "code" {
                    htmlCode = !tag.isClosing
                } else if !htmlCode, tag.name == "details" {
                    if tag.isClosing { depth -= 1 } else if !tag.isSelfClosing { depth += 1 }
                    if depth == 0 {
                        let summary = summaryStart.flatMap { first in summaryEnd.map { source.substring(with: NSRange(location: first, length: $0 - first)) } } ?? ""
                        let body = source.substring(with: NSRange(location: contentStart, length: cursor - contentStart))
                        return (.init(summary: summary, content: body, isOpen: opener.attributes["open"] != nil), source.substring(from: tag.end))
                    }
                } else if !htmlCode, depth == 1, tag.name == "summary" {
                    if !tag.isClosing, summaryStart == nil {
                        summaryStart = tag.end
                    } else if tag.isClosing, summaryStart != nil, summaryEnd == nil {
                        summaryEnd = cursor
                        contentStart = tag.end
                    }
                }
                cursor = tag.end
            } else {
                cursor += 1
            }
        }
        return nil
    }

    private static func hasClosingBacktick(in source: NSString, after start: Int, length: Int) -> Bool {
        var cursor = start
        while cursor < source.length {
            if source.character(at: cursor) != 96 { cursor += 1; continue }
            let first = cursor
            while cursor < source.length, source.character(at: cursor) == 96 { cursor += 1 }
            if cursor - first == length { return true }
        }
        return false
    }

    private static func block(lines: [String], startingAt start: Int, isOpen: Bool) -> (block: Block, nextIndex: Int) {
        var index = start + 1
        var summary = ""
        var content: [String] = []
        var foundSummary = false
        var inSummary = false
        var depth = 1
        var fence: Character?
        var fenceLength = 0
        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let lower = trimmed.lowercased()
            if let marker = fence {
                if foundSummary { content.append(line) }
                if let run = fenceRun(lower), run.0 == marker, run.1 >= fenceLength,
                   lower.dropFirst(run.1).trimmingCharacters(in: .whitespaces).isEmpty {
                    fence = nil
                }
                index += 1
                continue
            }
            if let run = fenceRun(lower) {
                fence = run.0
                fenceLength = run.1
                if foundSummary { content.append(line) }
                index += 1
                continue
            }
            if lower == "<details>" || lower == "<details open>" {
                depth += 1
                if foundSummary { content.append(line) }
                index += 1
                continue
            }
            if lower == "</details>" {
                depth -= 1
                index += 1
                if depth == 0 { break }
                if foundSummary { content.append(line) }
                continue
            }
            if depth == 1, lower.hasPrefix("<summary>") {
                foundSummary = true
                inSummary = true
                let afterOpen = String(trimmed.dropFirst("<summary>".count))
                if let close = afterOpen.range(of: "</summary>", options: .caseInsensitive) {
                    summary = String(afterOpen[..<close.lowerBound]).trimmingCharacters(in: .whitespaces)
                    inSummary = false
                } else if !afterOpen.isEmpty {
                    summary = afterOpen
                }
                index += 1
                continue
            }
            if inSummary, let close = line.range(of: "</summary>", options: .caseInsensitive) {
                let lastLine = String(line[..<close.lowerBound]).trimmingCharacters(in: .whitespaces)
                if !lastLine.isEmpty { summary = lastLine }
                inSummary = false
                index += 1
                continue
            }
            if inSummary {
                summary = "\(summary) \(trimmed)"
                index += 1
                continue
            }
            if foundSummary { content.append(line) }
            index += 1
        }
        return (Block(summary: summary, content: content.joined(separator: "\n"), isOpen: isOpen), index)
    }

    private static func fenceRun(_ line: String) -> (Character, Int)? {
        guard let first = line.first, first == "`" || first == "~" else { return nil }
        let count = line.prefix(while: { $0 == first }).count
        return count >= 3 ? (first, count) : nil
    }
}
