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
}
