import XCTest
@testable import SmoothMarkdown

@MainActor
final class FormattedBlockEditorTests: XCTestCase {
    func testModesRetainSourcePreviewAndSplit() {
        XCTAssertEqual(MarkdownEditorMode.allCases, [.source, .formatted, .preview, .split])
    }

    func testHeadingEditRoundTripsAndUndoesWithoutTouchingRawBlock() {
        let original = "#  First **bold**\n\n<custom>&nbsp;literal</custom>\n\nParagraph\n"
        let controller = MarkdownEditorController(text: original)
        controller.mode = .formatted
        XCTAssertEqual(controller.semanticDocument.blocks.map(\.id), ["block-0", "block-1", "block-2"])
        XCTAssertTrue(controller.replaceSemanticBlockContent(id: "block-0", with: "Revised **bold**"))
        XCTAssertEqual(controller.text, "#  Revised **bold**\n\n<custom>&nbsp;literal</custom>\n\nParagraph\n")
        XCTAssertEqual(MarkdownDocumentCodec().parse(controller.text).blocks[0].kind,
                       .heading(level: 1, markdown: "Revised **bold**"))
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, original)
        XCTAssertEqual(controller.mode, .formatted)
        XCTAssertTrue(controller.redo())
        XCTAssertTrue(controller.text.contains("Revised **bold**"))
    }

    func testCodeEditKeepsFenceAndUndo() {
        let original = "~~~swift title=Demo\nlet x = 1\n~~~\n"
        let controller = MarkdownEditorController(text: original)
        XCTAssertTrue(controller.replaceSemanticBlockContent(id: "block-0", with: "let x = 2"))
        XCTAssertEqual(controller.text, "~~~swift title=Demo\nlet x = 2\n~~~\n")
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, original)
    }

    func testRemovingEmptyParagraphPreservesOtherBlocksAndUndo() {
        let original = "# First\n\nMiddle\n\nLast"
        let controller = MarkdownEditorController(text: original)
        XCTAssertTrue(controller.removeSemanticBlock(id: "block-1"))
        XCTAssertEqual(controller.text, "# First\n\nLast")
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, original)
        XCTAssertTrue(controller.removeSemanticBlock(id: "block-0"))
        XCTAssertEqual(controller.text, "Middle\n\nLast")
    }

    func testRawBlockSourceRangeUsesUTF16Offsets() {
        let source = "Emoji 😀\n\n<custom>raw</custom>\n"
        let document = MarkdownDocumentCodec().parse(source)
        let range = document.sourceRange(of: "block-1")!
        XCTAssertEqual((source as NSString).substring(with: range), "<custom>raw</custom>\n")
        XCTAssertEqual(range.location, ("Emoji 😀\n\n" as NSString).length)
        XCTAssertNil(document.sourceRange(of: "missing"))
    }

    func testComplexSourceBlocksPreviewKeepUntouchedBytesSelectionAndUndo() {
        let original = "# Editor 😀\r\n\r\n"
            + "- parent\r\n  - child\r\n- sibling\r\n\r\n"
            + "> quoted **text** 😀\r\n> second line\r\n\r\n"
            + "| Name  |   Value |\r\n| :---- | ---: |\r\n| one\\|two | 1 |\r\n\r\nTail"
        let controller = MarkdownEditorController(text: original)
        let document = controller.semanticDocument
        XCTAssertEqual(document.toMarkdown(), original)
        XCTAssertEqual(document.blocks.count, 5)
        guard case .list = document.blocks[1].kind, case .raw = document.blocks[2].kind,
              case .table = document.blocks[3].kind else {
            return XCTFail("Expected nested list, source-only blockquote, and editable GFM table")
        }

        let originalSelection = (original as NSString).range(of: "second line")
        controller.setSelection(originalSelection)
        controller.mode = .formatted
        XCTAssertTrue(controller.updateSemanticList(id: "block-1") {
            $0.replacingItemContent(at: 1, with: "much longer child 😀")
        })
        let edited = original.replacingOccurrences(of: "  - child", with: "  - much longer child 😀")
        XCTAssertEqual(controller.text, edited)
        controller.mode = .preview
        XCTAssertEqual(controller.text, edited)
        controller.mode = .source
        XCTAssertEqual(controller.selectedText, "second line")
        XCTAssertEqual(controller.selection, (edited as NSString).range(of: "second line"))

        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, original)
        XCTAssertEqual(controller.selection, originalSelection)
        XCTAssertTrue(controller.redo())
        XCTAssertEqual(controller.text, edited)
        XCTAssertEqual(controller.selectedText, "second line")
    }
}
