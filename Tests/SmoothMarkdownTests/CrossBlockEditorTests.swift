import XCTest
@testable import SmoothMarkdown

@MainActor
final class CrossBlockEditorTests: XCTestCase {
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
