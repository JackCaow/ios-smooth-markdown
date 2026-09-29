import Foundation

/// The first source-preserving semantic block types supported by the native editor.
public enum MarkdownSemanticBlock: Equatable {
    case paragraph(markdown: String)
    case heading(level: Int, markdown: String)
    case fencedCode(fence: String, info: String, code: String)
    case table(MarkdownSourceTable)
    case list(MarkdownSourceList)
    case horizontalRule
    /// An opt-in top-level block parsed by a registered host plugin.
    case plugin(id: String, match: BlockPluginMatch)
    case raw
}

/// A block keeps its exact original source and the whitespace preceding it.
public struct MarkdownDocumentBlock: Equatable, Identifiable {
    public let id: String
    public let kind: MarkdownSemanticBlock
    public let source: String
    public let leadingTrivia: String

    public init(id: String, kind: MarkdownSemanticBlock, source: String, leadingTrivia: String = "") {
        self.id = id
        self.kind = kind
        self.source = source
        self.leadingTrivia = leadingTrivia
    }

    public var plainText: String {
        switch kind {
        case let .paragraph(markdown), let .heading(_, markdown): markdown
        case let .fencedCode(_, _, code): code
        case let .table(table): table.toMarkdown()
        case let .list(list): list.plainText
        case .horizontalRule: ""
        case let .plugin(_, match): match.content
        case .raw: source
        }
    }

    /// Replaces editable body content while retaining the original marker and line ending.
    /// Raw blocks and rules deliberately have no semantic body edit yet.
    public func replacingContent(_ content: String) -> MarkdownDocumentBlock? {
        let ending = source.hasSuffix("\r\n") ? "\r\n" : source.hasSuffix("\n") ? "\n" : ""
        switch kind {
        case .paragraph:
            return validated(.init(id: id, kind: .paragraph(markdown: content), source: content + ending, leadingTrivia: leadingTrivia))
        case let .heading(level, _):
            let pattern = try! NSRegularExpression(pattern: #"^([ \t]{0,3}#{1,6}[ \t]+)"#)
            let original = source as NSString
            let match = pattern.firstMatch(in: source, range: NSRange(location: 0, length: original.length))
            let prefix = match.map { original.substring(with: $0.range(at: 1)) } ?? String(repeating: "#", count: level) + " "
            return validated(.init(id: id, kind: .heading(level: level, markdown: content),
                                   source: prefix + content + ending, leadingTrivia: leadingTrivia))
        case let .fencedCode(fence, info, _):
            let lines = source.components(separatedBy: "\n")
            guard let opening = lines.first else { return nil }
            let newline = source.contains("\r\n") ? "\r\n" : "\n"
            let opener = opening.trimmingCharacters(in: .newlines) + newline
            let hasCloser = lines.dropFirst().contains { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.hasPrefix(fence) && trimmed.dropFirst(fence.count).trimmingCharacters(in: .whitespaces).isEmpty
            }
            let closer = hasCloser ? fence + ending : ""
            let rendered = opener + content + (content.hasSuffix(newline) || content.isEmpty ? "" : newline) + closer
            return validated(.init(id: id, kind: .fencedCode(fence: fence, info: info, code: content),
                                   source: rendered, leadingTrivia: leadingTrivia))
        case .table, .list, .horizontalRule, .plugin, .raw: return nil
        }
    }

    private func validated(_ candidate: MarkdownDocumentBlock) -> MarkdownDocumentBlock? {
        let reparsed = MarkdownDocumentCodec().parse(candidate.source)
        guard reparsed.blocks.count == 1 else { return nil }
        switch (kind, reparsed.blocks[0].kind) {
        case (.paragraph, .paragraph), (.fencedCode, .fencedCode): return candidate
        case let (.heading(originalLevel, _), .heading(newLevel, _)) where originalLevel == newLevel: return candidate
        default: return nil
        }
    }
}

/// Immutable, source-preserving top-level document snapshot.
public struct MarkdownDocument: Equatable {
    public let blocks: [MarkdownDocumentBlock]
    public let trailingTrivia: String

    public init(blocks: [MarkdownDocumentBlock], trailingTrivia: String = "") {
        self.blocks = blocks
        self.trailingTrivia = trailingTrivia
    }

