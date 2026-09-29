import Combine
import Foundation

/// The focused empty paragraph created when Return exits a root list item.
/// Its draft is also written to `text`; this state only keeps the Blocks field alive while typing.
struct PendingListParagraph: Equatable {
    let sourceOffset: Int
    let draft: String
    let insertedTerminator: String
}

/// A UTF-16 offset in formatted prose, a list item's physical source line,
/// a fenced code body, or the visible text of one GFM table cell.
public struct MarkdownSemanticTextPosition: Equatable {
    public let blockID: String
    public let offset: Int
    /// The item within a source-backed list. `nil` outside lists.
    public let listItemIndex: Int?
    /// A paragraph continuation before nested children, or a deferred
    /// continuation after children. Both are `nil` for the item's primary line.
    public let listContinuationIndex: Int?
    public let listTrailingIndex: Int?
    /// A table row and column, with row zero denoting the header. Both are
    /// required for a cell endpoint; its offset excludes cell padding and escapes.
    public let tableRow: Int?
    public let tableColumn: Int?
    /// Physical explicit `>` line inside a simple source-backed quote.
    public let quoteLineIndex: Int?

    public init(blockID: String, offset: Int, listItemIndex: Int? = nil,
                listContinuationIndex: Int? = nil, listTrailingIndex: Int? = nil,
                tableRow: Int? = nil, tableColumn: Int? = nil,
                quoteLineIndex: Int? = nil) {
        self.blockID = blockID
        self.offset = offset
        self.listItemIndex = listItemIndex
        self.listContinuationIndex = listContinuationIndex
        self.listTrailingIndex = listTrailingIndex
        self.tableRow = tableRow
        self.tableColumn = tableColumn
        self.quoteLineIndex = quoteLineIndex
    }
}

/// Two character endpoints in the formatted document; either direction is valid.
public struct MarkdownSemanticTextSelection: Equatable {
    /// Optional source snapshot. Pass it for commands captured from a Blocks UI.
    public let source: String?
    public let anchor: MarkdownSemanticTextPosition
    public let focus: MarkdownSemanticTextPosition

    public init(anchor: MarkdownSemanticTextPosition, focus: MarkdownSemanticTextPosition,
                source: String? = nil) {
        self.source = source
        self.anchor = anchor
        self.focus = focus
    }
}

/// A UTF-16 offset in rendered paragraph or ATX-heading text, excluding Markdown markers.
public struct MarkdownVisibleTextPosition: Equatable {
    public let blockID: String
    public let offset: Int

    public init(blockID: String, offset: Int) {
        self.blockID = blockID
        self.offset = offset
    }
}

/// A source-revision-bound selection in rendered text across adjacent prose blocks.
public struct MarkdownVisibleTextSelection: Equatable {
    public let source: String
    public let anchor: MarkdownVisibleTextPosition
    public let focus: MarkdownVisibleTextPosition

    public init(source: String, anchor: MarkdownVisibleTextPosition, focus: MarkdownVisibleTextPosition) {
        self.source = source
        self.anchor = anchor
        self.focus = focus
    }
}

/// A contiguous run of sibling items inside one source-backed list block.
public struct MarkdownSemanticListItemSelection: Equatable {
    public let blockID: String
    public let anchorIndex: Int
    public let focusIndex: Int

    public init(blockID: String, anchorIndex: Int, focusIndex: Int) {
        self.blockID = blockID
        self.anchorIndex = anchorIndex
        self.focusIndex = focusIndex
    }
}

/// A rectangular group of table cells. Row zero is the header; body rows start at one.
public struct MarkdownSemanticTableCellSelection: Equatable {
    public let blockID: String
    public let anchorRow: Int
    public let anchorColumn: Int
    public let focusRow: Int
    public let focusColumn: Int

    public init(blockID: String, anchorRow: Int, anchorColumn: Int, focusRow: Int, focusColumn: Int) {
        self.blockID = blockID
        self.anchorRow = anchorRow
        self.anchorColumn = anchorColumn
        self.focusRow = focusRow
        self.focusColumn = focusColumn
    }
}

/// Source-backed editing commands. Offsets use UTF-16, matching UITextView selections.
@MainActor
public final class MarkdownEditorController: ObservableObject {
    @Published public private(set) var text: String
    @Published public private(set) var selection: NSRange
    @Published public private(set) var savedText: String
    @Published public var mode: MarkdownEditorMode = .source
    @Published private(set) var pendingListParagraph: PendingListParagraph?
    /// Emits every committed source edit, including rapid programmatic edits and undo/redo.
    /// An open transaction emits only its final source. Source IME composition is deferred.
    let committedTextChanges = PassthroughSubject<String, Never>()

    private struct Snapshot {
        let text: String
        let selection: NSRange
        let pendingListParagraph: PendingListParagraph?
    }
    private let historyLimit: Int
    private let plugins: ParserPluginRegistry?
    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []
    private var transactionDepth = 0
    private var transactionBefore: Snapshot?
    private var compositionStartingText: String?

    public init(text: String = "", historyLimit: Int = 100, plugins: ParserPluginRegistry? = nil) {
        self.text = text
        self.selection = NSRange(location: (text as NSString).length, length: 0)
        self.savedText = text
        self.historyLimit = max(0, historyLimit)
        self.plugins = plugins?.copy()
    }

