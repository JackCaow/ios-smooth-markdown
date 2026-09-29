import XCTest
@testable import SmoothMarkdown

@MainActor
final class CrossBlockEditorTests: XCTestCase {
    private func range(_ first: String, _ start: Int, _ last: String, _ end: Int)
        -> MarkdownSemanticTextSelection {
        .init(anchor: .init(blockID: first, offset: start),
              focus: .init(blockID: last, offset: end))
    }

    func testCharacterRangeCopiesExactSourceAndReplacesWithOneUndoStep() {
        let original = "Lead\r\n\r\n# One 😀\r\n\r\nSecond\r\n\r\nKeep\r\n"
        let controller = MarkdownEditorController(text: original)
        let selected = range("block-1", 4, "block-2", 3)
        XCTAssertEqual(controller.copySemanticTextRange(selected), "😀\r\n\r\nSec")
        XCTAssertTrue(controller.canReplaceSemanticTextRange(selected, with: "X"))
        XCTAssertTrue(controller.replaceSemanticTextRange(selected, with: "X"))
        XCTAssertEqual(controller.text, "Lead\r\n\r\n# One Xond\r\n\r\nKeep\r\n")
        XCTAssertEqual(controller.selection, NSRange(location: ("Lead\r\n\r\n# One X" as NSString).length, length: 0))
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, original)
        XCTAssertFalse(controller.canUndo)
        XCTAssertTrue(controller.redo())
        XCTAssertEqual(controller.text, "Lead\r\n\r\n# One Xond\r\n\r\nKeep\r\n")
    }

    func testReverseCharacterRangeAndEmojiBoundary() {
        let original = "Hello 😀\n\nworld!\n\nKeep"
        let controller = MarkdownEditorController(text: original)
        let reversed = range("block-1", 5, "block-0", 4)
        XCTAssertEqual(controller.copySemanticTextRange(reversed), "o 😀\n\nworld")
        XCTAssertTrue(controller.deleteSemanticTextRange(reversed))
        XCTAssertEqual(controller.text, "Hell!\n\nKeep")
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, original)
        let surrogateSplit = range("block-0", 7, "block-1", 1)
        XCTAssertNil(controller.copySemanticTextRange(surrogateSplit))
        XCTAssertFalse(controller.deleteSemanticTextRange(surrogateSplit))
        XCTAssertEqual(controller.text, original)
    }

    func testNativeDragHighlightsExactUTF16FragmentsInBothDirections() {
        let controller = MarkdownEditorController(text: "First 😀\n\n# Middle\n\nLast line")
        let selected = range("block-2", 4, "block-0", 6)
        let expected: [String: NSRange] = [
            "block-0": NSRange(location: 6, length: 2),
            "block-1": NSRange(location: 0, length: 6),
            "block-2": NSRange(location: 0, length: 4),
        ]
        XCTAssertEqual(controller.semanticTextHighlightRanges(selected), expected)
        XCTAssertEqual(controller.copySemanticTextRange(selected), "😀\n\n# Middle\n\nLast")
        XCTAssertEqual(controller.semanticTextHighlightRanges(range("block-0", 6, "block-2", 4)), expected)
        XCTAssertNil(controller.semanticTextHighlightRanges(range("block-0", 7, "block-1", 1)),
                     "A drag endpoint must never split an emoji surrogate pair")
    }

    func testNativeDragDoesNotHighlightUnsupportedBlocks() {
        let controller = MarkdownEditorController(text: "Before\n\n- item\n\nAfter")
        XCTAssertNil(controller.semanticTextHighlightRanges(range("block-0", 2, "block-2", 2)))
    }

    func testCharacterCopyIncludesOnlySelectedHeadingMarkers() {
        let controller = MarkdownEditorController(text: "# Start\n\n# End\n\nTail")
        XCTAssertEqual(controller.copySemanticTextRange(range("block-0", 0, "block-1", 2)),
                       "# Start\n\n# En")
        XCTAssertEqual(controller.copySemanticTextRange(range("block-0", 3, "block-1", 0)),
                       "rt\n\n")
    }

    func testCharacterRangeRejectsStructuralAndUnsupportedEdits() {
        let controller = MarkdownEditorController(text: "Before\n\n# Heading\n\nAfter")
        let selected = range("block-0", 3, "block-1", 2)
        XCTAssertFalse(controller.replaceSemanticTextRange(selected, with: "\n\n- item\n\n"))
        XCTAssertEqual(controller.text, "Before\n\n# Heading\n\nAfter")
        XCTAssertFalse(controller.canUndo)

        let list = MarkdownEditorController(text: "Before\n\n- item\n\nAfter")
        let crossingList = range("block-0", 2, "block-2", 2)
        XCTAssertNil(list.copySemanticTextRange(crossingList))
        XCTAssertFalse(list.deleteSemanticTextRange(crossingList))
        XCTAssertFalse(list.canUndo)
        XCTAssertNil(list.copySemanticTextRange(range("block-0", 2, "missing", 0)))
    }

    func testTextRangeFormatsPartialHeadingAndParagraphWithoutChangingSourceTrivia() {
        let original = "Lead\r\n\r\n# One 😀\r\n\r\nSecond text\r\n\r\nTail"
        let controller = MarkdownEditorController(text: original)
        let selected = range("block-2", 6, "block-1", 4)
        XCTAssertTrue(controller.applySemanticInlineMarkToTextRange(selected, mark: .bold))
        XCTAssertEqual(controller.text,
                       "Lead\r\n\r\n# One **😀**\r\n\r\n**Second** text\r\n\r\nTail")
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, original)
        XCTAssertFalse(controller.canUndo)
    }

    func testTextRangeFormatsEveryTouchedPlainTextRowInOneUndoStep() {
        let original = "Alpha one\n\n# Middle\n\nOmega last"
        let controller = MarkdownEditorController(text: original)
        XCTAssertTrue(controller.applySemanticInlineMarkToTextRange(
            range("block-0", 6, "block-2", 5), mark: .italic))
        XCTAssertEqual(controller.text, "Alpha *one*\n\n# *Middle*\n\n*Omega* last")
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, original)
        XCTAssertFalse(controller.canUndo)
    }

    func testTextRangeRejectsNestedSyntaxAndUnsafeLinkAtomically() {
        let original = "Before\n\n# **nested**\n\nAfter"
        let controller = MarkdownEditorController(text: original)
        let selected = range("block-0", 2, "block-2", 3)
        XCTAssertFalse(controller.applySemanticInlineMarkToTextRange(selected, mark: .bold))
        XCTAssertEqual(controller.text, original)
        XCTAssertFalse(controller.canUndo)

        let plain = MarkdownEditorController(text: "First\n\nSecond")
        XCTAssertFalse(plain.applySemanticInlineMarkToTextRange(
            range("block-0", 0, "block-1", 6), mark: .link(destination: "javascript:alert(1)")))
        XCTAssertEqual(plain.text, "First\n\nSecond")
        XCTAssertFalse(plain.canUndo)
    }

    func testTextRangeItalicPreservesExistingBoldAcrossWholeHeadingAndParagraph() {
        let original = "# First **bold** end\n\nSecond [link](https://example.com) end\n\nTail"
        let controller = MarkdownEditorController(text: original)
        XCTAssertTrue(controller.applySemanticInlineMarkToTextRange(
            range("block-0", 0, "block-1",
                  ("Second [link](https://example.com) end" as NSString).length), mark: .italic))
        XCTAssertEqual(controller.text, "# *First **bold** end*\n\n"
                       + "*Second [link](https://example.com) end*\n\nTail")
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, original)
        XCTAssertFalse(controller.canUndo)
    }

    func testCopiesExactMarkdownAndDeletesRangeWithOneUndoStep() {
        let original = "# One 😀\r\n\r\nSecond\r\n\r\nThird\r\n"
        let controller = MarkdownEditorController(text: original)
        XCTAssertEqual(controller.copySemanticBlockRange(from: "block-1", to: "block-0"),
                       "# One 😀\r\n\r\nSecond\r\n")
        XCTAssertTrue(controller.canDeleteSemanticBlockRange(from: "block-0", to: "block-1"))
        XCTAssertTrue(controller.deleteSemanticBlockRange(from: "block-1", to: "block-0"))
        XCTAssertEqual(controller.text, "Third\r\n")
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, original)
        XCTAssertFalse(controller.canUndo)
        XCTAssertTrue(controller.redo())
        XCTAssertEqual(controller.text, "Third\r\n")
    }

    func testDeletionKeepsUntouchedOuterBlocksAndRejectsMerge() {
        let original = "Before\r\n\r\n# Heading\r\n\r\n---\r\n\r\nAfter"
        let controller = MarkdownEditorController(text: original)
        XCTAssertTrue(controller.deleteSemanticBlockRange(from: "block-1", to: "block-2"))
        XCTAssertEqual(controller.text, "Before\r\n\r\nAfter")
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, original)

        let unsafe = MarkdownEditorController(text: "Before\n```\nx\n```\n# Heading\nAfter")
        XCTAssertEqual(unsafe.semanticDocument.blocks.count, 4)
        XCTAssertFalse(unsafe.canDeleteSemanticBlockRange(from: "block-1", to: "block-2"))
        XCTAssertFalse(unsafe.deleteSemanticBlockRange(from: "block-1", to: "block-2"))
        XCTAssertEqual(unsafe.text, "Before\n```\nx\n```\n# Heading\nAfter")
        XCTAssertFalse(unsafe.canUndo)
    }

    func testComplexBlocksCanBeCopiedButNotDeletedAndInvalidRangeDoesNothing() {
        let original = "Before\n\n- item\n\nAfter"
        let controller = MarkdownEditorController(text: original)
        XCTAssertEqual(controller.copySemanticBlockRange(from: "block-0", to: "block-1"),
                       "Before\n\n- item\n")
        XCTAssertFalse(controller.canDeleteSemanticBlockRange(from: "block-0", to: "block-1"))
        XCTAssertFalse(controller.deleteSemanticBlockRange(from: "block-0", to: "block-1"))
        XCTAssertNil(controller.copySemanticBlockRange(from: "block-0", to: "missing"))
        XCTAssertNil(controller.copySemanticBlockRange(from: "block-0", to: "block-0"))
        XCTAssertEqual(controller.text, original)
        XCTAssertFalse(controller.canUndo)
    }
}
