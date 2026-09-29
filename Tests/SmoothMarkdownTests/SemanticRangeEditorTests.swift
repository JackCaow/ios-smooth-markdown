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

    func testListRangeFormatsPrimaryLinesAndPreservesMarkersContinuationsAndOneUndo() {
        let original = "Intro\r\n\r\n- one\r\n  continued\r\n- two 😀\r\n- three\r\n\r\nTail"
        let controller = MarkdownEditorController(text: original)
        let selected = MarkdownSemanticListItemSelection(blockID: "block-1", anchorIndex: 1, focusIndex: 0)
        XCTAssertTrue(controller.applySemanticInlineMarkToListItemRange(selected, mark: .bold))
        XCTAssertEqual(controller.text,
                       "Intro\r\n\r\n- **one**\r\n  continued\r\n- **two 😀**\r\n- three\r\n\r\nTail")
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, original)
        XCTAssertFalse(controller.canUndo)
    }

    func testListRangeLinkRejectsUnsafeURLWithoutPartialMutation() {
        let original = "- one\n- two\n- three"
        let controller = MarkdownEditorController(text: original)
        let selected = MarkdownSemanticListItemSelection(blockID: "block-0", anchorIndex: 0, focusIndex: 1)
        XCTAssertFalse(controller.applySemanticInlineMarkToListItemRange(
            selected, mark: .link(destination: "javascript:alert(1)")))
        XCTAssertEqual(controller.text, original)
        XCTAssertFalse(controller.canUndo)
        XCTAssertTrue(controller.applySemanticInlineMarkToListItemRange(
            selected, mark: .link(destination: "https://example.com")))
        XCTAssertEqual(controller.text, "- [one](https://example.com)\n- [two](https://example.com)\n- three")
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, original)
    }

    func testTableRangeFormatPreservesCellSpacingPipesCRLFAndOneUndo() {
        let original = "Intro\r\n\r\n| Name  |   Value |\r\n| :---- | ---: |\r\n"
            + "| A\\|B | 1 |\r\n| C | 2 |\r\n\r\nTail"
        let controller = MarkdownEditorController(text: original)
        let selected = MarkdownSemanticTableCellSelection(blockID: "block-1", anchorRow: 2,
                                                           anchorColumn: 1, focusRow: 1, focusColumn: 0)
        XCTAssertTrue(controller.applySemanticInlineMarkToTableCells(selected, mark: .strikethrough))
        XCTAssertEqual(controller.text, "Intro\r\n\r\n| Name  |   Value |\r\n| :---- | ---: |\r\n"
                       + "| ~~A\\|B~~ | ~~1~~ |\r\n| ~~C~~ | ~~2~~ |\r\n\r\nTail")
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, original)
        XCTAssertFalse(controller.canUndo)
        XCTAssertFalse(controller.applySemanticInlineMarkToTableCells(
            selected, mark: .link(destination: "https://example.com")))
        XCTAssertEqual(controller.text, original)
    }

    func testTableRangeSkipsEmptyCellsAndRejectsInvalidSelection() {
        let original = "| A | B |\n| --- | --- |\n|  | x |\n| y |  |"
        let controller = MarkdownEditorController(text: original)
        let selected = MarkdownSemanticTableCellSelection(blockID: "block-0", anchorRow: 1,
                                                           anchorColumn: 0, focusRow: 2, focusColumn: 1)
        XCTAssertTrue(controller.applySemanticInlineMarkToTableCells(selected, mark: .italic))
        XCTAssertEqual(controller.text, "| A | B |\n| --- | --- |\n|  | *x* |\n| *y* |  |")
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, original)
        let invalid = MarkdownSemanticTableCellSelection(blockID: "block-0", anchorRow: 0,
                                                          anchorColumn: 0, focusRow: 8, focusColumn: 1)
        XCTAssertFalse(controller.applySemanticInlineMarkToTableCells(invalid, mark: .bold))
        XCTAssertEqual(controller.text, original)
    }

    func testListAndTableRangeRefuseExistingInlineSyntaxWithoutPartialEdit() {
        let listSource = "- plain\n- **existing**\n- tail"
        let list = MarkdownEditorController(text: listSource)
        let items = MarkdownSemanticListItemSelection(blockID: "block-0", anchorIndex: 0, focusIndex: 1)
        XCTAssertFalse(list.applySemanticInlineMarkToListItemRange(items, mark: .italic))
        XCTAssertEqual(list.text, listSource)
        XCTAssertFalse(list.canUndo)

        let tableSource = "| plain | **existing** |\n| --- | --- |\n| one | two |"
        let table = MarkdownEditorController(text: tableSource)
        let cells = MarkdownSemanticTableCellSelection(blockID: "block-0", anchorRow: 0,
                                                       anchorColumn: 0, focusRow: 0, focusColumn: 1)
        XCTAssertFalse(table.applySemanticInlineMarkToTableCells(cells, mark: .bold))
        XCTAssertEqual(table.text, tableSource)
        XCTAssertFalse(table.canUndo)
    }
}
