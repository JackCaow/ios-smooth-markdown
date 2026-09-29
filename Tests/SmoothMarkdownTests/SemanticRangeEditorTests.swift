import XCTest
@testable import SmoothMarkdown

@MainActor
final class SemanticRangeEditorTests: XCTestCase {
    func testSiblingListDragCopiesExactSourceAndDeletesWithOneUndo() {
        let original = "Intro\r\n\r\n- one\r\n- two 😀\r\n- three\r\n\r\nTail"
        let controller = MarkdownEditorController(text: original)
        let selection = MarkdownSemanticListItemSelection(blockID: "block-1", anchorIndex: 1, focusIndex: 0)
        XCTAssertEqual(controller.copySemanticListItemRange(selection), "- one\r\n- two 😀\r\n")
        XCTAssertTrue(controller.canDeleteSemanticListItemRange(selection))
        XCTAssertTrue(controller.deleteSemanticListItemRange(selection))
        XCTAssertEqual(controller.text, "Intro\r\n\r\n- three\r\n\r\nTail")
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, original)
        XCTAssertFalse(controller.canUndo)
    }

    func testListDragRejectsNestedParentAndPreservesOtherItems() {
        let original = "- parent\n  - child\n- sibling\n- tail"
        let controller = MarkdownEditorController(text: original)
        let nested = MarkdownSemanticListItemSelection(blockID: "block-0", anchorIndex: 0, focusIndex: 2)
        XCTAssertNil(controller.copySemanticListItemRange(nested))
        XCTAssertFalse(controller.deleteSemanticListItemRange(nested))
        let siblings = MarkdownSemanticListItemSelection(blockID: "block-0", anchorIndex: 2, focusIndex: 3)
        XCTAssertEqual(controller.copySemanticListItemRange(siblings), "- sibling\n- tail")
        XCTAssertTrue(controller.deleteSemanticListItemRange(siblings))
        XCTAssertEqual(controller.text, "- parent\n  - child\n")
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, original)
    }

    func testTableRectangleCopiesTSVAndClearsWithoutReformattingSource() {
        let original = "Intro\r\n\r\n| Name  |   Value |\r\n| :---- | ---: |\r\n"
            + "| A\\|B | 1 |\r\n| C | 2 |\r\n\r\nTail 😀"
        let controller = MarkdownEditorController(text: original)
        let selection = MarkdownSemanticTableCellSelection(blockID: "block-1", anchorRow: 2,
                                                            anchorColumn: 1, focusRow: 1, focusColumn: 0)
        XCTAssertEqual(controller.semanticTableCellRectangle(selection)?.rows, 1...2)
        XCTAssertEqual(controller.semanticTableCellRectangle(selection)?.columns, 0...1)
        XCTAssertEqual(controller.copySemanticTableCellsAsTSV(selection), "A|B\t1\nC\t2")
        XCTAssertTrue(controller.canClearSemanticTableCells(selection))
        XCTAssertTrue(controller.clearSemanticTableCells(selection))
        XCTAssertEqual(controller.text, "Intro\r\n\r\n| Name  |   Value |\r\n| :---- | ---: |\r\n"
                       + "|  |  |\r\n|  |  |\r\n\r\nTail 😀")
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, original)
        XCTAssertFalse(controller.canUndo)
    }

    func testRangeCommandsRejectInvalidEndpointsWithoutMutation() {
        let original = "- one\n- two\n\n| A | B |\n| --- | --- |\n| x | y |"
        let controller = MarkdownEditorController(text: original)
        let singleItem = MarkdownSemanticListItemSelection(blockID: "block-0", anchorIndex: 0, focusIndex: 0)
        XCTAssertNil(controller.copySemanticListItemRange(singleItem))
        XCTAssertFalse(controller.deleteSemanticListItemRange(singleItem))
        let outside = MarkdownSemanticTableCellSelection(blockID: "block-1", anchorRow: 0,
                                                          anchorColumn: 0, focusRow: 9, focusColumn: 1)
        XCTAssertNil(controller.copySemanticTableCellsAsTSV(outside))
        XCTAssertFalse(controller.clearSemanticTableCells(outside))
        XCTAssertEqual(controller.text, original)
        XCTAssertFalse(controller.canUndo)
    }
}
