import Foundation

/// Imports Markdown without normalizing untouched syntax, whitespace, or line endings.
public struct MarkdownDocumentCodec {
    private let plugins: ParserPluginRegistry?

    /// Custom block syntax is recognized only when its registry is explicitly supplied.
    public init(plugins: ParserPluginRegistry? = nil) {
        self.plugins = plugins?.copy()
    }

    public func parse(_ markdown: String) -> MarkdownDocument {
        guard !markdown.isEmpty else { return .init(blocks: []) }
        let components = markdown.components(separatedBy: "\n")
        let lines = components.enumerated().map { index, component in
            SourceLine(text: component.hasSuffix("\r") ? String(component.dropLast()) : component,
                       raw: component + (index < components.count - 1 ? "\n" : ""))
        }
        let pluginLines = lines.map(\.text)
        var blocks: [MarkdownDocumentBlock] = []
        var pendingTrivia = ""
        var index = 0
        while index < lines.count {
            if lines[index].isBlank {
                pendingTrivia += lines[index].raw
                index += 1
                continue
            }
            let start = index
            let isFrontmatter = start == 0 && lines[start].text.trimmingCharacters(in: .whitespaces) == "---" &&
                lines.dropFirst().contains { $0.text.trimmingCharacters(in: .whitespaces) == "---" }
            let classification: Classification = isFrontmatter ? .raw : classify(lines[index].text)
            let kind: MarkdownSemanticBlock
            if !isFrontmatter, let pluginBlock = pluginBlock(at: index, lines: lines, pluginLines: pluginLines) {
                index += pluginBlock.match.linesConsumed
                kind = .plugin(id: pluginBlock.id, match: pluginBlock.match)
            } else if !isFrontmatter, index + 1 < lines.count,
               MarkdownSourceTable.parse(lines[index...index + 1].map(\.text).joined(separator: "\n")) != nil {
                index += 2
                while index < lines.count, !lines[index].isBlank, isTableBodyLine(lines[index].text),
                    pluginBlock(at: index, lines: lines, pluginLines: pluginLines) == nil {
                    index += 1
                }
                let tableSource = lines[start..<index].map(\.text).joined(separator: "\n")
                kind = .table(MarkdownSourceTable.parse(tableSource)!)
            } else {
                switch classification {
            case let .heading(level, prefix):
                kind = .heading(level: level, markdown: String(lines[index].text.dropFirst(prefix.count)))
                index += 1
            case let .fence(marker, count, info):
                index += 1
                let contentStart = index
                while index < lines.count && !isFenceCloser(lines[index].text, marker: marker, count: count) { index += 1 }
                let code = lines[contentStart..<index].map(\.raw).joined()
                if index < lines.count { index += 1 }
                kind = .fencedCode(fence: String(repeating: String(marker), count: count), info: info,
                                   code: stripFinalLineEnding(code))
            case .horizontalRule:
                kind = .horizontalRule
                index += 1
            case .list:
                index += 1
                while index < lines.count && !lines[index].isBlank &&
                    !isDefiniteBreak(lines[index].text, at: index, lines: lines, pluginLines: pluginLines) { index += 1 }
                let source = lines[start..<index].map(\.raw).joined()
                kind = MarkdownSourceList.parse(source).map(MarkdownSemanticBlock.list) ?? .raw
            case .raw:
                index += 1
                if start == 0 && lines[start].text.trimmingCharacters(in: .whitespaces) == "---" {
                    while index < lines.count {
                        let closing = lines[index].text.trimmingCharacters(in: .whitespaces) == "---"
                        index += 1
                        if closing { break }
                    }
                } else {
                    while index < lines.count && !lines[index].isBlank &&
                        !isDefiniteBreak(lines[index].text, at: index, lines: lines, pluginLines: pluginLines) { index += 1 }
                }
                kind = .raw
            case .paragraph:
                index += 1
                while index < lines.count && !lines[index].isBlank &&
                    !isNewBlock(lines[index].text, at: index, lines: lines, pluginLines: pluginLines) { index += 1 }
                let source = lines[start..<index].map(\.raw).joined()
                kind = .paragraph(markdown: stripFinalLineEnding(source))
                }
            }
            let source = lines[start..<index].map(\.raw).joined()
            blocks.append(.init(id: "block-\(blocks.count)", kind: kind, source: source,
                                leadingTrivia: pendingTrivia))
            pendingTrivia = ""
        }
        return .init(blocks: blocks, trailingTrivia: pendingTrivia)
    }

