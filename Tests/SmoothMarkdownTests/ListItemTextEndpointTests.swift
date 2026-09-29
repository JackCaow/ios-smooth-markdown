import Foundation
import XCTest
@testable import SmoothMarkdown

@MainActor
final class ListItemTextEndpointTests: XCTestCase {
    private func position(_ block: String, _ offset: Int, item: Int? = nil) -> MarkdownSemanticTextPosition {
        .init(blockID: block, offset: offset, listItemIndex: item)
    }

    private func selection(_ source: String, _ anchor: MarkdownSemanticTextPosition,
                           _ focus: MarkdownSemanticTextPosition) -> MarkdownSemanticTextSelection {
        .init(anchor: anchor, focus: focus, source: source)
    }

    func testPartialRootItemsCopyDeleteAndUndoInEitherDirection() {
        let original = "Lead\r\n\r\n- BeforeX\r\n- middle\r\n- YAfter\r\n\r\nTail"
        let controller = MarkdownEditorController(text: original)
        let forward = selection(original, position("block-1", 6, item: 0),
                                position("block-1", 1, item: 2))
        let backward = selection(original, forward.focus, forward.anchor)
        XCTAssertEqual(controller.copySemanticTextRange(forward), "- X\r\n- middle\r\n- Y")
        XCTAssertEqual(controller.copySemanticTextRange(backward), controller.copySemanticTextRange(forward))
        XCTAssertEqual(controller.semanticListItemHighlightRanges(backward)?["block-1"], [
            0: NSRange(location: 6, length: 1),
            1: NSRange(location: 0, length: 6),
            2: NSRange(location: 0, length: 1),
        ])
        XCTAssertTrue(controller.canReplaceSemanticTextRange(forward))
        XCTAssertTrue(controller.deleteSemanticTextRange(backward))
        XCTAssertEqual(controller.text, "Lead\r\n\r\n- BeforeAfter\r\n\r\nTail")
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, original)
        XCTAssertFalse(controller.canUndo)
        XCTAssertTrue(controller.redo())
        XCTAssertEqual(controller.text, "Lead\r\n\r\n- BeforeAfter\r\n\r\nTail")
    }

    func testReplaceWithinItemAndAcrossListToProsePreservesOtherSource() {
        let original = "Keep\n\n- Stay\n- BeforeX\n\nAfterY\n\nTail"
        let controller = MarkdownEditorController(text: original)
        let selected = selection(original, position("block-1", 6, item: 1), position("block-2", 2))
        XCTAssertEqual(controller.copySemanticTextRange(selected), "- X\n\nAf")
        XCTAssertTrue(controller.replaceSemanticTextRange(selected, with: "Q"))
        XCTAssertEqual(controller.text, "Keep\n\n- Stay\n- BeforeQterY\n\nTail")
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, original)

        let within = selection(original, position("block-1", 1, item: 0), position("block-1", 3, item: 0))
        XCTAssertEqual(controller.copySemanticTextRange(within), "- ta")
        XCTAssertTrue(controller.replaceSemanticTextRange(within, with: "XY"))
        XCTAssertEqual(controller.text, "Keep\n\n- SXYy\n- BeforeX\n\nAfterY\n\nTail")
    }

    func testProseToFinalListItemCanMergeWithoutChangingFollowingBlock() {
        let original = "BeforeX\n\n- YAfter\n\nKeep"
        let controller = MarkdownEditorController(text: original)
        let selected = selection(original, position("block-0", 6), position("block-1", 1, item: 0))
        XCTAssertEqual(controller.copySemanticTextRange(selected), "X\n\n- Y")
        XCTAssertTrue(controller.deleteSemanticTextRange(selected))
        XCTAssertEqual(controller.text, "BeforeAfter\n\nKeep")
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, original)
    }

    func testTaskMarkerAndSpacingRemainExact() {
        let original = "- [x] BeforeX\n- YAfter\n\nKeep"
        let controller = MarkdownEditorController(text: original)
        let selected = selection(original, position("block-0", 6, item: 0),
                                 position("block-0", 1, item: 1))
        XCTAssertEqual(controller.copySemanticTextRange(selected), "- [x] X\n- Y")
        XCTAssertTrue(controller.deleteSemanticTextRange(selected))
        XCTAssertEqual(controller.text, "- [x] BeforeAfter\n\nKeep")
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, original)
    }

    func testRejectsStaleSurrogateNestedAndContinuationEndpointsAtomically() {
        let original = "- 😀 First\n- Last\n\nKeep"
        let controller = MarkdownEditorController(text: original)
        let split = selection(original, position("block-0", 1, item: 0), position("block-0", 2, item: 1))
        XCTAssertNil(controller.copySemanticTextRange(split))
        XCTAssertFalse(controller.deleteSemanticTextRange(split))
        let stale = selection(original, position("block-0", 3, item: 0), position("block-1", 2))
        controller.replaceRange(NSRange(location: 0, length: 0), with: "Intro\n\n")
        let changed = controller.text
        XCTAssertNil(controller.copySemanticTextRange(stale))
        XCTAssertFalse(controller.replaceSemanticTextRange(stale, with: "X"))
        XCTAssertEqual(controller.text, changed)
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, original)

        for unsupported in ["- Parent\n  - Child\n- Last\n\nKeep",
                            "- Parent\n  continuation\n- Last\n\nKeep"] {
            let nested = MarkdownEditorController(text: unsupported)
            let range = selection(unsupported, position("block-0", 2, item: 0), position("block-1", 2))
            XCTAssertNil(nested.copySemanticTextRange(range))
            XCTAssertFalse(nested.deleteSemanticTextRange(range))
            XCTAssertEqual(nested.text, unsupported)
            XCTAssertFalse(nested.canUndo)
        }
    }

    func testRejectsMultilineReplacementWithoutCreatingHistory() {
        let original = "- FirstX\n- YLast"
        let controller = MarkdownEditorController(text: original)
        let selected = selection(original, position("block-0", 5, item: 0),
                                 position("block-0", 1, item: 1))
        XCTAssertFalse(controller.replaceSemanticTextRange(selected, with: "\n\n# Heading"))
        XCTAssertEqual(controller.text, original)
        XCTAssertFalse(controller.canUndo)
    }
}
