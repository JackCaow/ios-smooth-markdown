import Foundation

/// A search hit in text that Blocks mode actually displays. Coordinates are
/// UTF-16 offsets within the corresponding rendered or editable row.
struct MarkdownFormattedFindMatch: Equatable {
    enum Field: Equatable {
        case prose
        case listItem(Int)
        case quoteLine(Int)
    }

    let blockID: String
    let field: Field
    let range: NSRange
}

enum MarkdownFormattedFind {
    static func matches(in document: MarkdownDocument, query: String, limit: Int = 500) -> [MarkdownFormattedFindMatch] {
        guard !query.isEmpty, limit > 0 else { return [] }
        var result: [MarkdownFormattedFindMatch] = []
        for block in document.blocks {
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
                    if result.count == limit { break }
                }
            case .raw:
                if let quote = MarkdownSourceQuote(source: block.source) {
                    for (index, line) in quote.lines.enumerated() {
                        append(line.content, blockID: block.id, field: .quoteLine(index),
                               query: query, limit: limit, to: &result)
                        if result.count == limit { break }
                    }
                }
            case .fencedCode, .table, .horizontalRule, .plugin: break
            }
            if result.count == limit { break }
        }
        return result
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
