import XCTest
@testable import SmoothMarkdown

@MainActor
final class TableGridPasteTests: XCTestCase {
    func testRectanglePastePreservesUntouchedSourceSelectionAndOneUndoRedo() {
        let original = "Intro 😀\r\n\r\n| Name  |   Value | Extra |\r\n| :---- | ---: | :---: |\r\n"
            + "| A\\|B | 1 | stay |\r\n| C | 2 | stay |\r\n\r\nTail"
        let controller = MarkdownEditorController(text: original)
        let selection = MarkdownSemanticTableCellSelection(blockID: "block-1", anchorRow: 2,
                                                            anchorColumn: 1, focusRow: 1, focusColumn: 0)
        controller.setSelection(NSRange(location: ("Intro 😀" as NSString).length, length: 0))
        let sourceSelection = controller.selection
        XCTAssertTrue(controller.pasteSemanticTableCells("one|pipe\t10\r\ntwo\t20\r\n", into: selection))
        XCTAssertEqual(controller.text,
                       "Intro 😀\r\n\r\n| Name  |   Value | Extra |\r\n| :---- | ---: | :---: |\r\n"
                       + "| one\\|pipe | 10 | stay |\r\n| two | 20 | stay |\r\n\r\nTail")
        XCTAssertEqual(controller.selection, sourceSelection)
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, original)
        XCTAssertEqual(controller.selection, sourceSelection)
        XCTAssertFalse(controller.canUndo)
        XCTAssertTrue(controller.redo())
        XCTAssertTrue(controller.text.contains("| one\\|pipe | 10 | stay |"))
    }

    func testFocusedCellMultilinePasteFillsExistingRowsOnly() {
        let source = "| H1 | H2 |\n| --- | --- |\n| a | b |\n| c | d |"
        let controller = MarkdownEditorController(text: source)
        XCTAssertTrue(controller.pasteTableCells("first\tsecond\nthird\tfourth", inTable: "block-0",
                                                 row: 1, column: 0))
        XCTAssertEqual(controller.text, "| H1 | H2 |\n| --- | --- |\n| first | second |\n| third | fourth |")
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, source)
        XCTAssertFalse(controller.canUndo)
    }

    func testHeaderPasteKeepsInlineMarkdownAndEscapesLiteralPipes() {
        let source = "| H1 | H2 | Stay |\n| :--- | ---: | :---: |\n| x | y | z |"
        let controller = MarkdownEditorController(text: source)
        let selected = MarkdownSemanticTableCellSelection(blockID: "block-0", anchorRow: 0,
                                                           anchorColumn: 0, focusRow: 1, focusColumn: 1)
        XCTAssertTrue(controller.pasteSemanticTableCells("**Bold**\tA|B\n*Em*\t`Code`", into: selected))
        XCTAssertEqual(controller.text,
                       "| **Bold** | A\\|B | Stay |\n| :--- | ---: | :---: |\n| *Em* | `Code` | z |")
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, source)
    }

    func testRejectsRaggedOversizedAndOutOfBoundsGridAtomically() {
        let source = "| A | B |\n| --- | --- |\n| x | y |\n| q | r |"
        let controller = MarkdownEditorController(text: source)
        let cells = MarkdownSemanticTableCellSelection(blockID: "block-0", anchorRow: 1,
                                                        anchorColumn: 0, focusRow: 2, focusColumn: 1)
        XCTAssertFalse(controller.pasteSemanticTableCells("one\ttwo\nthree", into: cells))
        XCTAssertFalse(controller.pasteSemanticTableCells("one\ttwo\nthree\tfour\nfive\tsix", into: cells))
        XCTAssertFalse(controller.pasteTableCells("one\ttwo", inTable: "block-0", row: 2, column: 1))
        XCTAssertFalse(controller.pasteTableCells("single line", inTable: "block-0", row: 1, column: 0))
        XCTAssertFalse(controller.pasteTableCells("one\ttwo", inTable: "missing", row: 1, column: 0))
        XCTAssertFalse(controller.pasteTableCells(String(repeating: "x", count: 1_048_577) + "\n",
                                                  inTable: "block-0", row: 1, column: 0))
        XCTAssertEqual(controller.text, source)
        XCTAssertFalse(controller.canUndo)
    }

    func testSingleColumnMultilinePasteRejectsRowsBeyondTable() {
        let source = "| A | B |\n| --- | --- |\n| x | y |"
        let controller = MarkdownEditorController(text: source)
        XCTAssertFalse(controller.pasteTableCells("bad\n\nextra", inTable: "block-0", row: 1, column: 0))
        XCTAssertEqual(controller.text, source)
    }
}