    public func serialize(_ document: MarkdownDocument) -> String { document.toMarkdown() }

    private enum Classification {
        case paragraph
        case heading(Int, String)
        case fence(Character, Int, String)
        case horizontalRule
        case list
        case raw
    }

    private func classify(_ line: String) -> Classification {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if let match = match(#"^([ \t]{0,3})(#{1,6}[ \t]+)"#, in: line) {
            return .heading(match[2].prefix(while: { $0 == "#" }).count, match[1] + match[2])
        }
        if let marker = trimmed.first, marker == "`" || marker == "~" {
            let count = trimmed.prefix(while: { $0 == marker }).count
            if count >= 3 { return .fence(marker, count, String(trimmed.dropFirst(count))) }
        }
        if isRule(trimmed) { return .horizontalRule }
        if MarkdownSourceList.isListStart(line) { return .list }
        if match(#"^(?: {0,3}(?:>|[-*+]\s+|[0-9]+[.)]\s+|\$\$|<|\|)|\t)"#, in: line) != nil { return .raw }
        return .paragraph
    }

    private func isNewBlock(_ line: String, at index: Int, lines: [SourceLine], pluginLines: [String]) -> Bool {
        if pluginBlock(at: index, lines: lines, pluginLines: pluginLines) != nil { return true }
        switch classify(line) {
        case .paragraph: return false
        default: return true
        }
    }

    private func isTableBodyLine(_ line: String) -> Bool {
        if line.contains("|") { return true }
        if case .paragraph = classify(line) { return true }
        return false
    }

    private func isDefiniteBreak(_ line: String, at index: Int, lines: [SourceLine], pluginLines: [String]) -> Bool {
        if pluginBlock(at: index, lines: lines, pluginLines: pluginLines) != nil { return true }
        switch classify(line) {
        case .heading, .fence, .horizontalRule: return true
        case .paragraph, .list, .raw: return false
        }
    }

    /// Keep the original source in the semantic match; plugins parse normalized lines,
    /// while editor selections and replacements must retain CRLF and exact trivia.
    private func pluginBlock(at index: Int, lines: [SourceLine], pluginLines: [String])
        -> (id: String, match: BlockPluginMatch)? {
        guard let plugins, !lines[index].isBlank else { return nil }
        for plugin in plugins.findBlockPlugins(pluginLines[index], lines: pluginLines, at: index) {
            guard let parsed = plugin.parse(pluginLines, at: index), parsed.linesConsumed > 0,
                  parsed.linesConsumed <= lines.count - index else { continue }
            let source = lines[index..<(index + parsed.linesConsumed)].map(\.raw).joined()
            return (plugin.id, BlockPluginMatch(linesConsumed: parsed.linesConsumed, source: source,
                                                content: parsed.content, attributes: parsed.attributes))
        }
        return nil
    }

    private func isRule(_ trimmed: String) -> Bool {
        let compact = trimmed.filter { !$0.isWhitespace }
        guard compact.count >= 3, let first = compact.first, first == "-" || first == "*" || first == "_" else { return false }
        return compact.allSatisfy { $0 == first }
    }

    private func isFenceCloser(_ line: String, marker: Character, count: Int) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let run = trimmed.prefix(while: { $0 == marker }).count
        return run >= count && trimmed.dropFirst(run).trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func stripFinalLineEnding(_ source: String) -> String {
        let value = source as NSString
        if source.hasSuffix("\r\n") { return value.substring(to: value.length - 2) }
        if source.hasSuffix("\n") { return value.substring(to: value.length - 1) }
        return source
    }

    private func match(_ pattern: String, in line: String) -> [String]? {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }
        let source = line as NSString
        guard let result = expression.firstMatch(in: line, range: NSRange(location: 0, length: source.length)) else { return nil }
        return (0..<result.numberOfRanges).map { result.range(at: $0).location == NSNotFound ? "" : source.substring(with: result.range(at: $0)) }
    }
}

private struct SourceLine {
    let text: String
    let raw: String
    var isBlank: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}