    public var isEmpty: Bool { blocks.allSatisfy { $0.plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
    public var plainText: String { blocks.map(\.plainText).joined(separator: "\n\n") }
    public func toMarkdown() -> String { blocks.map { $0.leadingTrivia + $0.source }.joined() + trailingTrivia }
    public func blockById(_ id: String) -> MarkdownDocumentBlock? { blocks.first { $0.id == id } }

    /// UTF-16 source range for one block, excluding its leading whitespace.
    public func sourceRange(of id: String) -> NSRange? {
        var offset = 0
        for block in blocks {
            offset += (block.leadingTrivia as NSString).length
            let length = (block.source as NSString).length
            if block.id == id { return NSRange(location: offset, length: length) }
            offset += length
        }
        return nil
    }

    /// UTF-16 source span of one table cell's content, excluding surrounding
    /// cell padding. Used only when a visible cell can be mapped back exactly
    /// to source for a paste that cannot be represented as a table grid.
    public func sourceRangeOfTableCell(blockID: String, row: Int, column: Int) -> NSRange? {
        guard let block = blockById(blockID), case let .table(table) = block.kind,
              row >= 0, row <= table.rows.count, table.headers.indices.contains(column),
              let blockRange = sourceRange(of: blockID) else { return nil }
        let lineIndex = row == 0 ? 0 : row + 1
        let lines = block.source.components(separatedBy: "\n")
        guard lines.indices.contains(lineIndex) else { return nil }
        let rawLine = lines[lineIndex].hasSuffix("\r") ? String(lines[lineIndex].dropLast()) : lines[lineIndex]
        let line = rawLine as NSString
        var separators: [Int] = []
        var slashes = 0
        for (offset, unit) in rawLine.utf16.enumerated() {
            if unit == 124, slashes.isMultiple(of: 2) { separators.append(offset) }
            slashes = unit == 92 ? slashes + 1 : 0
        }
        let boundaries = [-1] + separators + [line.length]
        var cells = zip(boundaries, boundaries.dropFirst()).map { left, right in
            NSRange(location: left + 1, length: right - left - 1)
        }
        let trimmedLine = rawLine.trimmingCharacters(in: .whitespaces)
        if trimmedLine.hasPrefix("|"), let first = cells.first,
           line.substring(with: first).trimmingCharacters(in: .whitespaces).isEmpty { cells.removeFirst() }
        if trimmedLine.hasSuffix("|"), let last = cells.last,
           line.substring(with: last).trimmingCharacters(in: .whitespaces).isEmpty { cells.removeLast() }
        guard cells.indices.contains(column) else { return nil }
        let padded = line.substring(with: cells[column])
        let expected = row == 0 ? table.headers[column] : table.rows[row - 1][column]
        guard padded.trimmingCharacters(in: .whitespaces) == expected else { return nil }
        let left = padded.prefix { $0 == " " || $0 == "\t" }.utf16.count
        let right = min(String(padded.reversed().prefix { $0 == " " || $0 == "\t" }).utf16.count,
                        cells[column].length - left)
        let lineOffset = lines[..<lineIndex].reduce(0) { $0 + ($1 as NSString).length + 1 }
        return NSRange(location: blockRange.location + lineOffset + cells[column].location + left,
                       length: cells[column].length - left - right)
    }

    public func replacingBlock(_ replacement: MarkdownDocumentBlock) -> MarkdownDocument {
        guard let index = blocks.firstIndex(where: { $0.id == replacement.id }) else { return self }
        var next = blocks
        next[index] = replacement
        return .init(blocks: next, trailingTrivia: trailingTrivia)
    }

    public func movingBlock(_ id: String, to targetIndex: Int) -> MarkdownDocument {
        guard let index = blocks.firstIndex(where: { $0.id == id }), blocks.count > 1 else { return self }
        let target = min(max(0, targetIndex), blocks.count - 1)
        guard index != target else { return self }
        var next = blocks
        let block = next.remove(at: index)
        next.insert(block, at: target)
        let trivia = blocks.map(\.leadingTrivia)
        next = next.enumerated().map { position, item in
            .init(id: item.id, kind: item.kind, source: item.source, leadingTrivia: trivia[position])
        }
        return .init(blocks: next, trailingTrivia: trailingTrivia)
    }

    public func removingBlock(_ id: String) -> MarkdownDocument {
        guard let index = blocks.firstIndex(where: { $0.id == id }) else { return self }
        var next = blocks
        let removed = next.remove(at: index)
        if index == 0 && !next.isEmpty {
            let first = next[0]
            next[0] = .init(id: first.id, kind: first.kind, source: first.source,
                            leadingTrivia: removed.leadingTrivia)
        }
        return .init(blocks: next, trailingTrivia: trailingTrivia)
    }

    /// Applies a table edit while retaining the surrounding document source and line ending.
    public func updatingTable(_ id: String, preservingSource: Bool = false,
                              _ transform: (MarkdownSourceTable) -> MarkdownSourceTable) -> MarkdownDocument? {
        guard let block = blockById(id), case let .table(table) = block.kind else { return nil }
        let updated = transform(table)
        guard updated != table else { return nil }
        if let source = Self.sourcePreservingTableCellEdits(block.source, from: table, to: updated) {
            return replacingBlock(.init(id: id, kind: .table(updated), source: source,
                                        leadingTrivia: block.leadingTrivia))
        }
        if preservingSource { return nil }
        let ending = block.source.hasSuffix("\r\n") ? "\r\n" : block.source.hasSuffix("\n") ? "\n" : ""
        let newline = block.source.contains("\r\n") ? "\r\n" : "\n"
        let source = updated.toMarkdown().replacingOccurrences(of: "\n", with: newline) + ending
        let replacement = MarkdownDocumentBlock(id: id, kind: .table(updated), source: source,
                                                leadingTrivia: block.leadingTrivia)
        return replacingBlock(replacement)
    }

    /// Cell edits should not rewrite untouched spacing, delimiter widths, or line endings.
    /// Structural changes still use the table serializer above.
    private static func sourcePreservingTableCellEdits(_ source: String, from old: MarkdownSourceTable,
                                                       to updated: MarkdownSourceTable) -> String? {
        guard old.headers.count == updated.headers.count, old.rows.count == updated.rows.count,
              old.alignments == updated.alignments else { return nil }
        var changes: [(line: Int, column: Int, before: String, after: String)] = []
        func record(_ line: Int, _ column: Int, _ before: String, _ after: String) {
            if before != after { changes.append((line, column, before, after)) }
        }
        for column in old.headers.indices {
            record(0, column, old.headers[column], updated.headers[column])
        }
        for row in old.rows.indices {
            guard old.rows[row].count == updated.rows[row].count else { return nil }
            for column in old.rows[row].indices {
                record(row + 2, column, old.rows[row][column], updated.rows[row][column])
            }
        }
        guard !changes.isEmpty else { return nil }
        let lines = source.components(separatedBy: "\n")
        var edits: [(range: NSRange, replacement: String)] = []
        for change in changes {
            guard lines.indices.contains(change.line) else { return nil }
            let rawLine = lines[change.line].hasSuffix("\r") ? String(lines[change.line].dropLast()) : lines[change.line]
            let lineSource = rawLine as NSString
            let units = Array(rawLine.utf16)
            var separatorOffsets: [Int] = []
            var slashes = 0
            for (index, unit) in units.enumerated() {
                if unit == 124, slashes.isMultiple(of: 2) { separatorOffsets.append(index) }
                slashes = unit == 92 ? slashes + 1 : 0
            }
            let boundaries = [-1] + separatorOffsets + [lineSource.length]
            var cells = zip(boundaries, boundaries.dropFirst()).map { left, right in
                NSRange(location: left + 1, length: right - left - 1)
            }
            let trimmedLine = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmedLine.hasPrefix("|"), let first = cells.first,
               lineSource.substring(with: first).trimmingCharacters(in: .whitespaces).isEmpty {
                cells.removeFirst()
            }
            if trimmedLine.hasSuffix("|"), let last = cells.last,
               lineSource.substring(with: last).trimmingCharacters(in: .whitespaces).isEmpty {
                cells.removeLast()
            }
            guard cells.indices.contains(change.column) else { return nil }
            let cell = lineSource.substring(with: cells[change.column])
            guard cell.trimmingCharacters(in: .whitespaces) == change.before else { return nil }
            let left = cell.prefix { $0 == " " || $0 == "\t" }.utf16.count
            let right = min(String(cell.reversed().prefix { $0 == " " || $0 == "\t" }).utf16.count,
                            cells[change.column].length - left)
            let contentRange = NSRange(location: cells[change.column].location + left,
                                       length: cells[change.column].length - left - right)
            let lineOffset = lines[..<change.line].reduce(0) { $0 + ($1 as NSString).length + 1 }
            edits.append((NSRange(location: lineOffset + contentRange.location, length: contentRange.length),
                          change.after))
        }
        var result = source
        for edit in edits.sorted(by: { $0.range.location > $1.range.location }) {
            result = (result as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
        }
        let reparsed = MarkdownDocumentCodec().parse(result)
        guard reparsed.blocks.count == 1, reparsed.blocks[0].kind == .table(updated),
              reparsed.toMarkdown() == result else { return nil }
        return result
    }

    /// Applies a list edit while preserving every marker, continuation prefix, and untouched source line.
    public func updatingList(_ id: String, _ transform: (MarkdownSourceList) -> MarkdownSourceList?) -> MarkdownDocument? {
        guard let block = blockById(id), case let .list(list) = block.kind,
              let updated = transform(list), updated != list else { return nil }
        let parsed = MarkdownDocumentCodec().parse(updated.toMarkdown())
        guard parsed.blocks.count == 1, case let .list(reparsed) = parsed.blocks[0].kind,
              reparsed == updated else { return nil }
        let replacement = MarkdownDocumentBlock(id: id, kind: .list(updated), source: updated.toMarkdown(),
                                                leadingTrivia: block.leadingTrivia)
        return replacingBlock(replacement)
    }
}