    public var isDirty: Bool { text != savedText }
    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }
    public var selectedText: String { (text as NSString).substring(with: normalizedSelection()) }

    /// A source-preserving semantic snapshot for supported top-level blocks.
    public var semanticDocument: MarkdownDocument { codec.parse(text) }
    /// A snapshot of the editor's opt-in syntax registry for its preview.
    public var parserPlugins: ParserPluginRegistry? { plugins?.copy() }
    private var codec: MarkdownDocumentCodec { MarkdownDocumentCodec(plugins: plugins) }

    /// Replaces one host-recognized block only while the source snapshot that
    /// produced its editor context is still current. The replacement must
    /// remain one top-level block without changing its neighbors.
    @discardableResult
    func replaceCustomBlockMarkdown(id: String, expectedText: String, with markdown: String) -> Bool {
        guard text == expectedText else { return false }
        let document = semanticDocument
        guard let original = document.blockById(id) else { return false }
        let parsed = codec.parse(markdown)
        guard parsed.blocks.count == 1, parsed.trailingTrivia.isEmpty,
              parsed.blocks[0].leadingTrivia.isEmpty, parsed.blocks[0].source == markdown else { return false }
        let replacement = MarkdownDocumentBlock(id: id, kind: parsed.blocks[0].kind,
                                                source: markdown, leadingTrivia: original.leadingTrivia)
        let next = document.replacingBlock(replacement)
        guard isValidCustomBlockDocument(next, matching: next.blocks) else { return false }
        return replaceSemanticMarkdown(next.toMarkdown())
    }

    /// Deletes one block with the same stale-context and source-boundary checks.
    @discardableResult
    func deleteCustomBlock(id: String, expectedText: String) -> Bool {
        guard text == expectedText else { return false }
        let document = semanticDocument
        guard document.blockById(id) != nil else { return false }
        let next = document.removingBlock(id)
        guard isValidCustomBlockDocument(next, matching: next.blocks) else { return false }
        return replaceSemanticMarkdown(next.toMarkdown())
    }

    private func isValidCustomBlockDocument(_ document: MarkdownDocument,
                                            matching expectedBlocks: [MarkdownDocumentBlock]) -> Bool {
        let source = document.toMarkdown()
        let reparsed = codec.parse(source)
        return reparsed.toMarkdown() == source && reparsed.blocks.count == expectedBlocks.count &&
            zip(reparsed.blocks, expectedBlocks).allSatisfy { parsed, expected in
                parsed.kind == expected.kind && parsed.source == expected.source
            }
    }

    /// Copies complete top-level Blocks rows, including the exact source trivia between them.
    /// Endpoints may be tapped in either order. The first row's preceding trivia is omitted.
    public func copySemanticBlockRange(from startID: String, to endID: String) -> String? {
        let document = semanticDocument
        guard let range = semanticBlockRange(in: document, from: startID, to: endID) else { return nil }
        return document.blocks[range].enumerated().map { offset, block in
            (offset == 0 ? "" : block.leadingTrivia) + block.source
        }.joined()
    }

    /// A complete top-level range is deletable only when the remaining source
    /// reparses into the same blocks with the same trivia. This includes lists,
    /// tables, and custom blocks when deleting them cannot merge neighbours.
    public func canDeleteSemanticBlockRange(from startID: String, to endID: String) -> Bool {
        deletionMarkdown(from: startID, to: endID) != nil
    }

    /// Deletes a complete multi-block selection as one source-backed undo step.
    @discardableResult
    public func deleteSemanticBlockRange(from startID: String, to endID: String) -> Bool {
        guard let updated = deletionMarkdown(from: startID, to: endID) else { return false }
        return replaceSemanticMarkdown(updated)
    }

    private func semanticBlockRange(in document: MarkdownDocument, from startID: String,
                                    to endID: String) -> ClosedRange<Int>? {
        guard let first = document.blocks.firstIndex(where: { $0.id == startID }),
              let last = document.blocks.firstIndex(where: { $0.id == endID }), first != last else { return nil }
        return min(first, last)...max(first, last)
    }

    private func deletionMarkdown(from startID: String, to endID: String) -> String? {
        let document = semanticDocument
        guard let range = semanticBlockRange(in: document, from: startID, to: endID) else { return nil }
        var kept = document.blocks.enumerated().compactMap { range.contains($0.offset) ? nil : $0.element }
        if range.lowerBound == 0, !kept.isEmpty {
            let first = kept[0]
            kept[0] = .init(id: first.id, kind: first.kind, source: first.source,
                            leadingTrivia: document.blocks[0].leadingTrivia)
        }
        let updated = kept.isEmpty ? "" : MarkdownDocument(blocks: kept,
                                                               trailingTrivia: document.trailingTrivia).toMarkdown()
        let reparsed = codec.parse(updated)
        guard reparsed.toMarkdown() == updated, reparsed.blocks.count == kept.count,
              (kept.isEmpty || reparsed.trailingTrivia == document.trailingTrivia),
              zip(reparsed.blocks, kept).allSatisfy({ $0.0.kind == $0.1.kind &&
                  $0.0.source == $0.1.source && $0.0.leadingTrivia == $0.1.leadingTrivia }) else {
            return nil
        }
        return updated == text ? nil : updated
    }

    private struct ResolvedSemanticTextSelection {
        let firstIndex: Int
        let lastIndex: Int
        let start: MarkdownSemanticTextPosition
        let end: MarkdownSemanticTextPosition
        let startOffset: Int
        let endOffset: Int
        let startSourceOffset: Int
        let endSourceOffset: Int
    }

    /// Copies the selected text fragments as Markdown, preserving source trivia.
    /// A code endpoint crossing a block boundary gains its original fence so
    /// the copied fragment remains a valid fenced block.
    public func copySemanticTextRange(_ selection: MarkdownSemanticTextSelection) -> String? {
        guard let resolved = resolveSemanticTextSelection(selection) else { return nil }
        let document = semanticDocument
        let first = document.blocks[resolved.firstIndex]
        let last = document.blocks[resolved.lastIndex]
        if let lineIndex = resolved.start.quoteLineIndex,
           resolved.firstIndex == resolved.lastIndex,
           let quote = MarkdownSourceQuote(source: first.source),
           quote.lines.indices.contains(lineIndex) {
            let prefix = quote.lines[lineIndex].prefix
            let copied = (text as NSString).substring(with: NSRange(
                location: resolved.startSourceOffset,
                length: resolved.endSourceOffset - resolved.startSourceOffset))
            return prefix + copied
        }
        let start = resolved.startOffset == 0 && isHeading(first) ?
            document.sourceRange(of: first.id)!.location : resolved.startSourceOffset
        let end: Int
        if resolved.endOffset == 0 && isHeading(last) {
            end = document.sourceRange(of: last.id)!.location
        } else if let index = resolved.end.listItemIndex, resolved.endOffset == 0,
                  resolved.end.listContinuationIndex == nil, resolved.end.listTrailingIndex == nil,
                  case let .list(list) = last.kind, let itemStart = list.sourceOffset(ofItemAt: index) {
            end = document.sourceRange(of: last.id)!.location + itemStart
        } else {
            end = resolved.endSourceOffset
        }
        guard start <= end else { return nil }
        let range = NSRange(location: start, length: end - start)
        let copied = (text as NSString).substring(with: range)
        let listPrefix: String
        if let index = resolved.start.listItemIndex, case let .list(list) = first.kind {
            let item = list.items[index]
            if let line = resolved.start.listContinuationIndex {
                listPrefix = item.continuations[line].indent
            } else if let line = resolved.start.listTrailingIndex {
                listPrefix = item.trailingContinuations[line].indent
            } else {
                listPrefix = item.indent + item.marker + item.spacing + (item.taskMarker ?? "") + item.taskSpacing
            }
        } else { listPrefix = "" }
        if resolved.firstIndex != resolved.lastIndex {
            let opener: String
            if case .fencedCode = first.kind, let bodyStart = Self.codeBodyStart(in: first) {
                opener = (first.source as NSString).substring(to: bodyStart)
            } else { opener = "" }
            let closer: String
            if case .fencedCode = last.kind, let bodyStart = Self.codeBodyStart(in: last) {
                let codeEnd = bodyStart + (last.plainText as NSString).length
                closer = (last.source as NSString).substring(from: codeEnd)
            } else { closer = "" }
            if !opener.isEmpty || !closer.isEmpty { return opener + listPrefix + copied + closer }
        }
        return listPrefix + copied
    }

    /// Text-coordinate highlights for prose endpoints and complete intervening rows.
    /// Structured rows use the range's presence to tint the whole row; their
    /// plainText length is not a character-selection coordinate for an editor.
    public func semanticTextHighlightRanges(_ selection: MarkdownSemanticTextSelection) -> [String: NSRange]? {
        guard let resolved = resolveSemanticTextSelection(selection) else { return nil }
        let blocks = semanticDocument.blocks
        var result: [String: NSRange] = [:]
        for index in resolved.firstIndex...resolved.lastIndex {
            let block = blocks[index]
            if case .table = block.kind {
                result[block.id] = NSRange(location: 0, length: 1)
                continue
            }
            if case .list = block.kind {
                // List rows receive an item-level text tint from the companion
                // range map; this entry keeps complete/intervening rows tinted.
                result[block.id] = NSRange(location: 0, length: 1)
                continue
            }
            let length = (block.plainText as NSString).length
            let start = index == resolved.firstIndex ? resolved.startOffset : 0
            let end = index == resolved.lastIndex ? resolved.endOffset : length
            result[block.id] = NSRange(location: start, length: end - start)
        }
        return result
    }

    /// UTF-16 character tints for list item primary fields touched by a range.
    public func semanticListItemHighlightRanges(_ selection: MarkdownSemanticTextSelection)
        -> [String: [Int: NSRange]]? {
        semanticListLineHighlightRanges(selection)?.mapValues(\.primary)
    }

    struct ListLineHighlights {
        var primary: [Int: NSRange] = [:]
        var continuations: [Int: [Int: NSRange]] = [:]
        var trailing: [Int: [Int: NSRange]] = [:]
    }

    /// Map the source interval back onto physical list fields. Source offsets
    /// keep nested items and deferred continuations in their real order.
    func semanticListLineHighlightRanges(_ selection: MarkdownSemanticTextSelection)
        -> [String: ListLineHighlights]? {
        guard let resolved = resolveSemanticTextSelection(selection) else { return nil }
        let document = semanticDocument
        let blocks = document.blocks
        var result: [String: ListLineHighlights] = [:]
        for blockIndex in resolved.firstIndex...resolved.lastIndex {
            let block = blocks[blockIndex]
            guard case let .list(list) = block.kind,
                  let sourceRange = document.sourceRange(of: block.id) else { continue }
            let lower = blockIndex == resolved.firstIndex ? resolved.startSourceOffset : sourceRange.location
            let upper = blockIndex == resolved.lastIndex ? resolved.endSourceOffset : NSMaxRange(sourceRange)
            var lines = ListLineHighlights()
            func tint(_ line: (offset: Int, content: String)?) -> NSRange? {
                guard let line else { return nil }
                let start = sourceRange.location + line.offset
                let end = start + (line.content as NSString).length
                let from = max(lower, start)
                let to = min(upper, end)
                guard from < to else { return nil }
                return NSRange(location: from - start, length: to - from)
            }
            for index in list.items.indices {
                if let highlight = tint(list.sourceLine(at: index)) { lines.primary[index] = highlight }
                for continuation in list.items[index].continuations.indices {
                    if let highlight = tint(list.sourceLine(at: index, continuationIndex: continuation)) {
                        lines.continuations[index, default: [:]][continuation] = highlight
                    }
                }
                for trailing in list.items[index].trailingContinuations.indices {
                    if let highlight = tint(list.sourceLine(at: index, trailingIndex: trailing)) {
                        lines.trailing[index, default: [:]][trailing] = highlight
                    }
                }
            }
            result[block.id] = lines
        }
        return result
    }

    /// Character tints for simple quote rows touched by a semantic range.
    func semanticQuoteLineHighlightRanges(_ selection: MarkdownSemanticTextSelection)
        -> [String: [Int: NSRange]]? {
        guard let resolved = resolveSemanticTextSelection(selection),
              resolved.firstIndex == resolved.lastIndex else { return nil }
        let document = semanticDocument
        let block = document.blocks[resolved.firstIndex]
        guard let quote = MarkdownSourceQuote(source: block.source),
              let blockRange = document.sourceRange(of: block.id) else { return nil }
        var result: [Int: NSRange] = [:]
        for (index, line) in quote.lines.enumerated() {
            let start = blockRange.location + line.bodyOffset
            let lower = max(start, resolved.startSourceOffset)
            let upper = min(start + (line.content as NSString).length, resolved.endSourceOffset)
            if lower < upper { result[index] = NSRange(location: lower - start, length: upper - lower) }
        }
        return [block.id: result]
    }

    /// Character tints inside cells touched by a source-backed text range.
    /// Whole intermediary tables keep their existing row-level tint.
    public func semanticTableCellHighlightRanges(_ selection: MarkdownSemanticTextSelection)
        -> [String: [Int: [Int: NSRange]]]? {
        guard let resolved = resolveSemanticTextSelection(selection) else { return nil }
        let blocks = semanticDocument.blocks
        var result: [String: [Int: [Int: NSRange]]] = [:]
        for index in resolved.firstIndex...resolved.lastIndex {
            let block = blocks[index]
            guard case let .table(table) = block.kind else { continue }
            let startsHere = index == resolved.firstIndex && resolved.start.tableRow != nil
            let endsHere = index == resolved.lastIndex && resolved.end.tableRow != nil
            guard startsHere || endsHere else { continue }
            let row = startsHere ? resolved.start.tableRow! : resolved.end.tableRow!
            let column = startsHere ? resolved.start.tableColumn! : resolved.end.tableColumn!
            let raw = row == 0 ? table.headers[column] : table.rows[row - 1][column]
            let length = (Self.visibleTableCell(raw).text as NSString).length
            let lower = startsHere ? resolved.startOffset : 0
            let upper = endsHere ? resolved.endOffset : length
            result[block.id] = [row: [column: NSRange(location: lower, length: upper - lower)]]
        }
        return result
    }

    private func resolvedListItems(_ selection: MarkdownSemanticListItemSelection)
        -> (MarkdownSourceList, ClosedRange<Int>)? {
        guard let block = semanticDocument.blockById(selection.blockID),
              case let .list(list) = block.kind,
              list.items.indices.contains(selection.anchorIndex),
              list.items.indices.contains(selection.focusIndex),
              selection.anchorIndex != selection.focusIndex else { return nil }
        let range = min(selection.anchorIndex, selection.focusIndex)...max(selection.anchorIndex, selection.focusIndex)
        let indent = list.items[range.lowerBound].indent
        guard list.items[range].allSatisfy({ $0.indent == indent }) else { return nil }
        return (list, range)
    }

    public func copySemanticListItemRange(_ selection: MarkdownSemanticListItemSelection) -> String? {
        guard let (list, range) = resolvedListItems(selection) else { return nil }
        let source = list.items[range].map(\.source).joined()
        let indent = list.items[range.lowerBound].indent
        guard !indent.isEmpty else { return source }
        // Flutter serializes a selected nested list as a standalone list.
        // Remove only the shared structural indent and final row terminator;
        // retain relative child/continuation indentation and content bytes.
        var lines = source.components(separatedBy: "\n")
        if lines.last == "" {
            lines.removeLast()
            if source.hasSuffix("\r\n"), let last = lines.last, last.hasSuffix("\r") {
                lines[lines.count - 1] = String(last.dropLast())
            }
        }
        var copied: [String] = []
        for line in lines {
            guard line.hasPrefix(indent) || line.isEmpty || line == "\r" else { return nil }
            copied.append(line.hasPrefix(indent) ? String(line.dropFirst(indent.count)) : line)
        }
        return copied.joined(separator: "\n")
    }

    private func deletedListItemMarkdown(_ selection: MarkdownSemanticListItemSelection) -> String? {
        guard let (_, range) = resolvedListItems(selection) else { return nil }
        let document = semanticDocument
        guard let updated = document.updatingList(selection.blockID, {
            $0.removingSiblingItems(from: range.lowerBound, to: range.upperBound)
        })?.toMarkdown(), updated != text else { return nil }
        let reparsed = codec.parse(updated)
        guard reparsed.toMarkdown() == updated, reparsed.blocks.count == document.blocks.count,
              zip(reparsed.blocks, document.blocks).allSatisfy({ next, old in
                  if old.id == selection.blockID {
                      if case .list = next.kind {
                          return next.id == old.id && next.leadingTrivia == old.leadingTrivia
                      }
                      return false
                  }
                  return next.id == old.id && next.kind == old.kind && next.source == old.source &&
                      next.leadingTrivia == old.leadingTrivia
              }) else { return nil }
        return updated
    }

    public func canDeleteSemanticListItemRange(_ selection: MarkdownSemanticListItemSelection) -> Bool {
        deletedListItemMarkdown(selection) != nil
    }

    @discardableResult
    public func deleteSemanticListItemRange(_ selection: MarkdownSemanticListItemSelection) -> Bool {
        guard let updated = deletedListItemMarkdown(selection) else { return false }
        return replaceSemanticMarkdown(updated)
    }

    /// Marks the primary text line of each selected sibling item. The list's
    /// markers, continuation lines, and neighboring blocks retain their source.
    @discardableResult
    public func applySemanticInlineMarkToListItemRange(_ selection: MarkdownSemanticListItemSelection,
                                                       mark: MarkdownInlineMark) -> Bool {
        guard let (_, range) = resolvedListItems(selection) else { return false }
        let document = semanticDocument
        guard let updated = document.updatingList(selection.blockID, { list in
            var next = list
            var changed = false
            for index in range {
                let content = next.items[index].content
                let length = (content as NSString).length
                if length == 0 { continue }
                guard let edit = MarkdownInlineMarkEditor.applyVerifiedRange(mark, to: content,
                                                                             selection: NSRange(location: 0, length: length)),
                      let replaced = next.replacingItemContent(at: index, with: edit.markdown) else { return nil }
                next = replaced
                changed = true
            }
            return changed ? next : nil
        })?.toMarkdown() else { return false }
        return replaceSemanticMarkdown(updated)
    }

    private func resolvedTableCells(_ selection: MarkdownSemanticTableCellSelection)
        -> (MarkdownSourceTable, ClosedRange<Int>, ClosedRange<Int>)? {
        guard let block = semanticDocument.blockById(selection.blockID),
              case let .table(table) = block.kind else { return nil }
        let rows = min(selection.anchorRow, selection.focusRow)...max(selection.anchorRow, selection.focusRow)
        let columns = min(selection.anchorColumn, selection.focusColumn)...max(selection.anchorColumn, selection.focusColumn)
        guard rows.lowerBound >= 0, rows.upperBound <= table.rows.count,
              columns.lowerBound >= 0, columns.upperBound < table.columnCount,
              rows.count * columns.count > 1 else { return nil }
        return (table, rows, columns)
    }

    public func semanticTableCellRectangle(_ selection: MarkdownSemanticTableCellSelection)
        -> (rows: ClosedRange<Int>, columns: ClosedRange<Int>)? {
        guard let (_, rows, columns) = resolvedTableCells(selection) else { return nil }
        return (rows, columns)
    }

    public func copySemanticTableCellsAsTSV(_ selection: MarkdownSemanticTableCellSelection) -> String? {
        guard let (table, rows, columns) = resolvedTableCells(selection) else { return nil }
        return rows.map { row in
            columns.map { column in
                let source = row == 0 ? table.headers[column] : table.rows[row - 1][column]
                return source.replacingOccurrences(of: "\\|", with: "|")
            }.joined(separator: "\t")
        }.joined(separator: "\n")
    }

    /// Pastes a rectangular TSV selection into an existing table without
    /// changing its shape or rewriting untouched source lines. Row zero is the
    /// header. A mismatch rejects the entire paste.
    @discardableResult
    public func pasteSemanticTableCells(_ clipboard: String,
                                        into selection: MarkdownSemanticTableCellSelection) -> Bool {
        guard let (_, rows, columns) = resolvedTableCells(selection),
              let grid = Self.tablePasteGrid(clipboard),
              grid.count == rows.count, grid[0].count == columns.count else { return false }
        return pasteTableGrid(grid, blockID: selection.blockID,
                              startRow: rows.lowerBound, startColumn: columns.lowerBound)
    }

    /// Handles a multiline or tabular paste that starts in one focused cell.
    /// Ordinary single-line text remains on the native UITextField path.
    @discardableResult
    public func pasteTableCells(_ clipboard: String, inTable blockID: String,
                                row: Int, column: Int) -> Bool {
        guard let grid = Self.tablePasteGrid(clipboard) else { return false }
        return pasteTableGrid(grid, blockID: blockID, startRow: row, startColumn: column)
    }

    /// Newline-only prose is ambiguous in one focused cell and stays in Source
    /// mode. A tab is an explicit grid delimiter, but replacing a whole cell
    /// is safe only when all its visible text is selected (including an empty
    /// cell at caret zero). Any partial caret/selection uses exact source paste.
    static func shouldRouteFocusedTablePasteAsGrid(_ clipboard: String,
                                                   visibleText: String,
                                                   selection: NSRange) -> Bool {
        let wholeCell = selection.location == 0 && selection.length == (visibleText as NSString).length
        return clipboard.contains("\t") && wholeCell
    }

    /// Preserves the exact pasted bytes when a focused-cell paste is not a
    /// representable grid. Switch to Source because a newline may split the
    /// table. If the displayed cell no longer matches its source, decline the
    /// edit so the UI can show an error instead of silently dropping text.
    @discardableResult
    public func pasteIntoTableCellSource(_ clipboard: String, inTable blockID: String,
                                         row: Int, column: Int, visibleText: String,
                                         visibleRange: NSRange) -> Bool {
        let document = semanticDocument
        guard let cellRange = document.sourceRangeOfTableCell(blockID: blockID, row: row, column: column),
              Range(visibleRange, in: visibleText) != nil,
              (text as NSString).substring(with: cellRange) == visibleText else { return false }
        replaceRange(NSRange(location: cellRange.location + visibleRange.location,
                             length: visibleRange.length), with: clipboard)
        mode = .source
        return true
    }

    private static func tablePasteGrid(_ clipboard: String) -> [[String]]? {
        guard clipboard.utf8.count <= 1_048_576,
              clipboard.contains("\t") || clipboard.contains("\n") || clipboard.contains("\r") else { return nil }
        let normalized = clipboard.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var lines = normalized.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        guard !lines.isEmpty, lines.count <= 1_000 else { return nil }
        let grid = lines.map { $0.components(separatedBy: "\t") }
        guard let width = grid.first?.count, width > 0,
              lines.count > 1 || width > 1,
              grid.allSatisfy({ $0.count == width }),
              lines.count <= 1_000 / width else { return nil }
        return grid
    }

    private func pasteTableGrid(_ grid: [[String]], blockID: String,
                                startRow: Int, startColumn: Int) -> Bool {
        guard let block = semanticDocument.blockById(blockID),
              case let .table(table) = block.kind,
              startRow >= 0, startColumn >= 0,
              grid.count <= table.rows.count + 1 - startRow,
              grid[0].count <= table.columnCount - startColumn else { return false }
        let document = semanticDocument
        guard let updated = document.updatingTable(blockID, preservingSource: true, { table in
            var next = table
            for (rowOffset, cells) in grid.enumerated() {
                for (columnOffset, value) in cells.enumerated() {
                    next = next.replacingCell(rowIndex: startRow + rowOffset - 1,
                                              columnIndex: startColumn + columnOffset,
                                              text: value, header: startRow + rowOffset == 0)
                }
            }
            return next
        })?.toMarkdown() else { return false }
        return replaceSemanticMarkdown(updated)
    }

    private func clearedTableCellsMarkdown(_ selection: MarkdownSemanticTableCellSelection) -> String? {
        guard let (_, rows, columns) = resolvedTableCells(selection) else { return nil }
        return semanticDocument.updatingTable(selection.blockID, preservingSource: true) { table in
            var result = table
            for row in rows {
                for column in columns {
                    if row == 0 { result.headers[column] = "" }
                    else { result.rows[row - 1][column] = "" }
                }
            }
            return result
        }?.toMarkdown()
    }

    public func canClearSemanticTableCells(_ selection: MarkdownSemanticTableCellSelection) -> Bool {
        clearedTableCellsMarkdown(selection) != nil
    }

    @discardableResult
    public func clearSemanticTableCells(_ selection: MarkdownSemanticTableCellSelection) -> Bool {
        guard let updated = clearedTableCellsMarkdown(selection) else { return false }
        return replaceSemanticMarkdown(updated)
    }

    /// Applies Flutter's basic table range marks to each non-empty cell. A
    /// source-preserving table edit must succeed for the entire rectangle.
    @discardableResult
    public func applySemanticInlineMarkToTableCells(_ selection: MarkdownSemanticTableCellSelection,
                                                     mark: MarkdownInlineMark) -> Bool {
        if case .link = mark { return false }
        guard let (_, rows, columns) = resolvedTableCells(selection) else { return false }
        let document = semanticDocument
        var valid = true
        var changed = false
        let updated = document.updatingTable(selection.blockID, preservingSource: true) { table in
            var next = table
            for row in rows {
                for column in columns {
                    let content = row == 0 ? next.headers[column] : next.rows[row - 1][column]
                    let length = (content as NSString).length
                    if length == 0 { continue }
                    guard let edit = MarkdownInlineMarkEditor.applyVerifiedRange(mark, to: content,
                                                                                 selection: NSRange(location: 0, length: length)) else {
                        valid = false
                        return table
                    }
                    if row == 0 { next.headers[column] = edit.markdown }
                    else { next.rows[row - 1][column] = edit.markdown }
                    changed = true
                }
            }
            return next
        }?.toMarkdown()
        guard valid, changed, let updated else { return false }
        return replaceSemanticMarkdown(updated)
    }

    private func isHeading(_ block: MarkdownDocumentBlock) -> Bool {
        if case .heading = block.kind { return true }
        return false
    }

    /// Reports whether a cross-block character replacement is source safe.
    public func canReplaceSemanticTextRange(_ selection: MarkdownSemanticTextSelection,
                                             with replacement: String = "") -> Bool {
        replacementForSemanticTextRange(selection, with: replacement) != nil
    }

    /// Replaces a character range spanning paragraph/heading rows as one undo step.
    /// The start row retains its style. Intervening rows are removed, and untouched
    /// source before and after the range is preserved exactly.
    @discardableResult
    public func replaceSemanticTextRange(_ selection: MarkdownSemanticTextSelection,
                                         with replacement: String) -> Bool {
        guard let edit = replacementForSemanticTextRange(selection, with: replacement) else { return false }
        let changed = replaceSemanticMarkdown(edit.markdown)
        if changed { setSelection(NSRange(location: edit.caret, length: 0)) }
        return changed
    }

    @discardableResult
    public func deleteSemanticTextRange(_ selection: MarkdownSemanticTextSelection) -> Bool {
        replaceSemanticTextRange(selection, with: "")
    }

    private struct ResolvedVisibleTextSelection {
        let document: MarkdownDocument
        let firstIndex: Int
        let lastIndex: Int
        let startOffset: Int
        let endOffset: Int
        let firstVisible: String
        let lastVisible: String
        let startBoundary: MarkdownInlineMarkEditor.VisibleBoundary
        let endBoundary: MarkdownInlineMarkEditor.VisibleBoundary
    }

    private func resolveVisibleTextSelection(_ selection: MarkdownVisibleTextSelection)
        -> ResolvedVisibleTextSelection? {
        guard selection.source == text else { return nil }
        let document = semanticDocument
        guard let anchorIndex = document.blocks.firstIndex(where: { $0.id == selection.anchor.blockID }),
              let focusIndex = document.blocks.firstIndex(where: { $0.id == selection.focus.blockID }) else { return nil }
        let forward = anchorIndex < focusIndex ||
            (anchorIndex == focusIndex && selection.anchor.offset <= selection.focus.offset)
        let firstIndex = min(anchorIndex, focusIndex)
        let lastIndex = max(anchorIndex, focusIndex)
        let startOffset = forward ? selection.anchor.offset : selection.focus.offset
        let endOffset = forward ? selection.focus.offset : selection.anchor.offset
        guard firstIndex != lastIndex || startOffset < endOffset else { return nil }
        for block in document.blocks[firstIndex...lastIndex] {
            switch block.kind {
            case .paragraph, .heading: break
            case .fencedCode, .table, .list, .horizontalRule, .plugin, .raw: return nil
            }
            guard MarkdownInlineMarkEditor.visibleText(of: block.plainText) != nil else { return nil }
        }
        let first = document.blocks[firstIndex]
        let last = document.blocks[lastIndex]
        guard let firstVisible = MarkdownInlineMarkEditor.visibleText(of: first.plainText),
              let lastVisible = MarkdownInlineMarkEditor.visibleText(of: last.plainText),
              startOffset >= 0, startOffset <= (firstVisible as NSString).length,
              endOffset >= 0, endOffset <= (lastVisible as NSString).length,
              Range(NSRange(location: startOffset, length: 0), in: firstVisible) != nil,
              Range(NSRange(location: endOffset, length: 0), in: lastVisible) != nil,
              let startBoundary = MarkdownInlineMarkEditor.visibleBoundary(in: first.plainText, at: startOffset),
              let endBoundary = MarkdownInlineMarkEditor.visibleBoundary(in: last.plainText, at: endOffset),
              firstIndex != lastIndex || startBoundary.sourceOffset <= endBoundary.sourceOffset else { return nil }
        return .init(document: document, firstIndex: firstIndex, lastIndex: lastIndex,
                     startOffset: startOffset, endOffset: endOffset,
                     firstVisible: firstVisible, lastVisible: lastVisible,
                     startBoundary: startBoundary, endBoundary: endBoundary)
    }

    /// Copies a rendered-text selection as balanced Markdown, including the
    /// exact source whitespace between its top-level paragraph/heading rows.
    public func copyVisibleTextRange(_ selection: MarkdownVisibleTextSelection) -> String? {
        guard let resolved = resolveVisibleTextSelection(selection) else { return nil }
        let first = resolved.document.blocks[resolved.firstIndex]
        let last = resolved.document.blocks[resolved.lastIndex]
        let firstLength = (resolved.firstVisible as NSString).length
        guard MarkdownInlineMarkEditor.copyVisibleRange(
            in: first.plainText,
            range: NSRange(location: resolved.startOffset,
                           length: (resolved.firstIndex == resolved.lastIndex ? resolved.endOffset : firstLength)
                               - resolved.startOffset)) != nil else { return nil }
        if resolved.firstIndex != resolved.lastIndex {
            guard MarkdownInlineMarkEditor.copyVisibleRange(
                in: last.plainText, range: NSRange(location: 0, length: resolved.endOffset)) != nil else { return nil }
        }
        guard let firstRange = resolved.document.sourceRange(of: first.id),
              let lastRange = resolved.document.sourceRange(of: last.id),
              let firstBodyStart = Self.editableBodyStart(in: first),
              let lastBodyStart = Self.editableBodyStart(in: last) else { return nil }
        let sourceStart = resolved.startOffset == 0 && isHeading(first) ? firstRange.location :
            firstRange.location + firstBodyStart + resolved.startBoundary.sourceOffset
        let sourceEnd = resolved.endOffset == 0 && isHeading(last) && resolved.firstIndex != resolved.lastIndex ?
            lastRange.location : lastRange.location + lastBodyStart + resolved.endBoundary.sourceOffset
        guard sourceStart <= sourceEnd else { return nil }
        return resolved.startBoundary.openTokens
            + (text as NSString).substring(with: NSRange(location: sourceStart, length: sourceEnd - sourceStart))
            + resolved.endBoundary.closeTokens
    }

    public func canReplaceVisibleTextRange(_ selection: MarkdownVisibleTextSelection,
                                           with replacement: String = "") -> Bool {
        replacementForVisibleTextRange(selection, with: replacement) != nil
    }

    /// Replaces rendered UTF-16 text in one or several adjacent prose rows as
    /// one undo step. The first row keeps its paragraph or heading style.
    /// The replacement must render as the supplied single-line plain text;
    /// multiline and structured Markdown paste belongs in Source mode.
    @discardableResult
    public func replaceVisibleTextRange(_ selection: MarkdownVisibleTextSelection,
                                        with replacement: String) -> Bool {
        guard let edit = replacementForVisibleTextRange(selection, with: replacement),
              replaceSemanticMarkdown(edit.markdown) else { return false }
        setSelection(NSRange(location: edit.caret, length: 0))
        return true
    }

    @discardableResult
    public func deleteVisibleTextRange(_ selection: MarkdownVisibleTextSelection) -> Bool {
        replaceVisibleTextRange(selection, with: "")
    }

    private static func editableBodyStart(in block: MarkdownDocumentBlock) -> Int? {
        let source = block.source as NSString
        let body = block.plainText as NSString
        let ending = block.source.hasSuffix("\r\n") ? 2 : block.source.hasSuffix("\n") ? 1 : 0
        let offset = source.length - body.length - ending
        guard offset >= 0, source.substring(with: NSRange(location: offset, length: body.length)) == block.plainText
        else { return nil }
        return offset
    }

    private func replacementForVisibleTextRange(_ selection: MarkdownVisibleTextSelection,
                                                with replacement: String) -> (markdown: String, caret: Int)? {
        guard let resolved = resolveVisibleTextSelection(selection),
              !replacement.contains("\n"), !replacement.contains("\r") else { return nil }
        let first = resolved.document.blocks[resolved.firstIndex]
        let last = resolved.document.blocks[resolved.lastIndex]
        guard let firstRange = resolved.document.sourceRange(of: first.id),
              let lastRange = resolved.document.sourceRange(of: last.id),
              let firstBodyStart = Self.editableBodyStart(in: first),
              let lastBodyStart = Self.editableBodyStart(in: last),
              let firstStyles = MarkdownInlineMarkEditor.visibleStyles(of: first.plainText),
              let lastStyles = MarkdownInlineMarkEditor.visibleStyles(of: last.plainText) else { return nil }
        let start = firstRange.location + firstBodyStart + resolved.startBoundary.sourceOffset
        let end = lastRange.location + lastBodyStart + resolved.endBoundary.sourceOffset
        guard start <= end else { return nil }
        let firstVisible = resolved.firstVisible as NSString
        let lastVisible = resolved.lastVisible as NSString
        let expectedVisible = firstVisible.substring(to: resolved.startOffset)
            + replacement + lastVisible.substring(from: resolved.endOffset)
        let expectedPrefixStyles = Array(firstStyles[..<resolved.startOffset])
        let expectedSuffixStyles = Array(lastStyles[resolved.endOffset...])
        let source = text as NSString
        let range = NSRange(location: start, length: end - start)
        let repairs = [("", ""),
                       (resolved.startBoundary.closeTokens, resolved.endBoundary.openTokens)]
        for (closing, opening) in repairs {
            let inserted = closing + replacement + opening
            let next = source.replacingCharacters(in: range, with: inserted)
            guard next != text else { continue }
            let parsed = codec.parse(next)
            let expectedCount = resolved.document.blocks.count - (resolved.lastIndex - resolved.firstIndex)
            guard parsed.toMarkdown() == next, parsed.blocks.count == expectedCount,
                  parsed.trailingTrivia == resolved.document.trailingTrivia else { continue }
            let merged = parsed.blocks[resolved.firstIndex]
            guard merged.leadingTrivia == first.leadingTrivia else { continue }
            switch (first.kind, merged.kind) {
            case (.paragraph, .paragraph): break
            case let (.heading(oldLevel, _), .heading(newLevel, _)) where oldLevel == newLevel: break
            default: continue
            }
            guard MarkdownInlineMarkEditor.visibleText(of: merged.plainText) == expectedVisible,
                  let styles = MarkdownInlineMarkEditor.visibleStyles(of: merged.plainText),
                  styles.count == (expectedVisible as NSString).length,
                  Array(styles.prefix(expectedPrefixStyles.count)) == expectedPrefixStyles,
                  Array(styles.suffix(expectedSuffixStyles.count)) == expectedSuffixStyles else { continue }
            let before = zip(parsed.blocks[..<resolved.firstIndex],
                             resolved.document.blocks[..<resolved.firstIndex]).allSatisfy(Self.sameSourceBlock)
            let after = zip(parsed.blocks[(resolved.firstIndex + 1)...],
                            resolved.document.blocks[(resolved.lastIndex + 1)...]).allSatisfy(Self.sameSourceBlock)
            guard before, after else { continue }
            return (next, start + (inserted as NSString).length)
        }
        return nil
    }

    /// Whole structured rows may be copied or deleted with the range, but only
    /// paragraph and heading text can receive an inline mark.
    public func canApplySemanticInlineMarkToTextRange(_ selection: MarkdownSemanticTextSelection) -> Bool {
        guard let resolved = resolveSemanticTextSelection(selection) else { return false }
        return semanticDocument.blocks[resolved.firstIndex...resolved.lastIndex].allSatisfy { block in
            switch block.kind {
            case .paragraph, .heading: return true
            case .fencedCode, .table, .list, .horizontalRule, .plugin, .raw: return false
            }
        }
    }

    /// Applies one mark to the selected character fragment in each adjacent
    /// paragraph or heading. Each row retains its marker, trivia, and ending.
    @discardableResult
    public func applySemanticInlineMarkToTextRange(_ selection: MarkdownSemanticTextSelection,
                                                    mark: MarkdownInlineMark) -> Bool {
        guard canApplySemanticInlineMarkToTextRange(selection),
              let resolved = resolveSemanticTextSelection(selection) else { return false }
        let document = semanticDocument
        var nextBlocks = document.blocks
        var changed = false
        for index in resolved.firstIndex...resolved.lastIndex {
            let block = nextBlocks[index]
            let body = block.plainText
            let start = index == resolved.firstIndex ? resolved.startOffset : 0
            let end = index == resolved.lastIndex ? resolved.endOffset : (body as NSString).length
            if start == end { continue }
            guard let edit = MarkdownInlineMarkEditor.applyVerifiedRange(mark, to: body,
                                                                         selection: NSRange(location: start, length: end - start)),
                  let replacement = block.replacingContent(edit.markdown) else { return false }
            nextBlocks[index] = replacement
            changed = true
        }
        guard changed else { return false }
        let updated = MarkdownDocument(blocks: nextBlocks, trailingTrivia: document.trailingTrivia).toMarkdown()
        let reparsed = codec.parse(updated)
        guard reparsed.toMarkdown() == updated, reparsed.blocks.count == nextBlocks.count,
              zip(reparsed.blocks, nextBlocks).allSatisfy({ parsed, proposed in
                  parsed.id == proposed.id && parsed.kind == proposed.kind &&
                      parsed.source == proposed.source && parsed.leadingTrivia == proposed.leadingTrivia
              }) else { return false }
        return replaceSemanticMarkdown(updated)
    }

    /// Applies one mark to rendered UTF-16 text in adjacent paragraphs/headings.
    /// Existing Markdown marks and source outside the selection remain intact;
    /// an unsafe candidate leaves the document and undo history untouched.
    @discardableResult
    public func applySemanticInlineMarkToVisibleTextRange(_ selection: MarkdownVisibleTextSelection,
                                                           mark: MarkdownInlineMark) -> Bool {
        guard selection.source == text else { return false }
        let document = semanticDocument
        guard let anchorIndex = document.blocks.firstIndex(where: { $0.id == selection.anchor.blockID }),
              let focusIndex = document.blocks.firstIndex(where: { $0.id == selection.focus.blockID }) else { return false }
        let firstIndex = min(anchorIndex, focusIndex)
        let lastIndex = max(anchorIndex, focusIndex)
        let forward = anchorIndex < focusIndex ||
            (anchorIndex == focusIndex && selection.anchor.offset <= selection.focus.offset)
        let startOffset = forward ? selection.anchor.offset : selection.focus.offset
        let endOffset = forward ? selection.focus.offset : selection.anchor.offset
        guard firstIndex != lastIndex || startOffset < endOffset else { return false }

        var nextBlocks = document.blocks
        var changed = false
        for index in firstIndex...lastIndex {
            let block = nextBlocks[index]
            switch block.kind {
            case .paragraph, .heading: break
            case .fencedCode, .table, .list, .horizontalRule, .plugin, .raw: return false
            }
            guard let visibleLength = MarkdownInlineMarkEditor.visibleUTF16Length(of: block.plainText) else { return false }
            let start = index == firstIndex ? startOffset : 0
            let end = index == lastIndex ? endOffset : visibleLength
            guard start >= 0, end >= start, end <= visibleLength else { return false }
            if start == end { continue }
            guard let markdown = MarkdownInlineMarkEditor.applyVerifiedVisibleRange(
                mark, to: block.plainText, selection: NSRange(location: start, length: end - start)),
                  let replacement = block.replacingContent(markdown) else { return false }
            nextBlocks[index] = replacement
            changed = true
        }
        guard changed else { return false }
        let updated = MarkdownDocument(blocks: nextBlocks, trailingTrivia: document.trailingTrivia).toMarkdown()
        let reparsed = codec.parse(updated)
        guard reparsed.toMarkdown() == updated, reparsed.blocks.count == nextBlocks.count,
              zip(reparsed.blocks, nextBlocks).allSatisfy({ parsed, proposed in
                  parsed.id == proposed.id && parsed.kind == proposed.kind &&
                      parsed.source == proposed.source && parsed.leadingTrivia == proposed.leadingTrivia
              }) else { return false }
        return replaceSemanticMarkdown(updated)
    }

    private func resolveSemanticTextSelection(_ selection: MarkdownSemanticTextSelection)
        -> ResolvedSemanticTextSelection? {
        guard selection.source == nil || selection.source == text else { return nil }
        let document = semanticDocument
        guard let anchorIndex = document.blocks.firstIndex(where: { $0.id == selection.anchor.blockID }),
              let focusIndex = document.blocks.firstIndex(where: { $0.id == selection.focus.blockID }) else { return nil }
        let firstIndex = min(anchorIndex, focusIndex)
        let lastIndex = max(anchorIndex, focusIndex)
        func sourceOffset(_ position: MarkdownSemanticTextPosition) -> Int? {
            guard let block = document.blockById(position.blockID),
                  let range = document.sourceRange(of: position.blockID) else { return nil }
            let bodyStart: Int
            let body: String
            switch block.kind {
            case .paragraph, .heading:
                guard position.listItemIndex == nil, position.listContinuationIndex == nil,
                      position.listTrailingIndex == nil, position.tableRow == nil,
                      position.tableColumn == nil, position.quoteLineIndex == nil else { return nil }
                body = block.plainText
                let ending = block.source.hasSuffix("\r\n") ? 2 : block.source.hasSuffix("\n") ? 1 : 0
                bodyStart = (block.source as NSString).length - (body as NSString).length - ending
            case let .list(list):
                guard position.tableRow == nil, position.tableColumn == nil,
                      position.quoteLineIndex == nil,
                      let index = position.listItemIndex, list.items.indices.contains(index),
                      position.listContinuationIndex == nil || position.listTrailingIndex == nil,
                      let line = list.sourceLine(at: index,
                          continuationIndex: position.listContinuationIndex,
                          trailingIndex: position.listTrailingIndex) else { return nil }
                body = line.content
                bodyStart = line.offset
            case .fencedCode:
                guard position.listItemIndex == nil, position.listContinuationIndex == nil,
                      position.listTrailingIndex == nil, position.tableRow == nil,
                      position.tableColumn == nil, position.quoteLineIndex == nil,
                      let codeStart = Self.codeBodyStart(in: block) else { return nil }
                body = block.plainText
                bodyStart = codeStart
            case let .table(table):
                guard position.listItemIndex == nil, position.listContinuationIndex == nil,
                      position.listTrailingIndex == nil, position.quoteLineIndex == nil,
                      let row = position.tableRow, let column = position.tableColumn,
                      row >= 0, row <= table.rows.count,
                      table.headers.indices.contains(column),
                      let cellRange = document.sourceRangeOfTableCell(blockID: position.blockID,
                                                                      row: row, column: column) else { return nil }
                let raw = row == 0 ? table.headers[column] : table.rows[row - 1][column]
                let mapped = Self.visibleTableCell(raw)
                guard position.offset >= 0, position.offset < mapped.boundaries.count,
                      Range(NSRange(location: position.offset, length: 0), in: mapped.text) != nil else { return nil }
                let absolute = cellRange.location + mapped.boundaries[position.offset]
                guard isValidSourceRange(NSRange(location: absolute, length: 0)) else { return nil }
                return absolute
            case .raw:
                guard position.listItemIndex == nil, position.listContinuationIndex == nil,
                      position.listTrailingIndex == nil, position.tableRow == nil,
                      position.tableColumn == nil,
                      let index = position.quoteLineIndex,
                      let quote = MarkdownSourceQuote(source: block.source),
                      quote.lines.indices.contains(index) else { return nil }
                body = quote.lines[index].content
                bodyStart = quote.lines[index].bodyOffset
            case .horizontalRule, .plugin: return nil
            }
            guard position.offset >= 0, position.offset <= (body as NSString).length,
                  Range(NSRange(location: position.offset, length: 0), in: body) != nil,
                  bodyStart >= 0,
                  bodyStart + (body as NSString).length <= (block.source as NSString).length,
                  (block.source as NSString).substring(with: NSRange(location: bodyStart,
                                                                     length: (body as NSString).length)) == body else { return nil }
            let absolute = range.location + bodyStart + position.offset
            guard isValidSourceRange(NSRange(location: absolute, length: 0)) else { return nil }
            return absolute
        }
        guard let anchorSourceOffset = sourceOffset(selection.anchor),
              let focusSourceOffset = sourceOffset(selection.focus) else { return nil }
        let forward = anchorSourceOffset <= focusSourceOffset
        let start = forward ? selection.anchor : selection.focus
        let end = forward ? selection.focus : selection.anchor
        let startSourceOffset = forward ? anchorSourceOffset : focusSourceOffset
        let endSourceOffset = forward ? focusSourceOffset : anchorSourceOffset
        if start.quoteLineIndex != nil || end.quoteLineIndex != nil {
            guard firstIndex == lastIndex,
                  start.quoteLineIndex != nil,
                  end.quoteLineIndex != nil else { return nil }
        }
        let sameCodeBlock: Bool
        if firstIndex == lastIndex, case .fencedCode = document.blocks[firstIndex].kind {
            sameCodeBlock = true
        } else { sameCodeBlock = false }
        let sameTableCell = firstIndex == lastIndex && start.tableRow != nil &&
            start.tableRow == end.tableRow && start.tableColumn == end.tableColumn
        let sameQuote = firstIndex == lastIndex && start.quoteLineIndex != nil && end.quoteLineIndex != nil
        guard (firstIndex != lastIndex || start.listItemIndex != nil || sameCodeBlock || sameTableCell || sameQuote),
              startSourceOffset < endSourceOffset else { return nil }
        return .init(firstIndex: firstIndex, lastIndex: lastIndex,
                     start: start, end: end,
                     startOffset: start.offset, endOffset: end.offset,
                     startSourceOffset: startSourceOffset, endSourceOffset: endSourceOffset)
    }

    private func replacementForSemanticTextRange(_ selection: MarkdownSemanticTextSelection,
                                                  with replacement: String) -> (markdown: String, caret: Int)? {
        guard let resolved = resolveSemanticTextSelection(selection) else { return nil }
        let original = semanticDocument
        let first = original.blocks[resolved.firstIndex]
        let last = original.blocks[resolved.lastIndex]
        if resolved.start.quoteLineIndex != nil || resolved.end.quoteLineIndex != nil {
            return replacementForQuoteEndpointRange(resolved, with: replacement, document: original)
        }
        if case .list = first.kind, resolved.firstIndex == resolved.lastIndex,
           resolved.start.listItemIndex == resolved.end.listItemIndex,
           resolved.start.listContinuationIndex == resolved.end.listContinuationIndex,
           resolved.start.listTrailingIndex == resolved.end.listTrailingIndex {
            return replacementForOneListLine(resolved, with: replacement, document: original)
        }
        if case .table = first.kind {
            return replacementForTableEndpointRange(resolved, with: replacement, document: original)
        }
        if case .table = last.kind {
            return replacementForTableEndpointRange(resolved, with: replacement, document: original)
        }
        if case .fencedCode = first.kind {
            return replacementForCodeEndpointRange(resolved, with: replacement, document: original)
        }
        if case .fencedCode = last.kind {
            return replacementForCodeEndpointRange(resolved, with: replacement, document: original)
        }
        // Cross-line list edits currently have merge semantics only for flat
        // primary lines. Other list lines remain copyable, but mutating them
        // across a structural boundary would require moving child ownership.
        for block in original.blocks[resolved.firstIndex...resolved.lastIndex] {
            if case let .list(list) = block.kind {
                guard let root = list.items.first,
                      list.items.allSatisfy({ $0.indent == root.indent &&
                          $0.continuations.isEmpty && $0.trailingContinuations.isEmpty }) else { return nil }
            }
        }
        if resolved.start.listItemIndex != nil || resolved.end.listItemIndex != nil {
            guard !replacement.contains("\n"), !replacement.contains("\r") else { return nil }
        }
        let source = text as NSString
        let replacementRange = NSRange(location: resolved.startSourceOffset,
                                       length: resolved.endSourceOffset - resolved.startSourceOffset)
        let next = source.replacingCharacters(in: replacementRange, with: replacement)
        guard next != text else { return nil }
        let parsed = codec.parse(next)
        let expectedCount = original.blocks.count - (resolved.lastIndex - resolved.firstIndex)
        guard parsed.toMarkdown() == next, parsed.blocks.count == expectedCount else { return nil }
        for index in 0..<resolved.firstIndex {
            guard parsed.blocks[index].kind == original.blocks[index].kind,
                  parsed.blocks[index].source == original.blocks[index].source,
                  parsed.blocks[index].leadingTrivia == original.blocks[index].leadingTrivia else { return nil }
        }
        let merged = parsed.blocks[resolved.firstIndex]
        guard merged.leadingTrivia == first.leadingTrivia else { return nil }
        switch (first.kind, merged.kind) {
        case (.paragraph, .paragraph): break
        case let (.heading(oldLevel, _), .heading(newLevel, _)) where oldLevel == newLevel: break
        case (.list, .list): break
        default: return nil
        }
        if let index = resolved.start.listItemIndex, case let .list(oldList) = first.kind,
           case let .list(newList) = merged.kind {
            guard newList.items.indices.contains(index),
                  Array(newList.items[..<index]) == Array(oldList.items[..<index]) else { return nil }
            let startBody = oldList.items[index].content as NSString
            let oldItem = oldList.items[index]
            let newItem = newList.items[index]
            guard newItem.indent == oldItem.indent, newItem.marker == oldItem.marker,
                  newItem.spacing == oldItem.spacing, newItem.taskMarker == oldItem.taskMarker,
                  newItem.taskSpacing == oldItem.taskSpacing else { return nil }
            let endBody: String
            if let endIndex = resolved.end.listItemIndex, case let .list(endList) = last.kind {
                endBody = endList.items[endIndex].content
                let tail = Array(endList.items.dropFirst(endIndex + 1))
                guard newList.items.count == index + 1 + tail.count,
                      Array(newList.items.suffix(tail.count)) == tail else { return nil }
            } else {
                endBody = last.plainText
                guard newList.items.count == index + 1 else { return nil }
            }
            let expected = startBody.substring(to: resolved.startOffset) + replacement +
                (endBody as NSString).substring(from: resolved.endOffset)
            guard newList.items[index].content == expected else { return nil }
        } else if let endIndex = resolved.end.listItemIndex,
                  case let .list(endList) = last.kind {
            // A prose prefix can absorb only the final root item. Otherwise
            // untouched following items would become an ambiguous new block.
            guard endIndex == endList.items.count - 1 else { return nil }
            let startBody = first.plainText as NSString
            let endBody = endList.items[endIndex].content as NSString
            let expected = startBody.substring(to: resolved.startOffset) + replacement +
                endBody.substring(from: resolved.endOffset)
            guard merged.plainText == expected else { return nil }
        }
        for oldIndex in (resolved.lastIndex + 1)..<original.blocks.count {
            let newIndex = oldIndex - (resolved.lastIndex - resolved.firstIndex)
            guard parsed.blocks[newIndex].kind == original.blocks[oldIndex].kind,
                  parsed.blocks[newIndex].source == original.blocks[oldIndex].source,
                  parsed.blocks[newIndex].leadingTrivia == original.blocks[oldIndex].leadingTrivia else { return nil }
        }
        guard parsed.trailingTrivia == original.trailingTrivia else { return nil }
        return (next, resolved.startSourceOffset + (replacement as NSString).length)
    }

    /// Edit exactly one physical list field. Reparse and compare the complete
    /// source-backed list so a changed marker, item boundary, blank-line owner,
    /// or nested subtree cannot silently move while editing a character range.
    private func replacementForOneListLine(_ resolved: ResolvedSemanticTextSelection,
                                           with replacement: String, document: MarkdownDocument)
        -> (markdown: String, caret: Int)? {
        guard !replacement.contains("\n"), !replacement.contains("\r"),
              let index = resolved.start.listItemIndex,
              case let .list(list) = document.blocks[resolved.firstIndex].kind,
              let line = list.sourceLine(at: index,
                  continuationIndex: resolved.start.listContinuationIndex,
                  trailingIndex: resolved.start.listTrailingIndex) else { return nil }
        let body = line.content as NSString
        let range = NSRange(location: resolved.startOffset,
                            length: resolved.endOffset - resolved.startOffset)
        guard range.location >= 0, range.length > 0, NSMaxRange(range) <= body.length else { return nil }
        let nextBody = body.replacingCharacters(in: range, with: replacement)
        let expected: MarkdownSourceList?
        if let continuation = resolved.start.listContinuationIndex {
            expected = list.replacingContinuationContent(at: index, lineIndex: continuation, with: nextBody)
        } else if let trailing = resolved.start.listTrailingIndex {
            expected = list.replacingTrailingContinuationContent(at: index, lineIndex: trailing, with: nextBody)
        } else {
            expected = list.replacingItemContent(at: index, with: nextBody)
        }
        guard let expected,
              let blockRange = document.sourceRange(of: resolved.start.blockID) else { return nil }
        let sourceRange = NSRange(location: resolved.startSourceOffset,
                                  length: resolved.endSourceOffset - resolved.startSourceOffset)
        let next = (text as NSString).replacingCharacters(in: sourceRange, with: replacement)
        guard next != text else { return nil }
        let parsed = codec.parse(next)
        guard parsed.toMarkdown() == next, parsed.blocks.count == document.blocks.count,
              parsed.trailingTrivia == document.trailingTrivia,
              parsed.blocks[resolved.firstIndex].source == expected.toMarkdown(),
              parsed.blocks[resolved.firstIndex].leadingTrivia == document.blocks[resolved.firstIndex].leadingTrivia,
              case let .list(actual) = parsed.blocks[resolved.firstIndex].kind,
              actual == expected,
              zip(parsed.blocks, document.blocks).enumerated().allSatisfy({ offset, pair in
                  offset == resolved.firstIndex || Self.sameSourceBlock(pair.0, pair.1)
              }),
              blockRange.location + line.offset + resolved.startOffset == resolved.startSourceOffset else { return nil }
        return (next, resolved.startSourceOffset + (replacement as NSString).length)
    }

    /// Replaces visible text on one quote line. UIKit's whole-field edits use
    /// this path, while toolbar ranges use the endpoint method below.
    @discardableResult
    public func replaceSemanticQuoteLine(id: String, lineIndex: Int, with content: String) -> Bool {
        guard !content.contains("\n"), !content.contains("\r"),
              let block = semanticDocument.blockById(id), case .raw = block.kind,
              let quote = MarkdownSourceQuote(source: block.source),
              quote.lines.indices.contains(lineIndex),
              let blockRange = semanticDocument.sourceRange(of: id) else { return false }
        let line = quote.lines[lineIndex]
        let range = NSRange(location: blockRange.location + line.bodyOffset,
                            length: (line.content as NSString).length)
        let next = (text as NSString).replacingCharacters(in: range, with: content)
        guard validQuoteEdit(next, oldDocument: semanticDocument, blockID: id,
                             expectedLineCount: quote.lines.count,
                             expectedPrefix: line.prefix,
                             changedLine: lineIndex) else { return false }
        return replaceSemanticMarkdown(next)
    }

    private func replacementForQuoteEndpointRange(_ resolved: ResolvedSemanticTextSelection,
                                                   with replacement: String,
                                                   document: MarkdownDocument)
        -> (markdown: String, caret: Int)? {
        guard !replacement.contains("\n"), !replacement.contains("\r"),
              resolved.firstIndex == resolved.lastIndex,
              let startIndex = resolved.start.quoteLineIndex,
              let endIndex = resolved.end.quoteLineIndex else { return nil }
        let block = document.blocks[resolved.firstIndex]
        guard case .raw = block.kind,
              let quote = MarkdownSourceQuote(source: block.source),
              quote.lines.indices.contains(startIndex),
              quote.lines.indices.contains(endIndex),
              startIndex <= endIndex else { return nil }
        let prefix = quote.lines[startIndex].prefix
        guard quote.lines[startIndex...endIndex].allSatisfy({ $0.prefix == prefix }) else { return nil }
        let range = NSRange(location: resolved.startSourceOffset,
                            length: resolved.endSourceOffset - resolved.startSourceOffset)
        let next = (text as NSString).replacingCharacters(in: range, with: replacement)
        guard validQuoteEdit(next, oldDocument: document, blockID: block.id,
                             expectedLineCount: quote.lines.count - (endIndex - startIndex),
                             expectedPrefix: prefix,
                             changedLine: startIndex) else { return nil }
        let parsed = codec.parse(next)
        guard let updated = parsed.blockById(block.id),
              let newQuote = MarkdownSourceQuote(source: updated.source) else { return nil }
        for index in 0..<startIndex where newQuote.lines[index] != quote.lines[index] { return nil }
        let removed = endIndex - startIndex
        for index in (endIndex + 1)..<quote.lines.count {
            let before = quote.lines[index]
            let after = newQuote.lines[index - removed]
            guard before.prefix == after.prefix, before.content == after.content,
                  before.ending == after.ending else { return nil }
        }
        let expected = (quote.lines[startIndex].content as NSString).substring(to: resolved.startOffset)
            + replacement + (quote.lines[endIndex].content as NSString).substring(from: resolved.endOffset)
        guard newQuote.lines[startIndex].content == expected,
              newQuote.lines[startIndex].ending == quote.lines[endIndex].ending else { return nil }
        return (next, resolved.startSourceOffset + (replacement as NSString).length)
    }

    private func validQuoteEdit(_ next: String, oldDocument: MarkdownDocument,
                                blockID: String, expectedLineCount: Int,
                                expectedPrefix: String, changedLine: Int) -> Bool {
        guard next != text else { return false }
        let parsed = codec.parse(next)
        guard parsed.toMarkdown() == next,
              parsed.blocks.count == oldDocument.blocks.count,
              parsed.trailingTrivia == oldDocument.trailingTrivia,
              let index = oldDocument.blocks.firstIndex(where: { $0.id == blockID }),
              parsed.blocks[index].leadingTrivia == oldDocument.blocks[index].leadingTrivia,
              case .raw = parsed.blocks[index].kind,
              let quote = MarkdownSourceQuote(source: parsed.blocks[index].source),
              quote.lines.count == expectedLineCount,
              quote.lines[changedLine].prefix == expectedPrefix else { return false }
        return zip(parsed.blocks, oldDocument.blocks).enumerated().allSatisfy { offset, pair in
            offset == index || Self.sameSourceBlock(pair.0, pair.1)
        }
    }

    /// The parsed code body must occupy the bytes immediately after the opening
    /// fence. This also rejects unusual fences whose body cannot be mapped exactly.
    private static func codeBodyStart(in block: MarkdownDocumentBlock) -> Int? {
        guard case let .fencedCode(_, _, code) = block.kind else { return nil }
        let source = block.source as NSString
        let firstBreak = source.range(of: "\n")
        guard firstBreak.location != NSNotFound else { return nil }
        let start = NSMaxRange(firstBreak)
        let length = (code as NSString).length
        guard start + length <= source.length,
              source.substring(with: NSRange(location: start, length: length)) == code else { return nil }
        return start
    }

    /// The formatted cell displays escaped pipes without their source slash.
    /// Keep a UTF-16 boundary map so a visible selection includes both source
    /// characters when it selects an escaped pipe.
    private static func visibleTableCell(_ raw: String) -> (text: String, boundaries: [Int]) {
        let source = Array(raw.utf16)
        var visible: [UInt16] = []
        var boundaries = [0]
        var index = 0
        while index < source.count {
            if source[index] == 92, index + 1 < source.count, source[index + 1] == 124 {
                visible.append(124)
                index += 2
            } else {
                visible.append(source[index])
                index += 1
            }
            boundaries.append(index)
        }
        return (String(decoding: visible, as: UTF16.self), boundaries)
    }

    private static func escapedTableInsertion(_ value: String) -> String? {
        guard value.utf8.count <= 1_048_576,
              !value.contains("\n"), !value.contains("\r"), !value.contains("\t") else { return nil }
        var result = ""
        var slashes = 0
        for character in value {
            if character == "|", slashes.isMultiple(of: 2) { result.append("\\") }
            result.append(character)
            slashes = character == "\\" ? slashes + 1 : 0
        }
        return result
    }

    private static func tableWithCell(_ table: MarkdownSourceTable, row: Int, column: Int,
                                      raw: String) -> MarkdownSourceTable {
        var expected = table
        if row == 0 { expected.headers[column] = raw }
        else { expected.rows[row - 1][column] = raw }
        return expected
    }

    private func replacementForTableEndpointRange(_ resolved: ResolvedSemanticTextSelection,
                                                  with replacement: String,
                                                  document: MarkdownDocument) -> (markdown: String, caret: Int)? {
        guard let inserted = Self.escapedTableInsertion(replacement) else { return nil }
        let first = document.blocks[resolved.firstIndex]
        let last = document.blocks[resolved.lastIndex]
        let source = text as NSString
        let tableFirst: Bool = { if case .table = first.kind { return true }; return false }()
        let tableBlock = tableFirst ? first : last
        guard case let .table(table) = tableBlock.kind else { return nil }
        let position = tableFirst ? resolved.start : resolved.end
        guard let row = position.tableRow, let column = position.tableColumn,
              let cellRange = document.sourceRangeOfTableCell(blockID: tableBlock.id,
                                                              row: row, column: column) else { return nil }
        let raw = row == 0 ? table.headers[column] : table.rows[row - 1][column]
        let mapped = Self.visibleTableCell(raw)
        let cellStart = cellRange.location
        let cellEnd = NSMaxRange(cellRange)
        let expectedRaw: String
        let expectedVisible: String
        let next: String
        let caret: Int

        if resolved.firstIndex == resolved.lastIndex {
            guard resolved.start.tableRow == row, resolved.start.tableColumn == column,
                  resolved.end.tableRow == row, resolved.end.tableColumn == column else { return nil }
            let range = NSRange(location: resolved.startSourceOffset,
                                length: resolved.endSourceOffset - resolved.startSourceOffset)
            next = source.replacingCharacters(in: range, with: inserted)
            let rawSource = raw as NSString
            expectedRaw = rawSource.substring(to: mapped.boundaries[resolved.startOffset]) + inserted
                + rawSource.substring(from: mapped.boundaries[resolved.endOffset])
            let visible = mapped.text as NSString
            expectedVisible = visible.substring(to: resolved.startOffset) + replacement
                + visible.substring(from: resolved.endOffset)
            caret = resolved.startSourceOffset + (inserted as NSString).length
        } else if tableFirst {
            guard row == table.rows.count, column == table.columnCount - 1,
                  let tableRange = document.sourceRange(of: tableBlock.id) else { return nil }
            let lastPrefix: String
            switch last.kind {
            case .paragraph: lastPrefix = ""
            case .heading:
                guard let bodyStart = Self.editableBodyStart(in: last) else { return nil }
                lastPrefix = (last.source as NSString).substring(to: bodyStart)
            default: return nil
            }
            let tableTail = source.substring(with: NSRange(location: cellEnd,
                                                           length: NSMaxRange(tableRange) - cellEnd))
            next = source.substring(to: resolved.startSourceOffset) + inserted + tableTail
                + last.leadingTrivia + lastPrefix + source.substring(from: resolved.endSourceOffset)
            expectedRaw = (raw as NSString).substring(to: mapped.boundaries[resolved.startOffset]) + inserted
            expectedVisible = (mapped.text as NSString).substring(to: resolved.startOffset) + replacement
            caret = resolved.startSourceOffset + (inserted as NSString).length
        } else {
            guard row == 0, column == 0,
                  let firstRange = document.sourceRange(of: first.id),
                  let tableRange = document.sourceRange(of: tableBlock.id),
                  let firstBodyStart = Self.editableBodyStart(in: first) else { return nil }
            switch first.kind {
            case .paragraph, .heading: break
            default: return nil
            }
            let firstBodyEnd = firstRange.location + firstBodyStart + (first.plainText as NSString).length
            let firstTail = source.substring(with: NSRange(location: firstBodyEnd,
                                                            length: NSMaxRange(firstRange) - firstBodyEnd))
            let tablePrefix = source.substring(with: NSRange(location: tableRange.location,
                                                              length: cellStart - tableRange.location))
            next = source.substring(to: resolved.startSourceOffset) + replacement + firstTail
                + tableBlock.leadingTrivia + tablePrefix + source.substring(from: resolved.endSourceOffset)
            expectedRaw = (raw as NSString).substring(from: mapped.boundaries[resolved.endOffset])
            expectedVisible = (mapped.text as NSString).substring(from: resolved.endOffset)
            caret = resolved.startSourceOffset + (replacement as NSString).length
        }
        guard next != text,
              Self.visibleTableCell(expectedRaw).text == expectedVisible else { return nil }
        let parsed = codec.parse(next)
        let removedBlocks = max(0, resolved.lastIndex - resolved.firstIndex - 1)
        let expectedCount = document.blocks.count - removedBlocks
        guard parsed.toMarkdown() == next, parsed.trailingTrivia == document.trailingTrivia,
              parsed.blocks.count == expectedCount else { return nil }
        for index in 0..<resolved.firstIndex {
            guard Self.sameSourceBlock(parsed.blocks[index], document.blocks[index]) else { return nil }
        }
        let parsedTable = parsed.blocks[tableFirst ? resolved.firstIndex : resolved.firstIndex + 1]
        guard case let .table(updatedTable) = parsedTable.kind,
              parsedTable.leadingTrivia == tableBlock.leadingTrivia,
              updatedTable == Self.tableWithCell(table, row: row, column: column, raw: expectedRaw) else { return nil }
        if resolved.firstIndex != resolved.lastIndex {
            let proseBlock = tableFirst ? last : first
            let parsedProse = parsed.blocks[tableFirst ? resolved.firstIndex + 1 : resolved.firstIndex]
            guard parsedProse.leadingTrivia == proseBlock.leadingTrivia,
                  Self.sameEndpointKind(proseBlock.kind, parsedProse.kind) else { return nil }
        }
        for oldIndex in (resolved.lastIndex + 1)..<document.blocks.count {
            let newIndex = oldIndex - removedBlocks
            guard Self.sameSourceBlock(parsed.blocks[newIndex], document.blocks[oldIndex]) else { return nil }
        }
        return (next, caret)
    }

    private func replacementForCodeEndpointRange(_ resolved: ResolvedSemanticTextSelection,
                                                 with replacement: String,
                                                 document: MarkdownDocument) -> (markdown: String, caret: Int)? {
        guard !replacement.contains("\n"), !replacement.contains("\r") else { return nil }
        let first = document.blocks[resolved.firstIndex]
        let last = document.blocks[resolved.lastIndex]
        let source = text as NSString
        let firstIsCode: Bool = { if case .fencedCode = first.kind { return true }; return false }()
        let lastIsCode: Bool = { if case .fencedCode = last.kind { return true }; return false }()
        // A single code block can use the ordinary, exact source replacement.
        if resolved.firstIndex == resolved.lastIndex {
            guard firstIsCode else { return nil }
            let range = NSRange(location: resolved.startSourceOffset,
                                length: resolved.endSourceOffset - resolved.startSourceOffset)
            let next = source.replacingCharacters(in: range, with: replacement)
            guard next != text else { return nil }
            let parsed = codec.parse(next)
            guard parsed.blocks.count == document.blocks.count,
                  parsed.trailingTrivia == document.trailingTrivia,
                  zip(parsed.blocks, document.blocks).enumerated().allSatisfy({ index, pair in
                      if index == resolved.firstIndex {
                          guard case .fencedCode = pair.0.kind else { return false }
                          return pair.0.leadingTrivia == pair.1.leadingTrivia
                      }
                      return Self.sameSourceBlock(pair.0, pair.1)
                  }) else { return nil }
            return (next, resolved.startSourceOffset + (replacement as NSString).length)
        }
        guard firstIsCode != lastIsCode,
              let firstRange = document.sourceRange(of: first.id),
              let lastRange = document.sourceRange(of: last.id) else { return nil }
        if firstIsCode {
            let lastPrefix: String
            switch last.kind {
            case .paragraph: lastPrefix = ""
            case .heading:
                guard let start = Self.editableBodyStart(in: last) else { return nil }
                lastPrefix = (last.source as NSString).substring(to: start)
            default: return nil
            }
            guard let bodyStart = Self.codeBodyStart(in: first) else { return nil }
            let bodyEnd = firstRange.location + bodyStart + (first.plainText as NSString).length
            let tail = source.substring(with: NSRange(location: bodyEnd,
                length: NSMaxRange(firstRange) - bodyEnd))
            let next = source.substring(to: resolved.startSourceOffset) + replacement + tail
                + last.leadingTrivia + lastPrefix + source.substring(from: resolved.endSourceOffset)
            return validateCodeEndpointReplacement(next, caret: resolved.startSourceOffset + (replacement as NSString).length,
                                                   document: document, resolved: resolved)
        }
        switch first.kind {
        case .paragraph, .heading: break
        default: return nil
        }
        guard let bodyStart = Self.codeBodyStart(in: last) else { return nil }
        guard let proseBodyStart = Self.editableBodyStart(in: first) else { return nil }
        let firstBodyEnd = firstRange.location + proseBodyStart + (first.plainText as NSString).length
        let firstTail = source.substring(with: NSRange(location: firstBodyEnd,
            length: NSMaxRange(firstRange) - firstBodyEnd))
        let codeOpener = source.substring(with: NSRange(location: lastRange.location, length: bodyStart))
        let next = source.substring(to: resolved.startSourceOffset) + replacement + firstTail
            + last.leadingTrivia + codeOpener + source.substring(from: resolved.endSourceOffset)
        return validateCodeEndpointReplacement(next, caret: resolved.startSourceOffset + (replacement as NSString).length,
                                               document: document, resolved: resolved)
    }

    private func validateCodeEndpointReplacement(_ next: String, caret: Int,
                                                 document: MarkdownDocument,
                                                 resolved: ResolvedSemanticTextSelection)
        -> (markdown: String, caret: Int)? {
        guard next != text else { return nil }
        let parsed = codec.parse(next)
        let expectedCount = document.blocks.count - (resolved.lastIndex - resolved.firstIndex - 1)
        guard parsed.toMarkdown() == next, parsed.blocks.count == expectedCount,
              parsed.trailingTrivia == document.trailingTrivia else { return nil }
        for index in 0..<resolved.firstIndex {
            guard Self.sameSourceBlock(parsed.blocks[index], document.blocks[index]) else { return nil }
        }
        let first = document.blocks[resolved.firstIndex]
        let last = document.blocks[resolved.lastIndex]
        let parsedFirst = parsed.blocks[resolved.firstIndex]
        let parsedLast = parsed.blocks[resolved.firstIndex + 1]
        guard parsedFirst.leadingTrivia == first.leadingTrivia,
              parsedLast.leadingTrivia == last.leadingTrivia else { return nil }
        guard Self.sameEndpointKind(first.kind, parsedFirst.kind),
              Self.sameEndpointKind(last.kind, parsedLast.kind) else { return nil }
        for oldIndex in (resolved.lastIndex + 1)..<document.blocks.count {
            let newIndex = oldIndex - (resolved.lastIndex - resolved.firstIndex - 1)
            guard Self.sameSourceBlock(parsed.blocks[newIndex], document.blocks[oldIndex]) else { return nil }
        }
        return (next, caret)
    }

    private static func sameEndpointKind(_ original: MarkdownSemanticBlock,
                                         _ parsed: MarkdownSemanticBlock) -> Bool {
        switch (original, parsed) {
        case (.paragraph, .paragraph), (.fencedCode, .fencedCode): return true
        case let (.heading(oldLevel, _), .heading(newLevel, _)): return oldLevel == newLevel
        default: return false
        }
    }

    /// Applies one semantic body edit through the existing source undo history.
    @discardableResult
    public func replaceSemanticBlockContent(id: String, with content: String) -> Bool {
        let document = semanticDocument
        guard let block = document.blockById(id), let replacement = block.replacingContent(content) else { return false }
        let updated = document.replacingBlock(replacement).toMarkdown()
        return replaceSemanticMarkdown(updated)
    }

    /// Edits only the body of leading YAML frontmatter. Its delimiters and all
    /// other blocks retain their exact source; an embedded closing marker is rejected.
    @discardableResult
    public func replaceFrontmatterContent(id: String, with content: String) -> Bool {
        let document = semanticDocument
        guard let first = document.blocks.first, first.id == id, case .raw = first.kind,
              first.leadingTrivia.isEmpty,
              let frontmatter = MarkdownSourceFrontmatter.parsePrefix(text),
              first.source == frontmatter.source,
              let replacementSource = frontmatter.replacingContent(content) else { return false }
        let replacement = MarkdownDocumentBlock(id: id, kind: .raw, source: replacementSource)
        let updated = document.replacingBlock(replacement).toMarkdown()
        let reparsed = codec.parse(updated)
        guard reparsed.blocks.count == document.blocks.count,
              reparsed.trailingTrivia == document.trailingTrivia,
              reparsed.blocks.first?.source == replacementSource,
              zip(reparsed.blocks.dropFirst(), document.blocks.dropFirst()).allSatisfy({ pair in pair.0 == pair.1 })
        else { return false }
        return replaceSemanticMarkdown(updated)
    }

    /// Updates a formatted code block's language as one source-backed undo step.
    /// Empty language selects plain text; unsupported characters are rejected.
    @discardableResult
    public func setCodeBlockLanguage(id: String, to language: String) -> Bool {
        let document = semanticDocument
        guard let block = document.blockById(id),
              let replacement = block.replacingCodeLanguage(language) else { return false }
        let updated = document.replacingBlock(replacement).toMarkdown()
        let reparsed = codec.parse(updated)
        guard reparsed.blocks.count == document.blocks.count,
              reparsed.trailingTrivia == document.trailingTrivia else { return false }
        for (current, original) in zip(reparsed.blocks, document.blocks) {
            guard current.id == original.id, current.leadingTrivia == original.leadingTrivia else { return false }
            if current.id == id {
                guard current.source == replacement.source, current.kind == replacement.kind else { return false }
            } else if current != original { return false }
        }
        return replaceSemanticMarkdown(updated)
    }

    /// Multi-line keyboard replacement is usually a paste. Keep ordinary prose
    /// and active IME composition on the text view's normal editing path.
    static func isStructuredBlockPaste(_ replacement: String, hasMarkedText: Bool) -> Bool {
        guard !hasMarkedText, replacement.contains("\n") || replacement.contains("\r") else { return false }
        let document = MarkdownDocumentCodec().parse(replacement)
        return document.blocks.contains { block in
            if case .paragraph = block.kind {
                return block.plainText.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("![")
            }
            return true
        }
    }

    /// Inserts parsed Markdown blocks into a UTF-16 range of a formatted
    /// paragraph or heading. The text on either side becomes separate sibling
    /// blocks, while every untouched source block stays byte-for-byte intact.
    /// Invalid ranges or a paste that would merge with a neighbor are rejected
    /// before entering the source undo history.
    @discardableResult
    public func replaceSemanticTextRangeWithMarkdownBlocks(id: String, range: NSRange,
                                                            markdown: String, ifTextIs expectedText: String? = nil) -> Bool {
        if let expectedText, expectedText != text { return false }
        let document = semanticDocument
        guard let index = document.blocks.firstIndex(where: { $0.id == id }),
              let sourceRange = document.sourceRange(of: id),
              !markdown.isEmpty else { return false }
        let block = document.blocks[index]
        switch block.kind {
        case .paragraph, .heading: break
        case .fencedCode, .table, .list, .horizontalRule, .plugin, .raw: return false
        }
        let body = block.plainText as NSString
        guard range.location != NSNotFound, range.location >= 0, range.length >= 0,
              NSMaxRange(range) <= body.length,
              Range(range, in: block.plainText) != nil,
              Self.isUTF16ScalarBoundary(range.location, in: block.plainText),
              Self.isUTF16ScalarBoundary(NSMaxRange(range), in: block.plainText),
              MarkdownInlineMarkEditor.canSplitForBlockPaste(block.plainText, range: range) else { return false }
        let inserted = codec.parse(markdown)
        guard !inserted.blocks.isEmpty, inserted.toMarkdown() == markdown else { return false }

        let before = body.substring(to: range.location)
        let after = body.substring(from: NSMaxRange(range))
        let hasBefore = !before.isEmpty
        let hasAfter = !after.isEmpty
        let ending = block.source.hasSuffix("\r\n") ? "\r\n" : block.source.hasSuffix("\n") ? "\n" : ""
        let lineEnding = block.source.contains("\r\n") ? "\r\n" : "\n"
        let prefixLength = (block.source as NSString).length - body.length - (ending as NSString).length
        guard prefixLength >= 0,
              (block.source as NSString).substring(with: NSRange(location: prefixLength, length: body.length))
                == block.plainText else { return false }
        let prefix = (block.source as NSString).substring(to: prefixLength)
        var replacement = ""
        if hasBefore { replacement = Self.joinPastedBlocks(prefix + before, markdown, lineEnding: lineEnding) }
        else { replacement = markdown }
        let pastedEnd = (replacement as NSString).length
        if hasAfter { replacement = Self.joinPastedBlocks(replacement, after, lineEnding: lineEnding) }
        if !ending.isEmpty && !replacement.hasSuffix("\n") { replacement += ending }

        let updated = (text as NSString).replacingCharacters(in: sourceRange, with: replacement)
        let reparsed = codec.parse(updated)
        let replacementCount = (hasBefore ? 1 : 0) + inserted.blocks.count + (hasAfter ? 1 : 0)
        guard reparsed.toMarkdown() == updated,
              reparsed.blocks.count == document.blocks.count - 1 + replacementCount,
              reparsed.trailingTrivia == document.trailingTrivia else { return false }
        for oldIndex in 0..<index {
            guard Self.sameSourceBlock(reparsed.blocks[oldIndex], document.blocks[oldIndex]) else { return false }
        }
        let insertedIndex = index + (hasBefore ? 1 : 0)
        if hasBefore {
            let first = reparsed.blocks[index]
            guard first.kind == block.replacingContent(before)?.kind,
                  first.leadingTrivia == block.leadingTrivia,
                  first.plainText == before else { return false }
        }
        for offset in inserted.blocks.indices {
            let actual = reparsed.blocks[insertedIndex + offset]
            let expected = inserted.blocks[offset]
            guard Self.sameInsertedBlock(actual, expected) else { return false }
        }
        if hasAfter {
            let last = reparsed.blocks[insertedIndex + inserted.blocks.count]
            guard case .paragraph = last.kind, last.plainText == after else { return false }
        }
        for oldIndex in (index + 1)..<document.blocks.count {
            let nextIndex = oldIndex - 1 + replacementCount
            guard Self.sameSourceBlock(reparsed.blocks[nextIndex], document.blocks[oldIndex]) else { return false }
        }
        guard replaceSemanticMarkdown(updated) else { return false }
        setSelection(NSRange(location: sourceRange.location + pastedEnd, length: 0))
        return true
    }

    private static func sameSourceBlock(_ left: MarkdownDocumentBlock, _ right: MarkdownDocumentBlock) -> Bool {
        left.kind == right.kind && left.source == right.source && left.leadingTrivia == right.leadingTrivia
    }

    private static func sameInsertedBlock(_ left: MarkdownDocumentBlock, _ right: MarkdownDocumentBlock) -> Bool {
        guard left.plainText == right.plainText,
              left.source.trimmingCharacters(in: .newlines) == right.source.trimmingCharacters(in: .newlines)
        else { return false }
        switch (left.kind, right.kind) {
        case (.paragraph, .paragraph), (.fencedCode, .fencedCode), (.table, .table), (.list, .list),
             (.horizontalRule, .horizontalRule), (.raw, .raw), (.plugin, .plugin): return true
        case let (.heading(leftLevel, _), .heading(rightLevel, _)): return leftLevel == rightLevel
        default: return false
        }
    }

    private static func isUTF16ScalarBoundary(_ offset: Int, in text: String) -> Bool {
        let units = Array(text.utf16)
        guard offset > 0 && offset < units.count else { return true }
        return !(0xD800...0xDBFF).contains(units[offset - 1]) ||
            !(0xDC00...0xDFFF).contains(units[offset])
    }

    private static func joinPastedBlocks(_ first: String, _ second: String, lineEnding: String) -> String {
        var tail = first[...]
        var breaks = 0
        while tail.last == "\n" {
            tail = tail.dropLast()
            if tail.last == "\r" { tail = tail.dropLast() }
            breaks += 1
        }
        return first + String(repeating: lineEnding, count: max(0, 2 - breaks)) + second
    }

    /// Applies one inline mark to a UTF-16 selection within an editable Blocks row.
    /// Returns the selection in the new block body, or nil for an unsupported edit.
    @discardableResult
    public func applySemanticInlineMark(id: String, selection: NSRange, mark: MarkdownInlineMark) -> NSRange? {
        let document = semanticDocument
        guard let block = document.blockById(id), let sourceRange = document.sourceRange(of: id) else { return nil }
        switch block.kind {
        case .paragraph, .heading: break
        case .fencedCode, .table, .list, .horizontalRule, .plugin, .raw: return nil
        }
        let oldBody = block.plainText
        guard let edit = MarkdownInlineMarkEditor.apply(mark, to: oldBody, selection: selection),
              let replacement = block.replacingContent(edit.markdown) else { return nil }
        let updated = document.replacingBlock(replacement).toMarkdown()
        guard updated != text else { return nil }
        let endingLength = block.source.hasSuffix("\r\n") ? 2 : block.source.hasSuffix("\n") ? 1 : 0
        let bodyOffset = (block.source as NSString).length - (oldBody as NSString).length - endingLength
        let selectedInSource = NSRange(location: sourceRange.location + bodyOffset + edit.selection.location,
                                       length: edit.selection.length)
        replaceRange(NSRange(location: 0, length: (text as NSString).length), with: updated,
                     selectedRange: selectedInSource)
        return edit.selection
    }

    /// Removes a top-level block, including its separator, through source undo history.
    @discardableResult
    public func removeSemanticBlock(id: String) -> Bool {
        let document = semanticDocument
        guard document.blockById(id) != nil else { return false }
        let updated = document.removingBlock(id).toMarkdown()
        return replaceSemanticMarkdown(updated)
    }

    /// Applies a semantic table operation by block ID through the source undo stack.
    @discardableResult
    public func updateSemanticTable(id: String, _ transform: (MarkdownSourceTable) -> MarkdownSourceTable) -> Bool {
        guard let updated = semanticDocument.updatingTable(id, transform)?.toMarkdown() else { return false }
        return replaceSemanticMarkdown(updated)
    }

    /// Edits a supported list item through the same source history as other Blocks edits.
    @discardableResult
    public func updateSemanticList(id: String, _ transform: (MarkdownSourceList) -> MarkdownSourceList?) -> Bool {
        guard let updated = semanticDocument.updatingList(id, transform)?.toMarkdown() else { return false }
        return replaceSemanticMarkdown(updated)
    }

    /// Inserts a pasted list below a formatted list row in one source-history
    /// operation. The returned row and UTF-16 offset let the rebuilt field keep
    /// the visible formatted caret on the last pasted child.
    @discardableResult
    func replaceSemanticListLineWithMarkdownBlocks(id: String, index: Int, continuationIndex: Int? = nil,
                                                   range: NSRange, markdown: String,
                                                   ifTextIs expectedText: String? = nil)
        -> (index: Int, continuationIndex: Int?, offset: Int)? {
        if let expectedText, expectedText != text { return nil }
        let document = semanticDocument
        guard let blockIndex = document.blocks.firstIndex(where: { $0.id == id }),
              case let .list(list) = document.blocks[blockIndex].kind,
              let blockRange = document.sourceRange(of: id),
              let edit = list.replacingLineRangeWithNestedList(at: index,
                                                              continuationIndex: continuationIndex,
                                                              range: range, markdown: markdown)
        else { return nil }
        let updated = (text as NSString).replacingCharacters(in: blockRange, with: edit.source)
        let reparsed = codec.parse(updated)
        guard reparsed.blocks.count == document.blocks.count,
              reparsed.trailingTrivia == document.trailingTrivia,
              reparsed.blocks.indices.allSatisfy({ position in
                  position == blockIndex ||
                      Self.sameSourceBlock(reparsed.blocks[position], document.blocks[position])
              }),
              case .list = reparsed.blocks[blockIndex].kind,
              let replacement = reparsed.blockById(id),
              replacement.leadingTrivia == document.blocks[blockIndex].leadingTrivia,
              replacement.source == edit.source else { return nil }
        guard replaceSemanticMarkdown(updated) else { return nil }
        setSelection(NSRange(location: blockRange.location + edit.sourceCaretOffset, length: 0))
        return (edit.focusIndex, edit.focusContinuationIndex, edit.focusOffset)
    }

    /// A visible fallback for structured paste the formatted list model cannot
    /// represent. The exact clipboard text replaces only the current row's
    /// selected source range, then Source mode exposes the result for editing.
    @discardableResult
    func pasteListLineVerbatimInSource(id: String, index: Int, continuationIndex: Int? = nil,
                                      trailingIndex: Int? = nil, range: NSRange,
                                      markdown: String, displayedText: String) -> Bool {
        guard !markdown.isEmpty, mode == .formatted else { return false }
        let document = semanticDocument
        guard let block = document.blockById(id), case let .list(list) = block.kind,
              let blockRange = document.sourceRange(of: id),
              let line = list.sourceLine(at: index, continuationIndex: continuationIndex,
                                         trailingIndex: trailingIndex),
              line.content == displayedText,
              range.location != NSNotFound, range.location >= 0, range.length >= 0,
              NSMaxRange(range) <= (line.content as NSString).length else { return false }
        let absolute = NSRange(location: blockRange.location + line.offset + range.location,
                               length: range.length)
        guard isValidSourceRange(absolute),
              (text as NSString).substring(with: absolute) ==
                (line.content as NSString).substring(with: range) else { return false }
        replaceRange(absolute, with: markdown)
        mode = .source
        return true
    }

    /// Return outdents an empty nested item, exits an empty root item, or adds a sibling.
    @discardableResult
    func submitSemanticListItem(id: String, at index: Int, contentOffset: Int? = nil) -> Bool {
        let document = semanticDocument
        guard let block = document.blockById(id), case let .list(list) = block.kind,
              list.items.indices.contains(index) else { return false }
        let item = list.items[index]
        if let contentOffset {
            let contentLength = (item.content as NSString).length
            guard contentOffset >= 0, contentOffset <= contentLength else { return false }
            if contentOffset < contentLength {
                return updateSemanticList(id: id) { $0.splittingItem(at: index, contentOffset: contentOffset) }
            }
        }
        if item.content.isEmpty && item.continuations.isEmpty && !list.hasNestedItems(at: index),
           !list.isNestedItem(at: index) {
            guard let blockRange = document.sourceRange(of: id) else { return false }
            guard let itemOffset = list.sourceOffset(ofItemAt: index) else { return false }
            let itemRange = NSRange(location: blockRange.location + itemOffset,
                                    length: (item.source as NSString).length)
            let newline = text.contains("\r\n") ? "\r\n" : "\n"
            // With preceding siblings, a blank line separates the list and the new paragraph.
            // The first item has no preceding list to separate, so remove its whole source line.
            let replacement = index == 0 ? "" : (item.lineEnding.isEmpty ? newline : item.lineEnding)
            replaceRange(itemRange, with: replacement)
            pendingListParagraph = .init(sourceOffset: itemRange.location + (replacement as NSString).length,
                                         draft: "", insertedTerminator: "")
            return true
        }
        return updateSemanticList(id: id) { list in
            guard list.items.indices.contains(index) else { return nil }
            if list.items[index].content.isEmpty, list.isNestedItem(at: index),
               let outdented = list.outdentingItem(at: index) {
                return outdented
            }
            return list.insertingEmptyItem(after: index)
        }
    }

    /// Updates the focused paragraph without dropping its UIKit text field as soon as it parses as a block.
    @discardableResult
    func updatePendingListParagraph(_ draft: String) -> Bool {
        guard let pendingListParagraph, !draft.contains("\n"), !draft.contains("\r"),
              pendingListParagraph.sourceOffset <= (text as NSString).length else { return false }
        let oldLength = (pendingListParagraph.draft as NSString).length
            + (pendingListParagraph.insertedTerminator as NSString).length
        let range = NSRange(location: pendingListParagraph.sourceOffset, length: oldLength)
        guard NSMaxRange(range) <= (text as NSString).length else { return false }
        let nextTerminator: String
        if draft.isEmpty || NSMaxRange(range) == (text as NSString).length {
            nextTerminator = ""
        } else {
            nextTerminator = text.contains("\r\n") ? "\r\n" : "\n"
        }
        let replacement = draft + nextTerminator
        guard draft != pendingListParagraph.draft || nextTerminator != pendingListParagraph.insertedTerminator else {
            return true
        }
        replaceRange(range, with: replacement,
                     selectedRange: NSRange(location: (draft as NSString).length, length: 0))
        self.pendingListParagraph = .init(sourceOffset: range.location, draft: draft,
                                          insertedTerminator: nextTerminator)
        return true
    }

    func finishPendingListParagraph() {
        // The codec treats an empty paragraph as trivia. Keep its field available after blur.
        if pendingListParagraph?.draft.isEmpty == false { pendingListParagraph = nil }
    }

    /// Keeps a Source-mode selection anchored when a Blocks edit changes text before it.
    /// Comparing Unicode scalars keeps the mapped endpoints outside UTF-16 surrogate pairs.
    private func replaceSemanticMarkdown(_ updated: String) -> Bool {
        guard updated != text else { return false }
        let before = Array(text.unicodeScalars)
        let after = Array(updated.unicodeScalars)
        var prefix = 0
        var prefixLength = 0
        while prefix < min(before.count, after.count), before[prefix] == after[prefix] {
            prefixLength += before[prefix].value > 0xFFFF ? 2 : 1
            prefix += 1
        }
        var suffix = 0
        var suffixLength = 0
        while suffix < before.count - prefix, suffix < after.count - prefix,
              before[before.count - suffix - 1] == after[after.count - suffix - 1] {
            suffixLength += before[before.count - suffix - 1].value > 0xFFFF ? 2 : 1
            suffix += 1
        }

        let oldLength = (text as NSString).length
        let newLength = (updated as NSString).length
        let oldSuffixStart = oldLength - suffixLength
        let newSuffixStart = newLength - suffixLength
        func mapped(_ offset: Int) -> Int {
            if prefixLength == oldSuffixStart, offset >= oldSuffixStart {
                return min(newLength, offset + newLength - oldLength)
            }
            if offset <= prefixLength { return offset }
            if offset >= oldSuffixStart { return offset + newLength - oldLength }
            return min(newSuffixStart, offset)
        }
        func validBoundary(_ offset: Int) -> Int {
            var position = min(max(0, offset), newLength)
            while position > 0, Range(NSRange(location: position, length: 0), in: updated) == nil {
                position -= 1
            }
            return position
        }
        let start = validBoundary(mapped(selection.location))
        let end = validBoundary(mapped(NSMaxRange(selection)))
        let nextSelection = NSRange(location: start, length: max(0, end - start))
        replaceRange(NSRange(location: 0, length: oldLength), with: updated, selectedRange: nextSelection)
        return true
    }

    public func markSaved(_ saved: String? = nil) { savedText = saved ?? text }
    public func clearHistory() { undoStack.removeAll(); redoStack.removeAll() }

    public func updateFromInput(text nextText: String, selection nextSelection: NSRange,
                                isComposing: Bool = false) {
        if isComposing, compositionStartingText == nil { compositionStartingText = text }
        let changed = nextText != text
        if changed { recordUndo(snapshot()) }
        text = nextText
        selection = clamped(nextSelection, in: nextText)
        if changed { pendingListParagraph = nil }
        if !isComposing {
            if let original = compositionStartingText {
                compositionStartingText = nil
                if original != text { emitCommittedText() }
            } else if changed { emitCommittedText() }
        }
    }

    public func setSelection(_ range: NSRange) { selection = clamped(range, in: text) }

    @discardableResult
    public func undo() -> Bool {
        guard let previous = undoStack.popLast() else { return false }
        let oldText = text
        redoStack.append(snapshot())
        text = previous.text
        selection = previous.selection
        pendingListParagraph = previous.pendingListParagraph
        compositionStartingText = nil
        if text != oldText { emitCommittedText() }
        return true
    }

    @discardableResult
    public func redo() -> Bool {
        guard let next = redoStack.popLast() else { return false }
        let oldText = text
        pushUndo(snapshot())
        text = next.text
        selection = next.selection
        pendingListParagraph = next.pendingListParagraph
        compositionStartingText = nil
        if text != oldText { emitCommittedText() }
        return true
    }

    public func transaction<T>(_ body: () throws -> T) rethrows -> T {
        if transactionDepth == 0 { transactionBefore = snapshot() }
        transactionDepth += 1
        defer {
            transactionDepth -= 1
            if transactionDepth == 0 {
                let changed = transactionBefore.map { $0.text != text } ?? false
                if let before = transactionBefore, before.text != text {
                    pushUndo(before)
                    redoStack.removeAll()
                }
                transactionBefore = nil
                if changed { committedTextChanges.send(text) }
            }
        }
        return try body()
    }

    public func replaceSelection(_ replacement: String, selectedRange: NSRange? = nil) {
        replaceRange(normalizedSelection(), with: replacement, selectedRange: selectedRange)
    }

    public func replaceRange(_ range: NSRange, with replacement: String, selectedRange: NSRange? = nil) {
        let valid = clamped(range, in: text)
        let next = (text as NSString).replacingCharacters(in: valid, with: replacement)
        let relative = selectedRange ?? NSRange(location: (replacement as NSString).length, length: 0)
        let maxOffset = (replacement as NSString).length
        let offset = min(max(0, relative.location), maxOffset)
        let length = min(max(0, relative.length), maxOffset - offset)
        updateValue(next, selection: NSRange(location: valid.location + offset, length: length))
    }

    public func insertMarkdown(_ markdown: String) { replaceSelection(markdown) }

    public func insertMarkdownBlock(_ markdown: String) {
        let block = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        if !block.isEmpty { insertSeparatedBlock(block) }
    }

    /// Inserts host-provided Markdown at the selection captured before asynchronous I/O.
    /// An intervening source edit invalidates the result instead of overwriting newer work.
    @discardableResult
    public func insertHostedMarkdownBlock(_ markdown: String, at range: NSRange, ifTextIs expectedText: String) -> Bool {
        let block = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !block.isEmpty, text == expectedText, isValidSourceRange(range) else { return false }
        let source = text as NSString
        let before = source.substring(to: range.location)
        let after = source.substring(from: NSMaxRange(range))
        let newline = text.contains("\r\n") ? "\r\n" : "\n"
        let leading = before.isEmpty || before.hasSuffix(newline + newline) ? "" :
            before.hasSuffix(newline) ? newline : newline + newline
        let trailing = after.isEmpty || after.hasPrefix(newline + newline) ? "" :
            after.hasPrefix(newline) ? newline : newline + newline
        let replacement = leading + block + trailing
        replaceRange(range, with: replacement,
                     selectedRange: NSRange(location: (leading as NSString).length + (block as NSString).length, length: 0))
        return true
    }

    /// Inserts a safe Markdown image block. Empty alt text uses the captured selected text.
    @discardableResult
    public func insertHostedImage(_ image: MarkdownEditorImageSelection, at range: NSRange,
                                  ifTextIs expectedText: String) -> Bool {
        guard text == expectedText, isValidSourceRange(range) else { return false }
        let url = image.url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.contains(where: { $0.isWhitespace || $0 == "<" || $0 == ">" || $0 == "\"" || $0 == "\\" }),
              ImageSource.parse(url) != nil else { return false }
        let selected = (text as NSString).substring(with: range)
        let alt = image.alt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? selected : image.alt
        let safeAlt = alt.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
        let safeURL = url.replacingOccurrences(of: "(", with: "%28")
            .replacingOccurrences(of: ")", with: "%29")
            .replacingOccurrences(of: "[", with: "%5B")
            .replacingOccurrences(of: "]", with: "%5D")
        let title = image.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let safeTitle = title.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
        let titleSuffix = safeTitle.isEmpty ? "" : " \"\(safeTitle)\""
        return insertHostedMarkdownBlock("![\(safeAlt)](\(safeURL)\(titleSuffix))", at: range, ifTextIs: expectedText)
    }

    private func isValidSourceRange(_ range: NSRange) -> Bool {
        let source = text as NSString
        guard range.location != NSNotFound, range.location >= 0, range.length >= 0,
              NSMaxRange(range) <= source.length,
              let swiftRange = Range(range, in: text), NSRange(swiftRange, in: text) == range else { return false }
        for offset in [range.location, NSMaxRange(range)] where offset > 0 && offset < source.length {
            let previous = source.character(at: offset - 1)
            let next = source.character(at: offset)
            if (0xD800...0xDBFF).contains(previous) && (0xDC00...0xDFFF).contains(next) { return false }
        }
        return true
    }

    public func insertTable(rows: Int = 3, columns: Int = 3) {
        let rowCount = max(1, rows)
        let columnCount = max(1, columns)
        let header = Array(repeating: "Column", count: columnCount).joined(separator: " | ")
        let separator = Array(repeating: "---", count: columnCount).joined(separator: " | ")
        let body = Array(repeating: "| " + Array(repeating: "Cell", count: columnCount).joined(separator: " | ") + " |", count: rowCount - 1)
        insertSeparatedBlock((["| \(header) |", "| \(separator) |"] + body).joined(separator: "\n"))
    }

    /// Returns the GFM table under the current source selection.
    public func tableAtSelection() -> MarkdownSourceTable? {
        findSourceTable(text, offset: selection.location)?.table
    }

    @discardableResult
    public func replaceTableCellText(rowIndex: Int, columnIndex: Int, text: String, header: Bool = false) -> Bool {
        editSelectedTable { $0.replacingCell(rowIndex: rowIndex, columnIndex: columnIndex, text: text, header: header) }
    }

    @discardableResult public func insertTableRowBefore(_ index: Int) -> Bool { editSelectedTable { $0.insertingRowBefore(index) } }
    @discardableResult public func insertTableRowAfter(_ index: Int) -> Bool { editSelectedTable { $0.insertingRowAfter(index) } }
    @discardableResult public func deleteTableRow(_ index: Int) -> Bool { editSelectedTable { $0.deletingRow(index) } }
    @discardableResult public func insertTableColumnBefore(_ index: Int) -> Bool { editSelectedTable { $0.insertingColumnBefore(index) } }
    @discardableResult public func insertTableColumnAfter(_ index: Int) -> Bool { editSelectedTable { $0.insertingColumnAfter(index) } }
    @discardableResult public func deleteTableColumn(_ index: Int) -> Bool { editSelectedTable { $0.deletingColumn(index) } }
    @discardableResult public func setTableColumnAlignment(_ index: Int, to alignment: MarkdownTableAlignment?) -> Bool {
        editSelectedTable { $0.settingColumnAlignment(index, to: alignment) }
    }

    @discardableResult
    public func deleteTableAtSelection() -> Bool {
        guard let located = findSourceTable(text, offset: selection.location) else { return false }
        replaceRange(located.range, with: "")
        return true
    }

    private func editSelectedTable(_ transform: (MarkdownSourceTable) -> MarkdownSourceTable) -> Bool {
        guard let located = findSourceTable(text, offset: selection.location) else { return false }
        let updated = transform(located.table)
        if updated != located.table {
            let replacement = updated.toMarkdown()
            let relativeCaret = min(max(0, selection.location - located.range.location), (replacement as NSString).length)
            replaceRange(located.range, with: replacement, selectedRange: NSRange(location: relativeCaret, length: 0))
        }
        return true
    }

    public func findMatches(_ query: String, caseSensitive: Bool = false) -> [NSRange] {
        guard !query.isEmpty else { return [] }
        let options: NSString.CompareOptions = caseSensitive ? [] : [.caseInsensitive]
        let source = text as NSString
        var results: [NSRange] = []
        var searchStart = 0
        while searchStart < source.length && results.count < 500 {
            let found = source.range(of: query, options: options, range: NSRange(location: searchStart, length: source.length - searchStart))
            if found.location == NSNotFound { break }
            results.append(found)
            searchStart = NSMaxRange(found)
        }
        return results
    }

    @discardableResult
    public func selectNextMatch(_ query: String, caseSensitive: Bool = false) -> NSRange? {
        let matches = findMatches(query, caseSensitive: caseSensitive)
        guard let first = matches.first else { return nil }
        let next = matches.first { $0.location >= NSMaxRange(selection) } ?? first
        selection = next
        return next
    }

    /// Resolves a slash trigger at the start of a formatted paragraph's visible text.
    /// The returned range is in source UTF-16 coordinates so it can be checked again
    /// when a suggestion is selected.
    public func slashCommandMatch(inBlock id: String, selection: NSRange) -> MarkdownSlashCommandMatch? {
        guard selection.length == 0,
              let block = semanticDocument.blockById(id),
              let blockRange = semanticDocument.sourceRange(of: id),
              case .paragraph = block.kind else { return nil }
        let body = block.plainText as NSString
        guard selection.location <= body.length else { return nil }
        let prefix = body.substring(to: selection.location)
        guard prefix.hasPrefix("/"),
              !prefix.dropFirst().contains(where: { $0.isWhitespace || $0.isNewline }) else { return nil }
        let range = NSRange(location: blockRange.location, length: selection.location)
        guard isValidSourceRange(range),
              (text as NSString).substring(with: range) == prefix else { return nil }
        return MarkdownSlashCommandMatch(range: range, query: String(prefix.dropFirst()))
    }

    /// Consumes a still-current trigger and applies a built-in command as one undo step.
    @discardableResult
    public func applySlashCommand(_ command: MarkdownEditorCommand, match: MarkdownSlashCommandMatch) -> Bool {
        guard isValidSourceRange(match.range),
              (text as NSString).substring(with: match.range) == "/" + match.query else { return false }
        setSelection(NSRange(location: NSMaxRange(match.range), length: 0))
        transaction {
            replaceRange(match.range, with: "")
            if case .wikilink = command {
                insertMarkdown("[[")
            } else {
                applyCommand(command)
            }
            let prefixLength: Int?
            switch command {
            case .paragraph: prefixLength = 0
            case .heading1: prefixLength = 2
            case .heading2: prefixLength = 3
            case .heading3: prefixLength = 4
            case .heading4: prefixLength = 5
            case .heading5: prefixLength = 6
            case .heading6: prefixLength = 7
            case .unorderedList: prefixLength = 2
            case .orderedList: prefixLength = 3
            case .taskList: prefixLength = 6
            case .blockquote: prefixLength = 2
            default: prefixLength = nil
            }
            if let prefixLength {
                setSelection(NSRange(location: match.range.location + prefixLength, length: 0))
            }
        }
        return true
    }

    /// Inserts a host-provided slash result as a separated Markdown block.
    /// The trigger is checked again after an asynchronous host callback, and
    /// removing it plus inserting the block forms one undo step.
    @discardableResult
    public func applyCustomSlashCommand(_ markdown: String, match: MarkdownSlashCommandMatch) -> Bool {
        let block = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !block.isEmpty, isValidSourceRange(match.range),
              (text as NSString).substring(with: match.range) == "/" + match.query else { return false }
        setSelection(NSRange(location: NSMaxRange(match.range), length: 0))
        transaction {
            replaceRange(match.range, with: "")
            insertSeparatedBlock(block)
        }
        return true
    }

    public func applyCommand(_ command: MarkdownEditorCommand, argument: String? = nil) {
        if let level = command.headingLevel {
            transformLines { _, line in
                String(repeating: "#", count: level) + " " + line.replacingOccurrences(of: "^ {0,3}#{1,6} +", with: "", options: .regularExpression)
            }
            return
        }
        switch command {
        case .paragraph:
            transformLines { _, line in
                var value = line
                for pattern in ["^ {0,3}#{1,6}\\s+", "^ {0,3}>\\s?", "^ {0,3}[-*+]\\s+\\[[ xX]\\]\\s+", "^ {0,3}[-*+]\\s+", "^ {0,3}\\d+[.)]\\s+"] {
                    value = value.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
                }
                return value
            }
        case .bold: wrap("**", "**", placeholder: "bold")
        case .italic: wrap("*", "*", placeholder: "italic")
        case .strikethrough: wrap("~~", "~~", placeholder: "strikethrough")
        case .inlineCode: wrap("`", "`", placeholder: "code")
        case .unorderedList: transformLines { _, line in "- " + line }
        case .orderedList: transformLines { index, line in "\(index + 1). " + line }
        case .taskList: transformLines { _, line in "- [ ] " + line }
        case .blockquote: transformLines { _, line in "> " + line }
        case .codeBlock: wrapBlock("```" + (argument ?? ""), "```", placeholder: "code")
        case .link: wrap("[", "](\(argument?.isEmpty == false ? argument! : "https://example.com"))", placeholder: "link")
        case .image: wrap("![", "](\(argument?.isEmpty == false ? argument! : "image-url"))", placeholder: "alt text")
        case .table: insertTable()
        case .blockMath: wrapBlock("$$", "$$", placeholder: "E = mc^2")
        case .mermaidDiagram: insertSeparatedBlock("```mermaid\nflowchart TD\n  A[Start] --> B[End]\n```")
        case .horizontalRule: insertSeparatedBlock("---")
        case .wikilink: wrap("[[", "]]", placeholder: "Note")
        case .heading1, .heading2, .heading3, .heading4, .heading5, .heading6: break
        }
    }

    /// Replaces the active `[[` trigger in a formatted paragraph or heading.
    /// The source edit is a single undo step and leaves every other byte untouched.
    @discardableResult
    public func insertWikilinkSuggestion(_ title: String, inBlock id: String,
                                         selection: NSRange) -> NSRange? {
        guard !title.isEmpty, !title.contains("]"), !title.contains("\n"), !title.contains("\r"),
              selection.length == 0,
              let block = semanticDocument.blockById(id),
              let blockRange = semanticDocument.sourceRange(of: id) else { return nil }
        switch block.kind {
        case .paragraph, .heading: break
        case .fencedCode, .table, .list, .horizontalRule, .plugin, .raw: return nil
        }
        let body = block.plainText
        guard let match = WikilinkTrigger.match(in: body, cursor: selection.location) else { return nil }
        let endingLength = block.source.hasSuffix("\r\n") ? 2 : block.source.hasSuffix("\n") ? 1 : 0
        let bodyOffset = (block.source as NSString).length - (body as NSString).length - endingLength
        guard bodyOffset >= 0 else { return nil }
        let sourceRange = NSRange(location: blockRange.location + bodyOffset + match.range.location,
                                  length: match.range.length)
        guard isValidSourceRange(sourceRange),
              (text as NSString).substring(with: sourceRange) == "[[" + match.query else { return nil }
        let replacement = "[[\(title)]]"
        replaceRange(sourceRange, with: replacement)
        return NSRange(location: match.range.location + (replacement as NSString).length, length: 0)
    }

    private func updateValue(_ next: String, selection nextSelection: NSRange) {
        let changed = next != text
        if changed { recordUndo(snapshot()) }
        text = next
        selection = nextSelection
        pendingListParagraph = nil
        if changed { emitCommittedText() }
    }

    private func emitCommittedText() {
        if transactionDepth == 0 { committedTextChanges.send(text) }
    }

    private func snapshot() -> Snapshot {
        .init(text: text, selection: selection, pendingListParagraph: pendingListParagraph)
    }

    private func recordUndo(_ previous: Snapshot) {
        if transactionDepth == 0 {
            pushUndo(previous)
            redoStack.removeAll()
        }
    }

    private func pushUndo(_ snapshot: Snapshot) {
        guard historyLimit > 0 else { return }
        if undoStack.count == historyLimit { undoStack.removeFirst() }
        undoStack.append(snapshot)
    }

    private func normalizedSelection() -> NSRange { clamped(selection, in: text) }

    private func clamped(_ range: NSRange, in source: String) -> NSRange {
        let limit = (source as NSString).length
        let location = min(max(0, range.location), limit)
        return NSRange(location: location, length: min(max(0, range.length), limit - location))
    }

    private func wrap(_ prefix: String, _ suffix: String, placeholder: String) {
        let body = selectedText.isEmpty ? placeholder : selectedText
        let start = (prefix as NSString).length
        replaceSelection(prefix + body + suffix, selectedRange: NSRange(location: start, length: (body as NSString).length))
    }

    private func wrapBlock(_ opening: String, _ closing: String, placeholder: String) {
        let body = selectedText.isEmpty ? placeholder : selectedText
        replaceSelection("\(opening)\n\(body)\n\(closing)", selectedRange: NSRange(location: (opening as NSString).length + 1, length: (body as NSString).length))
    }

    private func insertSeparatedBlock(_ block: String) {
        let source = text as NSString
        let range = normalizedSelection()
        let before = source.substring(to: range.location)
        let after = source.substring(from: NSMaxRange(range))
        let leading = before.isEmpty || before.hasSuffix("\n\n") ? "" : before.hasSuffix("\n") ? "\n" : "\n\n"
        let trailing = after.isEmpty || after.hasPrefix("\n\n") ? "" : after.hasPrefix("\n") ? "\n" : "\n\n"
        replaceSelection(leading + block + trailing)
    }

    private func transformLines(_ transform: (Int, String) -> String) {
        let source = text as NSString
        let selected = normalizedSelection()
        let prefix = source.substring(to: selected.location) as NSString
        let previousNewline = prefix.range(of: "\n", options: .backwards)
        let start = previousNewline.location == NSNotFound ? 0 : NSMaxRange(previousNewline)
        var effectiveEnd = NSMaxRange(selected)
        if selected.length > 0 && source.substring(with: NSRange(location: effectiveEnd - 1, length: 1)) == "\n" { effectiveEnd -= 1 }
        let nextNewline = source.range(of: "\n", range: NSRange(location: effectiveEnd, length: source.length - effectiveEnd))
        let end = nextNewline.location == NSNotFound ? source.length : nextNewline.location
        let range = NSRange(location: start, length: end - start)
        let replacement = source.substring(with: range).components(separatedBy: "\n").enumerated().map(transform).joined(separator: "\n")
        replaceRange(range, with: replacement, selectedRange: NSRange(location: 0, length: (replacement as NSString).length))
    }
}

