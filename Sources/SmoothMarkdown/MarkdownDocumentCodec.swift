import Foundation
#if canImport(SmoothMarkdownCore)
@_spi(ReaderInternals) import SmoothMarkdownCore
#endif

/// Imports Markdown without normalizing untouched syntax, whitespace, or line endings.
public struct MarkdownDocumentCodec {
    private let plugins: ParserPluginRegistry?

    /// Custom block syntax is recognized only when its registry is explicitly supplied.
    public init(plugins: ParserPluginRegistry? = nil) { self.plugins = plugins?.copy() }

    public func parse(_ markdown: String) -> MarkdownDocument {
        guard !markdown.isEmpty else { return .init(blocks: []) }
        let source = markdown as NSString
        var blocks: [MarkdownDocumentBlock] = []
        var trivia = ""
        func append(_ kind: MarkdownSemanticBlock, source raw: String) {
            blocks.append(.init(id: "block-\(blocks.count)", kind: kind, source: raw, leadingTrivia: trivia))
            trivia = ""
        }
        func appendMarkdown(_ raw: String, projection: PluginSharedSyntax.Result? = nil) {
            guard !raw.isEmpty else { return }
            guard let tree = projection?.tree ?? NativeMarkdownExtensionProjection.parse(raw) else {
                append(.raw, source: raw); return
            }
            let text = raw as NSString
            var cursor = 0
            var index = 0
            while index < tree.children.count {
                let node = tree.children[index]
                let range = node.sourceRange
                guard range.location >= cursor, range.length >= 0,
                      range.location <= text.length, range.length <= text.length - range.location else {
                    append(.raw, source: text.substring(from: cursor)); return
                }
                trivia += text.substring(with: NSRange(location: cursor, length: range.location - cursor))
                var end = NSMaxRange(range)
                var kind = semanticKind(node)
                if let payload = projection?.payload(for: node), case let .block(plugin, match) = payload {
                    kind = .plugin(id: plugin.id, match: projection!.blockMatch(match, node: node))
                }
                if case .list = node.kind, case .raw = kind {
                    // Loose sibling items keep separate editor separator slots.
                    // Rust's item ranges, rather than a blank-line grammar scan,
                    // supply the lossless boundaries for these editable groups.
                    let projected = node.children.compactMap { item -> (NSRange, MarkdownSourceList)? in
                        guard case .listItem = item.kind, let list = MarkdownSourceList.parse(item.source) else { return nil }
                        return (item.sourceRange, list)
                    }
                    if projected.count == node.children.count, !projected.isEmpty {
                        var itemCursor = range.location
                        for (itemRange, list) in projected {
                            trivia += text.substring(with: NSRange(location: itemCursor, length: itemRange.location - itemCursor))
                            append(.list(list), source: text.substring(with: itemRange))
                            itemCursor = NSMaxRange(itemRange)
                        }
                        trivia += text.substring(with: NSRange(location: itemCursor, length: end - itemCursor))
                        cursor = end; index += 1; continue
                    }
                }
                // Consecutive Rust list blocks may share one lossless editor row
                // group. The Rust AST still decides where all standard blocks end.
                if case .list = node.kind {
                    var next = index + 1
                    while next < tree.children.count, case .list = tree.children[next].kind,
                          tree.children[next].sourceRange.location == end {
                        let candidateEnd = NSMaxRange(tree.children[next].sourceRange)
                        let candidate = text.substring(with: NSRange(location: range.location, length: candidateEnd - range.location))
                        guard let list = MarkdownSourceList.parse(candidate) else { break }
                        kind = .list(list); end = candidateEnd; index = next; next += 1
                    }
                }
                append(kind, source: text.substring(with: NSRange(location: range.location, length: end - range.location)))
                cursor = end; index += 1
            }
            trivia += text.substring(from: cursor)
        }
        let frontmatter = MarkdownSourceFrontmatter.parsePrefix(markdown)
        let bodyStart = frontmatter.map { ($0.source as NSString).length } ?? 0
        if let frontmatter { append(.raw, source: frontmatter.source) }
        guard let plugins else {
            appendMarkdown(source.substring(from: bodyStart))
            return .init(blocks: blocks, trailingTrivia: trivia)
        }
        let body = source.substring(from: bodyStart)
        if let projection = PluginSharedSyntax.parse(body, registry: plugins, includeInline: false) {
            appendMarkdown(body, projection: projection)
        } else {
            append(.raw, source: body)
        }
        return .init(blocks: blocks, trailingTrivia: trivia)
    }

