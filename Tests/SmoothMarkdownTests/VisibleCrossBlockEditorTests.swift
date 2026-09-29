import Foundation
import XCTest
@testable import SmoothMarkdown

@MainActor
final class VisibleCrossBlockEditorTests: XCTestCase {
    private func selection(_ source: String, _ startID: String, _ start: Int,
                           _ endID: String, _ end: Int) -> MarkdownVisibleTextSelection {
        .init(source: source,
              anchor: .init(blockID: startID, offset: start),
              focus: .init(blockID: endID, offset: end))
    }

    func testCopiesRenderedSelectionWithBalancedBoldLinkAndExactCRLFTrivia() {
        let original = "Lead\r\n\r\n# **Alpha** end\r\n\r\n[Beta](https://example.com) tail\r\n\r\nKeep"
        let controller = MarkdownEditorController(text: original)
        let selected = selection(original, "block-1", 2, "block-2", 2)
        let reverse = MarkdownVisibleTextSelection(source: original,
                                                   anchor: selected.focus, focus: selected.anchor)
        XCTAssertEqual(controller.copyVisibleTextRange(selected),
                       "**pha** end\r\n\r\n[Be](https://example.com)")
        XCTAssertEqual(controller.copyVisibleTextRange(reverse), controller.copyVisibleTextRange(selected))
        XCTAssertEqual(controller.text, original)
        XCTAssertFalse(controller.canUndo)
    }

    func testDeletesAcrossMarkedHeadingAndParagraphAsOneUndoStep() {
        let original = "Lead\r\n\r\n# **Alpha** end\r\n\r\n[Beta](https://example.com) tail\r\n\r\nKeep"
        let controller = MarkdownEditorController(text: original)
        let forward = selection(original, "block-1", 2, "block-2", 2)
        XCTAssertTrue(controller.canReplaceVisibleTextRange(forward))
        XCTAssertTrue(controller.deleteVisibleTextRange(forward))
        XCTAssertEqual(controller.text,
                       "Lead\r\n\r\n# **Al**[ta](https://example.com) tail\r\n\r\nKeep")
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, original)
        XCTAssertFalse(controller.canUndo)
        XCTAssertTrue(controller.redo())
        XCTAssertEqual(controller.text,
                       "Lead\r\n\r\n# **Al**[ta](https://example.com) tail\r\n\r\nKeep")
    }

    func testReverseSelectionReplacesPlainProseAndKeepsNeighborSource() {
        let original = "Before\n\nAlpha 😀\n\nBeta\n\nAfter"
        let controller = MarkdownEditorController(text: original)
        let reverse = selection(original, "block-2", 2, "block-1", 6)
        XCTAssertTrue(controller.replaceVisibleTextRange(reverse, with: "X"))
        XCTAssertEqual(controller.text, "Before\n\nAlpha Xta\n\nAfter")
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, original)
        XCTAssertFalse(controller.canUndo)
    }

    func testRejectsStaleSourceSurrogateSplitAndUnsupportedBlockAtomically() {
        let original = "Before\n\n😀 first\n\nAfter"
        let controller = MarkdownEditorController(text: original)
        let split = selection(original, "block-1", 1, "block-2", 2)
        XCTAssertNil(controller.copyVisibleTextRange(split))
        XCTAssertFalse(controller.deleteVisibleTextRange(split))
        XCTAssertEqual(controller.text, original)
        XCTAssertFalse(controller.canUndo)

        let selected = selection(original, "block-1", 2, "block-2", 2)
        controller.replaceRange(NSRange(location: 0, length: 0), with: "Intro\n\n")
        let changed = controller.text
        XCTAssertNil(controller.copyVisibleTextRange(selected))
        XCTAssertFalse(controller.replaceVisibleTextRange(selected, with: "X"))
        XCTAssertEqual(controller.text, changed)
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, original)
        XCTAssertFalse(controller.canUndo)

        let list = "Before\n\n- item\n\nAfter"
        let blocked = MarkdownEditorController(text: list)
        let crossingList = selection(list, "block-0", 2, "block-2", 2)
        XCTAssertNil(blocked.copyVisibleTextRange(crossingList))
        XCTAssertFalse(blocked.deleteVisibleTextRange(crossingList))
        XCTAssertFalse(blocked.canUndo)
    }

    func testRejectsMarkdownStructureReplacementAndLeavesHistoryUntouched() {
        let original = "First\n\n# Second\n\nThird"
        let controller = MarkdownEditorController(text: original)
        let selected = selection(original, "block-0", 2, "block-1", 3)
        XCTAssertFalse(controller.replaceVisibleTextRange(selected, with: "\n\n- item"))
        XCTAssertFalse(controller.replaceVisibleTextRange(selected, with: "**bold**"))
        XCTAssertEqual(controller.text, original)
        XCTAssertFalse(controller.canUndo)
    }

    func testSingleBlockPartialCodeCopyAndMarkedDeletionKeepUnselectedStyle() {
        let original = "Use `code` and **bold** end"
        let controller = MarkdownEditorController(text: original)
        let code = selection(original, "block-0", 5, "block-0", 7)
        XCTAssertEqual(controller.copyVisibleTextRange(code), "`od`")

        let bold = selection(original, "block-0", 14, "block-0", 16)
        XCTAssertEqual(controller.copyVisibleTextRange(bold), "**ol**")
        XCTAssertTrue(controller.deleteVisibleTextRange(bold))
        XCTAssertEqual(MarkdownInlineMarkEditor.visibleText(of: controller.semanticDocument.blocks[0].plainText),
                       "Use code and bd end")
        XCTAssertEqual(MarkdownInlineMarkEditor.visibleStyles(of: controller.semanticDocument.blocks[0].plainText)?[13].bold, 1)
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, original)
    }

    func testReplacingThroughIntermediateHeadingPreservesOnlyOuterRows() {
        let original = "Before\n\nFirst\n\n# Middle\n\nLast\n\nAfter"
        let controller = MarkdownEditorController(text: original)
        let selected = selection(original, "block-1", 2, "block-3", 2)
        XCTAssertEqual(controller.copyVisibleTextRange(selected), "rst\n\n# Middle\n\nLa")
        XCTAssertTrue(controller.replaceVisibleTextRange(selected, with: "X"))
        XCTAssertEqual(controller.text, "Before\n\nFiXst\n\nAfter")
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, original)
    }
}