public enum MarkdownEditorMode: String, CaseIterable { case source, formatted, preview, split }

public struct MarkdownSlashCommandMatch {
    public let range: NSRange
    public let query: String
}

public enum MarkdownEditorCommand: Hashable {
    case paragraph, bold, italic, strikethrough, inlineCode
    case heading1, heading2, heading3, heading4, heading5, heading6
    case unorderedList, orderedList, taskList, blockquote, codeBlock
    case link, image, table, blockMath, mermaidDiagram, horizontalRule, wikilink

    var headingLevel: Int? {
        switch self {
        case .heading1: 1
        case .heading2: 2
        case .heading3: 3
        case .heading4: 4
        case .heading5: 5
        case .heading6: 6
        default: nil
        }
    }

    var toolbarTitle: String {
        switch self {
        case .paragraph: "Text"
        case .bold: "B"
        case .italic: "I"
        case .strikethrough: "Strike"
        case .inlineCode: "Inline Code"
        case .heading1: "H1"
        case .heading2: "H2"
        case .heading3: "H3"
        case .heading4: "H4"
        case .heading5: "H5"
        case .heading6: "H6"
        case .unorderedList: "List"
        case .orderedList: "Numbered"
        case .taskList: "Task"
        case .blockquote: "Quote"
        case .codeBlock: "Code"
        case .link: "Link"
        case .image: "Image"
        case .table: "Table"
        case .blockMath: "Math"
        case .mermaidDiagram: "Mermaid"
        case .horizontalRule: "Divider"
        case .wikilink: "Wiki"
        }
    }
}