    public func serialize(_ document: MarkdownDocument) -> String { document.toMarkdown() }

    private func semanticKind(_ node: NativeMarkdownNode) -> MarkdownSemanticBlock {
        switch node.kind {
        case .paragraph:
            // Raw host editor rows are a presentation policy for unsupported HTML,
            // quote-like and pipe-prefixed prose, after Rust identifies the syntax.
            let first = node.source.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !["<", "|", ">", "$$"].contains(where: first.hasPrefix) else { return .raw }
            return .paragraph(markdown: stripFinalLineEnding(node.source))
        case let .heading(level):
            guard let prefix = match(#"^([ \t]{0,3}#{1,6}[ \t]+)"#, in: node.source)?.first else { return .raw }
            let body = (node.source as NSString).substring(from: (prefix as NSString).length)
            return .heading(level: level, markdown: stripFinalLineEnding(body))
        case .fencedCode:
            let lines = sourceLines(node.source)
            guard let opening = lines.first else { return .raw }
            let trimmed = opening.text.trimmingCharacters(in: .whitespaces)
            guard let marker = trimmed.first else { return .raw }
            let fence = String(trimmed.prefix { $0 == marker })
            let info = String(trimmed.dropFirst(fence.count))
            var body = Array(lines.dropFirst())
            if let final = body.last, isFenceCloser(final.text, marker: marker, count: fence.count) { body.removeLast() }
            return .fencedCode(fence: fence, info: info, code: stripFinalLineEnding(body.map(\.raw).joined()))
        case .table: return .table(MarkdownSourceTable.fromAST(node))
        case .list: return MarkdownSourceList.parse(node.source).map(MarkdownSemanticBlock.list) ?? .raw
        case .thematicBreak: return .horizontalRule
        default: return .raw
        }
    }

    private func isFenceCloser(_ line: String, marker: Character, count: Int) -> Bool {
        let text = line.trimmingCharacters(in: .whitespaces)
        let run = text.prefix { $0 == marker }.count
        return run >= count && text.dropFirst(run).trimmingCharacters(in: .whitespaces).isEmpty
    }
    private func stripFinalLineEnding(_ source: String) -> String {
        let value = source as NSString
        if source.hasSuffix("\r\n") { return value.substring(to: value.length - 2) }
        if source.hasSuffix("\n") || source.hasSuffix("\r") { return value.substring(to: value.length - 1) }
        return source
    }
    private func match(_ pattern: String, in source: String) -> [String]? {
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let found = expression.firstMatch(in: source, range: NSRange(location: 0, length: (source as NSString).length)) else { return nil }
        return (1..<found.numberOfRanges).map { (source as NSString).substring(with: found.range(at: $0)) }
    }
    private func sourceLines(_ source: String) -> [SourceLine] {
        let text = source as NSString
        var lines: [SourceLine] = []
        var offset = 0
        while offset < text.length {
            var bodyEnd = offset
            while bodyEnd < text.length, text.character(at: bodyEnd) != 10, text.character(at: bodyEnd) != 13 { bodyEnd += 1 }
            var end = bodyEnd
            if end < text.length {
                end += text.character(at: end) == 13 && end + 1 < text.length && text.character(at: end + 1) == 10 ? 2 : 1
            }
            let range = NSRange(location: offset, length: end - offset)
            let raw = text.substring(with: range)
            let body = text.substring(with: NSRange(location: offset, length: bodyEnd - offset))
            lines.append(.init(text: body, raw: raw, start: offset, end: NSMaxRange(range)))
            offset = NSMaxRange(range)
        }
        return lines
    }
}

private struct SourceLine {
    let text: String
    let raw: String
    let start: Int
    let end: Int
    var isBlank: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}
