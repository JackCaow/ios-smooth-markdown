import XCTest
@testable import SmoothMarkdown

@MainActor
final class TableCellTextRangeEditorTests: XCTestCase {
    private func cell(_ block: String, _ row: Int, _ column: Int, _ offset: Int)
        -> MarkdownSemanticTextPosition {
        .init(blockID: block, offset: offset, tableRow: row, tableColumn: column)
    }

    func testEscapedPipeMapsVisibleCharacterToExactSourceAndUndoes() {
        let original = "Before\r\n\r\n| A\\|B | C |\r\n| :--- | ---: |\r\n| x | y |\r\n\r\nAfter"
        let controller = MarkdownEditorController(text: original)
        let selection = MarkdownSemanticTextSelection(anchor: cell("block-1", 0, 0, 1),
                                                     focus: cell("block-1", 0, 0, 2), source: original)
        XCTAssertEqual(controller.copySemanticTextRange(selection), "\\|")
        XCTAssertEqual(controller.semanticTableCellHighlightRanges(selection)?["block-1"]?[0]?[0],
                       NSRange(location: 1, length: 1))
        XCTAssertTrue(controller.replaceSemanticTextRange(selection, with: "X"))
        XCTAssertEqual(controller.text,
                       "Before\r\n\r\n| AXB | C |\r\n| :--- | ---: |\r\n| x | y |\r\n\r\nAfter")
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, original)
        XCTAssertFalse(controller.canUndo)
    }

    func testCellReplacementEscapesInsertedPipeWithoutRewritingDelimiters() {
        let original = "| A B | C |\r\n| :---- | ---: |\r\n| x | y |"
        let controller = MarkdownEditorController(text: original)
        let selection = MarkdownSemanticTextSelection(anchor: cell("block-0", 0, 0, 1),
                                                     focus: cell("block-0", 0, 0, 2))
        XCTAssertTrue(controller.replaceSemanticTextRange(selection, with: "|"))
        XCTAssertEqual(controller.text, "| A\\|B | C |\r\n| :---- | ---: |\r\n| x | y |")
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, original)
    }

    func testUnrepresentableVisibleBackslashPipeRejectsAtomically() {
        let original = "| A B | C |\n| --- | --- |"
        let controller = MarkdownEditorController(text: original)
        let selection = MarkdownSemanticTextSelection(anchor: cell("block-0", 0, 0, 1),
                                                     focus: cell("block-0", 0, 0, 2))
        XCTAssertFalse(controller.replaceSemanticTextRange(selection, with: "\\|"))
        XCTAssertEqual(controller.text, original)
        XCTAssertFalse(controller.canUndo)
    }

    func testLastTableCellToHeadingPreservesTableAndCRLF() {
        let original = "Before\r\n\r\n| A | B |\r\n| :---- | ---: |\r\n| 1 | two\\|tail |\r\n\r\n- item\r\n\r\n# After omega\r\n\r\nKeep"
        let controller = MarkdownEditorController(text: original)
        let selection = MarkdownSemanticTextSelection(anchor: cell("block-1", 1, 1, 4),
            focus: .init(blockID: "block-3", offset: 5), source: original)
        XCTAssertEqual(controller.copySemanticTextRange(selection),
                       "tail |\r\n\r\n- item\r\n\r\n# After")
        XCTAssertTrue(controller.replaceSemanticTextRange(selection, with: "X|Y"))
        XCTAssertEqual(controller.text,
                       "Before\r\n\r\n| A | B |\r\n| :---- | ---: |\r\n| 1 | two\\|X\\|Y |\r\n\r\n#  omega\r\n\r\nKeep")
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, original)
        XCTAssertFalse(controller.canUndo)
    }

    func testProseToFirstHeaderCellKeepsOriginalTableGrid() {
        let original = "Lead alpha\r\n\r\n- item\r\n\r\n| One\\|two | B |\r\n| --- | --- |\r\n| x | y |\r\n\r\nKeep"
        let controller = MarkdownEditorController(text: original)
        let selection = MarkdownSemanticTextSelection(anchor: .init(blockID: "block-0", offset: 5),
            focus: cell("block-2", 0, 0, 4), source: original)
        XCTAssertEqual(controller.copySemanticTextRange(selection),
                       "alpha\r\n\r\n- item\r\n\r\n| One\\|")
        XCTAssertTrue(controller.deleteSemanticTextRange(selection))
        XCTAssertEqual(controller.text,
                       "Lead \r\n\r\n| two | B |\r\n| --- | --- |\r\n| x | y |\r\n\r\nKeep")
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, original)

        let reversed = MarkdownSemanticTextSelection(anchor: cell("block-2", 0, 0, 4),
            focus: .init(blockID: "block-0", offset: 5), source: original)
        XCTAssertTrue(controller.replaceSemanticTextRange(reversed, with: "X"))
        XCTAssertEqual(controller.text,
                       "Lead X\r\n\r\n| two | B |\r\n| --- | --- |\r\n| x | y |\r\n\r\nKeep")
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, original)
    }

    func testUnsafeCellEdgesStaleRevisionAndInvalidOffsetsDoNothing() {
        let original = "Before\n\n| 😀 | B |\n| --- | --- |\n| x | tail |\n\nAfter"
        let controller = MarkdownEditorController(text: original)
        let nonEdge = MarkdownSemanticTextSelection(anchor: cell("block-1", 1, 0, 1),
            focus: .init(blockID: "block-2", offset: 2), source: original)
        XCTAssertFalse(controller.deleteSemanticTextRange(nonEdge))
        let splitEmoji = MarkdownSemanticTextSelection(anchor: cell("block-1", 0, 0, 1),
            focus: .init(blockID: "block-2", offset: 2), source: original)
        XCTAssertNil(controller.copySemanticTextRange(splitEmoji))
        let safe = MarkdownSemanticTextSelection(anchor: cell("block-1", 1, 1, 1),
            focus: .init(blockID: "block-2", offset: 2), source: original)
        XCTAssertFalse(controller.replaceSemanticTextRange(safe, with: "new\nline"))
        controller.replaceRange(NSRange(location: 0, length: 0), with: "New\n\n")
        let changed = controller.text
        XCTAssertNil(controller.copySemanticTextRange(safe))
        XCTAssertFalse(controller.deleteSemanticTextRange(safe))
        XCTAssertEqual(controller.text, changed)
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, original)
        XCTAssertFalse(controller.canUndo)
    }
}