/// Controls which built-in commands appear in the editor and can be selected.
public struct MarkdownEditorCapabilities {
    public static let all = Self()
    public static let defaultToolbarCommands: [MarkdownEditorCommand] = [
        .bold, .italic, .heading1, .unorderedList, .taskList,
        .codeBlock, .link, .table, .wikilink
    ]
    public let disabledCommands: Set<MarkdownEditorCommand>

    public init(disabledCommands: Set<MarkdownEditorCommand> = []) {
        self.disabledCommands = disabledCommands
    }

    public func supports(_ command: MarkdownEditorCommand) -> Bool {
        !disabledCommands.contains(command)
    }

    /// Preserves host order and drops commands unavailable to this editor.
    public func visibleToolbarCommands(_ configured: [MarkdownEditorCommand]? = nil,
                                       enableWikilinks: Bool = true) -> [MarkdownEditorCommand] {
        (configured ?? Self.defaultToolbarCommands).filter {
            supports($0) && ($0 != .wikilink || enableWikilinks)
        }
    }
}

/// A host command shown after built-in slash suggestions.
public struct MarkdownEditorSlashCommand {
    public let title: String
    public let searchText: String
    public let markdown: String?
    public let onSelected: ((String) async -> String?)?

    public init(title: String, searchText: String, markdown: String? = nil,
                onSelected: ((String) async -> String?)? = nil) {
        self.title = title
        self.searchText = searchText
        self.markdown = markdown
        self.onSelected = onSelected
    }
}
