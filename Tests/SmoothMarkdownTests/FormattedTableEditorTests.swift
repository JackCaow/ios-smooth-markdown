import XCTest
@testable import SmoothMarkdown

@MainActor
final class FormattedTableEditorTests: XCTestCase {
    func testTableBlockRoundTripsExactSourceIncludingEscapesAndLineEndings() {
        let source = "Before 😀\r\n\r\n| A\\|B | **H** |\r\n| :--- | ---: |\r\n| one\\|two | [link](https://example.com) |\r\n\r\nAfter"
        let document = MarkdownDocumentCodec().parse(source)
        XCTAssertEqual(document.toMarkdown(), source)
        XCTAssertEqual(document.blocks.count, 3)
        guard case let .table(table) = document.blocks[1].kind else { return XCTFail("Expected table block") }
        XCTAssertEqual(table.headers, ["A\\|B", "**H**"])
        XCTAssertEqual(table.rows, [["one\\|two", "[link](https://example.com)"]])
        XCTAssertEqual(table.alignments, [.left, .right])
    }

    func testCellEditKeepsEscapedPipeAlignmentAndOtherSourceWithUndo() {
        let source = "Intro\r\n\r\n| A\\|B | **H** |\r\n| :--- | ---: |\r\n| one\\|two | [link](https://example.com) |\r\n\r\nEnd"
        let controller = MarkdownEditorController(text: source)
        XCTAssertTrue(controller.updateSemanticTable(id: "block-1") {
            $0.replacingCell(rowIndex: 0, columnIndex: 0, text: "three|four")
        })
        XCTAssertTrue(controller.text.contains("| three\\|four | [link](https://example.com) |"))
        XCTAssertTrue(controller.text.contains("| :--- | ---: |"))
        XCTAssertTrue(controller.text.hasPrefix("Intro\r\n\r\n"))
        XCTAssertTrue(controller.text.hasSuffix("\r\n\r\nEnd"))
        XCTAssertTrue(controller.text.contains("\r\n| :--- | ---: |\r\n"))
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, source)
        XCTAssertTrue(controller.redo())
        XCTAssertTrue(controller.text.contains("three\\|four"))
    }

    func testRowsColumnsAndAlignmentEditThroughControllerAndUndo() {
        let source = "| A | B |\n| --- | ---: |\n| 1 | 2 |\n"
        let controller = MarkdownEditorController(text: source)
        XCTAssertTrue(controller.updateSemanticTable(id: "block-0") { $0.insertingColumnAfter(0) })
        XCTAssertTrue(controller.updateSemanticTable(id: "block-0") { $0.insertingRowAfter(0) })
        XCTAssertTrue(controller.updateSemanticTable(id: "block-0") { $0.settingColumnAlignment(1, to: .center) })
        guard case let .table(table) = controller.semanticDocument.blocks[0].kind else {
            return XCTFail("Expected edited table")
        }
        XCTAssertEqual(table.headers, ["A", "", "B"])
        XCTAssertEqual(table.rows, [["1", "", "2"], ["", "", ""]])
        XCTAssertEqual(table.alignments, [nil, .center, .right])
        XCTAssertEqual(controller.text, "| A |  | B |\n| --- | :---: | ---: |\n| 1 |  | 2 |\n|  |  |  |\n")
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.semanticDocument.blocks[0].kind,
                       .table(MarkdownSourceTable(headers: ["A", "", "B"], rows: [["1", "", "2"], ["", "", ""]], alignments: [nil, nil, .right])))
    }

    func testFencedTableLikeTextRemainsCode() {
        let source = "```md\n| A | B |\n| --- | --- |\n```\n"
        let document = MarkdownDocumentCodec().parse(source)
        XCTAssertEqual(document.blocks.count, 1)
        guard case .fencedCode = document.blocks[0].kind else { return XCTFail("Expected code block") }
        XCTAssertEqual(document.toMarkdown(), source)
    }

    func testDeleteRowAndColumnKeepsRemainingAlignment() {
        let source = "| A | B | C |\n| :--- | :---: | ---: |\n| 1 | 2 | 3 |\n| 4 | 5 | 6 |"
        let controller = MarkdownEditorController(text: source)
        XCTAssertTrue(controller.updateSemanticTable(id: "block-0") { $0.deletingRow(0) })
        XCTAssertTrue(controller.updateSemanticTable(id: "block-0") { $0.deletingColumn(1) })
        XCTAssertEqual(controller.text, "| A | C |\n| :--- | ---: |\n| 4 | 6 |")
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, "| A | B | C |\n| :--- | :---: | ---: |\n| 4 | 5 | 6 |")
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, source)
    }

    func testExistingPipeEscapeIsNotDoubledOnCellEdit() {
        let controller = MarkdownEditorController(text: "| H |\n| --- |\n| old |")
        XCTAssertTrue(controller.updateSemanticTable(id: "block-0") {
            $0.replacingCell(rowIndex: 0, columnIndex: 0, text: "left\\|right")
        })
        XCTAssertEqual(controller.text, "| H |\n| --- |\n| left\\|right |")
        guard case let .table(table) = controller.semanticDocument.blocks[0].kind else {
            return XCTFail("Expected table")
        }
        XCTAssertEqual(table.rows, [["left\\|right"]])
    }

    func testOneColumnTableBodyWithoutPipesRoundTrips() {
        let source = "| Header |\n| --- |\nfirst\nsecond\n\nAfter"
        let document = MarkdownDocumentCodec().parse(source)
        guard case let .table(table) = document.blocks[0].kind else { return XCTFail("Expected table") }
        XCTAssertEqual(table.rows, [["first"], ["second"]])
        XCTAssertEqual(document.toMarkdown(), source)
        XCTAssertEqual(document.blocks[1].plainText, "After")
    }

    func testCellEditKeepsUntouchedTableBytesAndSourceSelectionThroughUndo() {
        let original = "- parent\r\n  - child\r\n\r\n"
            + "> quote 😀\r\n\r\n"
            + "| Name  |   Value |\r\n| :---- | ---: |\r\n| one\\|two | 1 |\r\n\r\nTail 😀"
        let controller = MarkdownEditorController(text: original)
        let originalSelection = (original as NSString).range(of: "Tail 😀")
        controller.setSelection(originalSelection)
        controller.mode = .formatted
        XCTAssertTrue(controller.updateSemanticTable(id: "block-2") {
            $0.replacingCell(rowIndex: 0, columnIndex: 0, text: "three|four")
        })
        let edited = original.replacingOccurrences(of: "one\\|two", with: "three\\|four")
        XCTAssertEqual(controller.text, edited, "Only the edited table cell should change")
        controller.mode = .source
        XCTAssertEqual(controller.selection, (edited as NSString).range(of: "Tail 😀"))
        XCTAssertEqual(controller.selectedText, "Tail 😀")
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, original)
        XCTAssertEqual(controller.selection, originalSelection)
        XCTAssertTrue(controller.redo())
        XCTAssertEqual(controller.text, edited)
        XCTAssertEqual(controller.selectedText, "Tail 😀")
    }
}
