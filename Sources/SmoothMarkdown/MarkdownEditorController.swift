import Combine
import Foundation

/// Source-backed editing commands. Offsets use UTF-16, matching UITextView selections.
@MainActor
public final class MarkdownEditorController: ObservableObject {
    @Published public private(set) var text: String
    @Published public private(set) var selection: NSRange
    @Published public private(set) var savedText: String
    @Published public var mode: MarkdownEditorMode = .source

    private struct Snapshot {
        let text: String
        let selection: NSRange
    }
    private let historyLimit: Int
    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []
    private var transactionDepth = 0
    private var transactionBefore: Snapshot?

    public init(text: String = "", historyLimit: Int = 100) {
        self.text = text
        self.selection = NSRange(location: (text as NSString).length, length: 0)
        self.savedText = text
        self.historyLimit = max(0, historyLimit)
    }

    public var isDirty: Bool { text != savedText }
    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }
    public var selectedText: String { (text as NSString).substring(with: normalizedSelection()) }

    /// A source-preserving semantic snapshot for supported top-level blocks.
    public var semanticDocument: MarkdownDocument { MarkdownDocumentCodec().parse(text) }

    /// Applies one semantic body edit through the existing source undo history.
    @discardableResult
    public func replaceSemanticBlockContent(id: String, with content: String) -> Bool {
        let document = semanticDocument
        guard let block = document.blockById(id), let replacement = block.replacingContent(content) else { return false }
        let updated = document.replacingBlock(replacement).toMarkdown()
        guard updated != text else { return false }
        replaceRange(NSRange(location: 0, length: (text as NSString).length), with: updated, selectedRange: selection)
        return true
    }

    /// Applies one inline mark to a UTF-16 selection within an editable Blocks row.
    /// Returns the selection in the new block body, or nil for an unsupported edit.
    @discardableResult
    public func applySemanticInlineMark(id: String, selection: NSRange, mark: MarkdownInlineMark) -> NSRange? {
        let document = semanticDocument
        guard let block = document.blockById(id), let sourceRange = document.sourceRange(of: id) else { return nil }
        switch block.kind {
        case .paragraph, .heading: break
        case .fencedCode, .table, .list, .horizontalRule, .raw: return nil
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
        guard updated != text else { return false }
        replaceRange(NSRange(location: 0, length: (text as NSString).length), with: updated, selectedRange: selection)
        return true
    }

    /// Applies a semantic table operation by block ID through the source undo stack.
    @discardableResult
    public func updateSemanticTable(id: String, _ transform: (MarkdownSourceTable) -> MarkdownSourceTable) -> Bool {
        guard let updated = semanticDocument.updatingTable(id, transform)?.toMarkdown(), updated != text else { return false }
        replaceRange(NSRange(location: 0, length: (text as NSString).length), with: updated, selectedRange: selection)
        return true
    }

    /// Edits a supported list item through the same source history as other Blocks edits.
    @discardableResult
    public func updateSemanticList(id: String, _ transform: (MarkdownSourceList) -> MarkdownSourceList?) -> Bool {
        guard let updated = semanticDocument.updatingList(id, transform)?.toMarkdown(), updated != text else { return false }
        replaceRange(NSRange(location: 0, length: (text as NSString).length), with: updated, selectedRange: selection)
        return true
    }

    public func markSaved(_ saved: String? = nil) { savedText = saved ?? text }
    public func clearHistory() { undoStack.removeAll(); redoStack.removeAll() }

    public func updateFromInput(text nextText: String, selection nextSelection: NSRange) {
        if nextText != text { recordUndo(Snapshot(text: text, selection: selection)) }
        text = nextText
        selection = clamped(nextSelection, in: nextText)
    }

    public func setSelection(_ range: NSRange) { selection = clamped(range, in: text) }

    @discardableResult
    public func undo() -> Bool {
        guard let previous = undoStack.popLast() else { return false }
        redoStack.append(Snapshot(text: text, selection: selection))
        text = previous.text
        selection = previous.selection
        return true
    }

    @discardableResult
    public func redo() -> Bool {
        guard let next = redoStack.popLast() else { return false }
        pushUndo(Snapshot(text: text, selection: selection))
        text = next.text
        selection = next.selection
        return true
    }

    public func transaction<T>(_ body: () throws -> T) rethrows -> T {
        if transactionDepth == 0 { transactionBefore = Snapshot(text: text, selection: selection) }
        transactionDepth += 1
        defer {
            transactionDepth -= 1
            if transactionDepth == 0 {
                if let before = transactionBefore, before.text != text {
                    pushUndo(before)
                    redoStack.removeAll()
                }
                transactionBefore = nil
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

    private func updateValue(_ next: String, selection nextSelection: NSRange) {
        if next != text { recordUndo(Snapshot(text: text, selection: selection)) }
        text = next
        selection = nextSelection
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

public enum MarkdownEditorCommand {
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
}
