#if os(iOS)
import Foundation
import UIKit

/// Drives selection in a selectable ``SmoothMarkdownView`` or ``StreamMarkdownView``.
///
/// The controller attaches only while the reader uses its complete, native
/// TextKit document host. A reader rendered through separate legacy blocks
/// cannot offer one document-wide selection range, so `isAttached` is false.
/// Keep one controller per reader view.
@available(iOS 17.0, *)
public final class SmoothSelectionController {
    private weak var textView: ReaderDocumentSelectionTextView?

    public init() {}

    /// Whether a complete native selection host is currently mounted.
    public var isAttached: Bool { textView?.projection != nil }

    /// The current UTF-16 range in the visible TextKit document.
    public var selectedRange: NSRange? {
        guard let view = textView, view.projection != nil,
              view.selectedRange.length > 0 else { return nil }
        return view.selectedRange
    }

    /// Semantic plain text for the native selection, including text represented
    /// by a projected attachment. `nil` means there is no selection.
    public var selectedText: String? {
        guard let view = textView, let range = selectedRange else { return nil }
        return view.projection?.copiedText(in: range)
    }

    /// Selects the complete visible document. Returns false without a host or text.
    @discardableResult
    public func selectAll() -> Bool {
        guard let view = textView, view.projection != nil,
              view.textStorage.length > 0 else { return false }
        return view.selectAllReaderText()
    }

    /// Selects the native word at a point in screen coordinates.
    @discardableResult
    public func selectWordAt(_ screenPoint: CGPoint) -> Bool {
        guard let view = textView, let position = position(at: screenPoint, in: view) else { return false }
        let tokenizer = view.tokenizer
        guard let word = tokenizer.rangeEnclosingPosition(position, with: .word,
                    inDirection: UITextDirection.storage(.forward)) ??
                tokenizer.rangeEnclosingPosition(position, with: .word,
                    inDirection: UITextDirection.storage(.backward)) else { return false }
        let start = view.offset(from: view.beginningOfDocument, to: word.start)
        let end = view.offset(from: view.beginningOfDocument, to: word.end)
        return select(NSRange(location: start, length: end - start), in: view)
    }

    /// Selects the paragraph at a point in screen coordinates. A trailing line
    /// break is excluded, matching the reader's native long-press selection.
    @discardableResult
    public func selectParagraphAt(_ screenPoint: CGPoint) -> Bool {
        guard let view = textView, let position = position(at: screenPoint, in: view),
              view.textStorage.length > 0 else { return false }
        let source = view.textStorage.string as NSString
        let offset = view.offset(from: view.beginningOfDocument, to: position)
        let index = min(max(0, offset), source.length - 1)
        var paragraph = source.paragraphRange(for: NSRange(location: index, length: 0))
        while paragraph.length > 0 {
            let last = source.character(at: NSMaxRange(paragraph) - 1)
            guard last == 10 || last == 13 else { break }
            paragraph.length -= 1
        }
        return select(paragraph, in: view)
    }

    /// Clears the current range and dismisses native selection focus.
    public func clearSelection() {
        guard let view = textView, view.projection != nil else { return }
        view.selectedRange = NSRange(location: min(view.selectedRange.location,
                                                   view.textStorage.length), length: 0)
        view.resignFirstResponder()
    }

    /// Copies the semantic selection with the same behavior as the reader's
    /// native Copy action. Returns false when nothing is selected.
    @discardableResult
    public func copySelection() -> Bool {
        guard let view = textView, selectedText?.isEmpty == false else { return false }
        view.copy(nil)
        return true
    }

    func attach(_ view: ReaderDocumentSelectionTextView) { textView = view }

    func detach(_ view: ReaderDocumentSelectionTextView) {
        if textView === view { textView = nil }
    }

    private func position(at screenPoint: CGPoint, in view: ReaderDocumentSelectionTextView) -> UITextPosition? {
        guard view.projection != nil, view.textStorage.length > 0,
              let window = view.window else { return nil }
        let windowPoint = window.convert(screenPoint, from: window.screen.coordinateSpace)
        let local = view.convert(windowPoint, from: window)
        guard view.bounds.contains(local) else { return nil }
        return view.closestPosition(to: local)
    }

    private func select(_ range: NSRange, in view: ReaderDocumentSelectionTextView) -> Bool {
        guard range.location != NSNotFound, range.length > 0,
              NSMaxRange(range) <= view.textStorage.length else { return false }
        view.becomeFirstResponder()
        view.selectedRange = range
        view.scrollRangeToVisible(range)
        return true
    }
}
#else
/// Selection control requires the native iOS reader host.
public final class SmoothSelectionController {
    public init() {}
    public var isAttached: Bool { false }
}
#endif
