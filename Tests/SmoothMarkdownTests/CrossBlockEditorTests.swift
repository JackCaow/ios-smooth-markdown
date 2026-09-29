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
