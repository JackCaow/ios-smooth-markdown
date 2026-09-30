import Foundation
import XCTest
@testable import SmoothMarkdown

@MainActor
final class ListItemTextEndpointTests: XCTestCase {
    private func position(_ block: String, _ offset: Int, item: Int? = nil,
                          continuation: Int? = nil, trailing: Int? = nil) -> MarkdownSemanticTextPosition {
        .init(blockID: block, offset: offset, listItemIndex: item,
              listContinuationIndex: continuation, listTrailingIndex: trailing)
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

    func testRejectsStaleAndSurrogateEndpointsAtomicallyButCopiesComplexListSource() {
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

        for complex in ["- Parent\n  - Child\n- Last\n\nKeep",
                        "- Parent\n  continuation\n- Last\n\nKeep"] {
            let nested = MarkdownEditorController(text: complex)
            let range = selection(complex, position("block-0", 2, item: 0), position("block-1", 2))
            XCTAssertEqual(nested.copySemanticTextRange(range),
                           "- rent" + (complex as NSString).substring(with: NSRange(
                            location: ("- Parent" as NSString).length,
                            length: (complex as NSString).length - ("- Parent" as NSString).length - 2)))
            XCTAssertFalse(nested.deleteSemanticTextRange(range))
            XCTAssertEqual(nested.text, complex)
            XCTAssertFalse(nested.canUndo)
        }
    }

    func testNestedItemPartialCopyReplaceAndOneUndoPreserveAllOtherLines() {
        let original = "# Title\r\n\r\n- Parent\r\n  + Child **bold** 😀\r\n- Sibling\r\n\r\nTail"
        let controller = MarkdownEditorController(text: original)
        let forward = selection(original, position("block-1", 8, item: 1),
                                position("block-1", 12, item: 1))
        let backward = selection(original, forward.focus, forward.anchor)
        XCTAssertEqual(controller.copySemanticTextRange(forward), "  + bold")
        XCTAssertEqual(controller.copySemanticTextRange(backward), controller.copySemanticTextRange(forward))
        XCTAssertEqual(controller.semanticListItemHighlightRanges(forward)?["block-1"]?[1],
                       NSRange(location: 8, length: 4))
        XCTAssertTrue(controller.replaceSemanticTextRange(backward, with: "bright"))
        XCTAssertEqual(controller.text,
                       "# Title\r\n\r\n- Parent\r\n  + Child **bright** 😀\r\n- Sibling\r\n\r\nTail")
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, original)
        XCTAssertFalse(controller.canUndo)
        XCTAssertTrue(controller.redo())
    }

    func testContinuationAndDeferredParentParagraphCharacterEndpoints() {
        let original = "- Before \r\n  - Child\r\n    line **bold** 😀\r\n\r\n   after **bold**\r\n- Keep"
        let controller = MarkdownEditorController(text: original)
        let continuation = selection(original,
            position("block-0", 7, item: 1, continuation: 0),
            position("block-0", 11, item: 1, continuation: 0))
        XCTAssertEqual(controller.copySemanticTextRange(continuation), "    bold")
        XCTAssertEqual(controller.semanticListLineHighlightRanges(continuation)?["block-0"]?
            .continuations[1]?[0], NSRange(location: 7, length: 4))
        XCTAssertTrue(controller.deleteSemanticTextRange(continuation))
        XCTAssertEqual(controller.text, original.replacingOccurrences(of: "line **bold**", with: "line ****"))
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, original)

        let trailing = selection(original, position("block-0", 8, item: 0, trailing: 0),
                                 position("block-0", 12, item: 0, trailing: 0))
        XCTAssertEqual(controller.copySemanticTextRange(trailing), "   bold")
        XCTAssertEqual(controller.semanticListLineHighlightRanges(trailing)?["block-0"]?
            .trailing[0]?[0], NSRange(location: 8, length: 4))
        XCTAssertTrue(controller.replaceSemanticTextRange(trailing, with: "strong"))
        XCTAssertEqual(controller.text, original.replacingOccurrences(of: "after **bold**", with: "after **strong**"))
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, original)
    }

    func testNestedAndContinuationRejectHalfEmojiStructuralPasteAndStaleSnapshot() {
        let original = "- Parent\r\n  - 😀 Child\r\n    cont 😀ent\r\n- Keep"
        let controller = MarkdownEditorController(text: original)
        let halfEmoji = selection(original, position("block-0", 1, item: 1),
                                  position("block-0", 3, item: 1))
        XCTAssertNil(controller.copySemanticTextRange(halfEmoji))
        XCTAssertFalse(controller.deleteSemanticTextRange(halfEmoji))
        let continuation = selection(original, position("block-0", 5, item: 1, continuation: 0),
                                     position("block-0", 8, item: 1, continuation: 0))
        XCTAssertFalse(controller.replaceSemanticTextRange(continuation, with: "\r\n# Heading"))
        XCTAssertEqual(controller.text, original)
        XCTAssertFalse(controller.canUndo)
        controller.replaceRange(NSRange(location: 0, length: 0), with: "Lead\r\n\r\n")
        let changed = controller.text
        XCTAssertNil(controller.copySemanticTextRange(continuation))
        XCTAssertFalse(controller.deleteSemanticTextRange(continuation))
        XCTAssertEqual(controller.text, changed)
    }

    func testNestedSiblingSelectionMatchesFlutterStandaloneCopyAndPreservesParentOnDelete() {
        let original = "- Outer\r\n  - Alpha\r\n  - Beta\r\n  - Gamma\r\n- Keep"
        let controller = MarkdownEditorController(text: original)
        let selected = MarkdownSemanticListItemSelection(blockID: "block-0", anchorIndex: 2, focusIndex: 1)
        XCTAssertEqual(controller.copySemanticListItemRange(selected), "- Alpha\r\n- Beta")
        XCTAssertTrue(controller.deleteSemanticListItemRange(selected))
        XCTAssertEqual(controller.text, "- Outer\r\n  - Gamma\r\n- Keep")
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, original)
        XCTAssertFalse(controller.canUndo)
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
