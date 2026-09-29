import Foundation

/// A search hit in text that Blocks mode actually displays. Coordinates are
/// UTF-16 offsets within the corresponding rendered or editable row.
struct MarkdownFormattedFindMatch: Equatable {
    enum Field: Equatable {
        case prose
        case listItem(Int)
        case listContinuation(item: Int, line: Int)
        case listTrailing(item: Int, line: Int)
        case quoteLine(Int)
        /// Row zero is the header; body rows start at one.
        case tableCell(row: Int, column: Int)
        case rawText
    }

    let blockID: String
    let field: Field
    let range: NSRange
}

enum MarkdownFormattedFind {
    static func matches(in document: MarkdownDocument, query: String, limit: Int = 500,
                        isCustomBlockRendered: ((MarkdownDocumentBlock) -> Bool)? = nil) -> [MarkdownFormattedFindMatch] {
        guard !query.isEmpty, limit > 0 else { return [] }
        var result: [MarkdownFormattedFindMatch] = []
        for (blockIndex, block) in document.blocks.enumerated() {
            if isCustomBlockRendered?(block) == true { continue }
            switch block.kind {
            case .paragraph, .heading:
                // The inline map omits Markdown markers and link destinations.
                // Unsupported inline syntax is not searched as visible prose.
                if let visible = MarkdownInlineMarkEditor.visibleText(of: block.plainText) {
                    append(visible, blockID: block.id, field: .prose, query: query, limit: limit, to: &result)
                }
            case let .list(list):
                for (index, item) in list.items.enumerated() {
                    append(item.content, blockID: block.id, field: .listItem(index),
                           query: query, limit: limit, to: &result)
                    for (line, continuation) in item.continuations.enumerated() {
                        append(continuation.content, blockID: block.id,
                               field: .listContinuation(item: index, line: line),
                               query: query, limit: limit, to: &result)
                    }
                    for owner in list.trailingOwners(after: index) {
                        for (line, continuation) in list.items[owner].trailingContinuations.enumerated() {
                            append(continuation.content, blockID: block.id,
                                   field: .listTrailing(item: owner, line: line),
                                   query: query, limit: limit, to: &result)
                        }
                    }
                    if result.count == limit { break }
                }
            case let .table(table):
                for row in 0...table.rows.count {
                    let cells = row == 0 ? table.headers : table.rows[row - 1]
                    for (column, cell) in cells.enumerated() {
                        // The editable field unescapes literal pipes but retains inline Markdown.
                        append(cell.replacingOccurrences(of: "\\|", with: "|"), blockID: block.id,
                               field: .tableCell(row: row, column: column),
                               query: query, limit: limit, to: &result)
                        if result.count == limit { break }
                    }
                    if result.count == limit { break }
                }
            case .raw:
                if let quote = MarkdownSourceQuote(source: block.source) {
                    for (index, line) in quote.lines.enumerated() {
                        append(line.content, blockID: block.id, field: .quoteLine(index),
                               query: query, limit: limit, to: &result)
                        if result.count == limit { break }
                    }
                } else if blockIndex != 0 || MarkdownSourceFrontmatter.parsePrefix(block.source)?.source != block.source {
                    append(rawDisplayText(block.source), blockID: block.id, field: .rawText,
                           query: query, limit: limit, to: &result)
                }
            case .fencedCode, .horizontalRule, .plugin: break
            }
            if result.count == limit { break }
        }
        return result
    }

    static func rawDisplayText(_ source: String) -> String {
        source.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func append(_ text: String, blockID: String, field: MarkdownFormattedFindMatch.Field,
                               query: String, limit: Int, to result: inout [MarkdownFormattedFindMatch]) {
        let haystack = text as NSString
        var offset = 0
        while offset < haystack.length && result.count < limit {
            let found = haystack.range(of: query, options: [.caseInsensitive],
                                       range: NSRange(location: offset, length: haystack.length - offset))
            guard found.location != NSNotFound, found.length > 0 else { break }
            result.append(.init(blockID: blockID, field: field, range: found))
            offset = NSMaxRange(found)
        }
    }
}
