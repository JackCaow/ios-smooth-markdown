import Foundation

/// Source-backed top-level block transforms for the formatted editor.
/// Only prose is transformed; reparsing verifies that adjacent untouched blocks
/// keep their exact source, trivia, and semantic kind.
enum MarkdownBlockRangeTransform {
    static func render(document: MarkdownDocument, range: ClosedRange<Int>,
                       command: MarkdownEditorCommand, codec: MarkdownDocumentCodec) -> String? {
        guard document.blocks.indices.contains(range.lowerBound),
              document.blocks.indices.contains(range.upperBound) else { return nil }
        let selected = Array(document.blocks[range])
        let bodies = selected.compactMap { block -> String? in
            switch block.kind {
            case let .paragraph(markdown), let .heading(_, markdown): markdown
            default: nil
            }
        }
        guard bodies.count == selected.count, !bodies.isEmpty else { return nil }
        let newline = document.toMarkdown().contains("\r\n") ? "\r\n" : "\n"
        let replacements: [MarkdownDocumentBlock]
        let expected: Expected
        switch command {
        case .paragraph, .heading1, .heading2, .heading3, .heading4, .heading5, .heading6:
            let level = command.headingLevel
            guard bodies.allSatisfy({ !$0.contains("\n") && !$0.contains("\r") }) else { return nil }
            replacements = zip(selected, bodies).map { block, body in
                let ending = lineEnding(of: block.source)
                let source = (level.map { String(repeating: "#", count: $0) + " " } ?? "") + body + ending
                return .init(id: block.id, kind: block.kind, source: source,
                             leadingTrivia: block.leadingTrivia)
            }
            expected = level.map(Expected.heading) ?? .paragraph
        case .unorderedList, .orderedList, .taskList:
            let kind: MarkdownSourceListItem.Kind = switch command {
            case .orderedList: .ordered
            case .taskList: .task
            default: .unordered
            }
            let lines = bodies.enumerated().map { index, body -> String in
                let prefix: String
                switch command {
                case .orderedList: prefix = "\(index + 1). "
                case .taskList: prefix = "- [ ] "
                default: prefix = "- "
                }
                let continuation = String(repeating: " ", count: prefix.count)
                return body.replacingOccurrences(of: "\r\n", with: "\n")
                    .components(separatedBy: "\n").enumerated().map { line, content in
                        (line == 0 ? prefix : continuation) + content
                    }.joined(separator: newline)
            }
            let source = lines.joined(separator: newline) + lineEnding(of: selected.last!.source)
            replacements = [.init(id: selected[0].id, kind: selected[0].kind, source: source,
                                  leadingTrivia: selected[0].leadingTrivia)]
            expected = .list(kind: kind, items: selected.count)
        case .blockquote:
            let lines = bodies.flatMap { body in
                body.replacingOccurrences(of: "\r\n", with: "\n")
                    .components(separatedBy: "\n").map { "> " + $0 }
            }
            let source = lines.joined(separator: newline) + lineEnding(of: selected.last!.source)
            replacements = [.init(id: selected[0].id, kind: selected[0].kind, source: source,
                                  leadingTrivia: selected[0].leadingTrivia)]
            expected = .blockquote
        default: return nil
        }

        var next = document.blocks
        next.replaceSubrange(range, with: replacements)
        let source = MarkdownDocument(blocks: next, trailingTrivia: document.trailingTrivia).toMarkdown()
        let parsed = codec.parse(source)
        guard parsed.toMarkdown() == source, parsed.blocks.count == next.count else { return nil }
        for index in parsed.blocks.indices {
            let actual = parsed.blocks[index]
            if index < range.lowerBound || index >= range.lowerBound + replacements.count {
                let originalIndex = index < range.lowerBound ? index : index + selected.count - replacements.count
                let original = document.blocks[originalIndex]
                guard actual.kind == original.kind, actual.source == original.source,
                      actual.leadingTrivia == original.leadingTrivia else { return nil }
            } else {
                let replacement = replacements[index - range.lowerBound]
                guard actual.source == replacement.source,
                      actual.leadingTrivia == replacement.leadingTrivia,
                      expected.accepts(actual.kind) else { return nil }
            }
        }
        return source == document.toMarkdown() ? nil : source
    }

    private static func lineEnding(of source: String) -> String {
        source.hasSuffix("\r\n") ? "\r\n" : source.hasSuffix("\n") ? "\n" : ""
    }

    private enum Expected {
        case paragraph, heading(Int), list(kind: MarkdownSourceListItem.Kind, items: Int), blockquote

        func accepts(_ kind: MarkdownSemanticBlock) -> Bool {
            switch (self, kind) {
            case (.paragraph, .paragraph): true
            case let (.heading(expected), .heading(actual, _)): expected == actual
            case let (.list(kind, items), .list(list)):
                list.items.count == items && list.items.allSatisfy { $0.kind == kind }
            case (.blockquote, .raw): true
            default: false
            }
        }
    }
}
