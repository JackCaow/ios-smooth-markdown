import Combine
import Foundation

/// The focused empty paragraph created when Return exits a root list item.
/// Its draft is also written to `text`; this state only keeps the Blocks field alive while typing.
struct PendingListParagraph: Equatable {
    let sourceOffset: Int
    let draft: String
    let insertedTerminator: String
}

/// A UTF-16 offset in the editable body of a formatted paragraph or heading.
/// Markdown markers are visible in that body, as they are in the formatted editor.
public struct MarkdownSemanticTextPosition: Equatable {
    public let blockID: String
    public let offset: Int

    public init(blockID: String, offset: Int) {
        self.blockID = blockID
        self.offset = offset
    }
}

/// Two character endpoints in the formatted document; either direction is valid.
public struct MarkdownSemanticTextSelection: Equatable {
    public let anchor: MarkdownSemanticTextPosition
    public let focus: MarkdownSemanticTextPosition

    public init(anchor: MarkdownSemanticTextPosition, focus: MarkdownSemanticTextPosition) {
        self.anchor = anchor
        self.focus = focus
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

    /// Complex source-only, list, and table blocks stay copyable but are not deleted yet.
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
        for block in document.blocks[range] {
            switch block.kind {
            case .paragraph, .heading, .fencedCode, .horizontalRule: break
            case .list, .table, .plugin, .raw: return nil
            }
        }
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
              zip(reparsed.blocks, kept).allSatisfy({ $0.0.kind == $0.1.kind && $0.0.source == $0.1.source }) else {
            return nil
        }
        return updated == text ? nil : updated
    }

    private struct ResolvedSemanticTextSelection {
        let firstIndex: Int
        let lastIndex: Int
        let startOffset: Int
        let endOffset: Int
        let startSourceOffset: Int
        let endSourceOffset: Int
    }

    /// Copies the selected text fragments as Markdown, preserving their exact
    /// source markers and intervening whitespace without normalizing them.
    public func copySemanticTextRange(_ selection: MarkdownSemanticTextSelection) -> String? {
        guard let resolved = resolveSemanticTextSelection(selection) else { return nil }
        let document = semanticDocument
        let first = document.blocks[resolved.firstIndex]
        let last = document.blocks[resolved.lastIndex]
        let start = resolved.startOffset == 0 && isHeading(first) ?
            document.sourceRange(of: first.id)!.location : resolved.startSourceOffset
        let end = resolved.endOffset == 0 && isHeading(last) ?
            document.sourceRange(of: last.id)!.location : resolved.endSourceOffset
        let range = NSRange(location: start, length: end - start)
        return (text as NSString).substring(with: range)
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

    private func resolveSemanticTextSelection(_ selection: MarkdownSemanticTextSelection)
        -> ResolvedSemanticTextSelection? {
        let document = semanticDocument
        guard let anchorIndex = document.blocks.firstIndex(where: { $0.id == selection.anchor.blockID }),
              let focusIndex = document.blocks.firstIndex(where: { $0.id == selection.focus.blockID }),
              anchorIndex != focusIndex else { return nil }
        let forward = anchorIndex < focusIndex
        let firstIndex = min(anchorIndex, focusIndex)
        let lastIndex = max(anchorIndex, focusIndex)
        let start = forward ? selection.anchor : selection.focus
        let end = forward ? selection.focus : selection.anchor
        for block in document.blocks[firstIndex...lastIndex] {
            switch block.kind {
            case .paragraph, .heading: break
            case .fencedCode, .table, .list, .horizontalRule, .plugin, .raw: return nil
            }
        }
        func sourceOffset(_ position: MarkdownSemanticTextPosition) -> Int? {
            guard let block = document.blockById(position.blockID),
                  let range = document.sourceRange(of: position.blockID),
                  position.offset >= 0, position.offset <= (block.plainText as NSString).length,
                  Range(NSRange(location: position.offset, length: 0), in: block.plainText) != nil else {
                return nil
            }
            let ending = block.source.hasSuffix("\r\n") ? 2 : block.source.hasSuffix("\n") ? 1 : 0
            let bodyStart = (block.source as NSString).length - (block.plainText as NSString).length - ending
            guard bodyStart >= 0,
                  (block.source as NSString).substring(with: NSRange(location: bodyStart,
                                                                     length: (block.plainText as NSString).length)) == block.plainText else {
                return nil
            }
            let absolute = range.location + bodyStart + position.offset
            guard isValidSourceRange(NSRange(location: absolute, length: 0)) else { return nil }
            return absolute
        }
        guard let startSourceOffset = sourceOffset(start), let endSourceOffset = sourceOffset(end),
              startSourceOffset < endSourceOffset else { return nil }
        return .init(firstIndex: firstIndex, lastIndex: lastIndex,
                     startOffset: start.offset, endOffset: end.offset,
                     startSourceOffset: startSourceOffset, endSourceOffset: endSourceOffset)
    }

    private func replacementForSemanticTextRange(_ selection: MarkdownSemanticTextSelection,
                                                  with replacement: String) -> (markdown: String, caret: Int)? {
        guard let resolved = resolveSemanticTextSelection(selection) else { return nil }
        let original = semanticDocument
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
        let first = original.blocks[resolved.firstIndex]
        guard merged.leadingTrivia == first.leadingTrivia else { return nil }
        switch (first.kind, merged.kind) {
        case (.paragraph, .paragraph): break
        case let (.heading(oldLevel, _), .heading(newLevel, _)) where oldLevel == newLevel: break
        default: return nil
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

    /// Applies one semantic body edit through the existing source undo history.
    @discardableResult
    public func replaceSemanticBlockContent(id: String, with content: String) -> Bool {
        let document = semanticDocument
        guard let block = document.blockById(id), let replacement = block.replacingContent(content) else { return false }
        let updated = document.replacingBlock(replacement).toMarkdown()
        return replaceSemanticMarkdown(updated)
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
            let itemOffset = list.items[..<index].reduce(0) { $0 + ($1.source as NSString).length }
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

    public func updateFromInput(text nextText: String, selection nextSelection: NSRange) {
        let changed = nextText != text
        if changed { recordUndo(snapshot()) }
        text = nextText
        selection = clamped(nextSelection, in: nextText)
        if changed { pendingListParagraph = nil }
    }

    public func setSelection(_ range: NSRange) { selection = clamped(range, in: text) }

    @discardableResult
    public func undo() -> Bool {
        guard let previous = undoStack.popLast() else { return false }
        redoStack.append(snapshot())
        text = previous.text
        selection = previous.selection
        pendingListParagraph = previous.pendingListParagraph
        return true
    }

    @discardableResult
    public func redo() -> Bool {
        guard let next = redoStack.popLast() else { return false }
        pushUndo(snapshot())
        text = next.text
        selection = next.selection
        pendingListParagraph = next.pendingListParagraph
        return true
    }

    public func transaction<T>(_ body: () throws -> T) rethrows -> T {
        if transactionDepth == 0 { transactionBefore = snapshot() }
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
        if next != text { recordUndo(snapshot()) }
        text = next
        selection = nextSelection
        pendingListParagraph = nil
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
