import Foundation
import XCTest
@testable import SmoothMarkdown

@MainActor
final class StructuredBlockPasteTests: XCTestCase {
    func testPastingHeadingAndListSplitsParagraphAndKeepsNeighborSource() {
        let original = "Before 😀 tail\r\n\r\nUntouched `code`"
        let controller = MarkdownEditorController(text: original)
        let range = NSRange(location: ("Before 😀 " as NSString).length, length: 0)
        XCTAssertTrue(controller.replaceSemanticTextRangeWithMarkdownBlocks(
            id: "block-0", range: range, markdown: "## Inserted\n\n- one\n- two"))
        XCTAssertEqual(controller.text,
                       "Before 😀 \r\n\r\n## Inserted\n\n- one\n- two\r\n\r\ntail\r\n\r\nUntouched `code`")
        XCTAssertEqual(controller.semanticDocument.blocks.map(\.plainText),
                       ["Before 😀 ", "Inserted", "one\ntwo", "tail", "Untouched `code`"])
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, original)
        XCTAssertFalse(controller.canUndo)
        XCTAssertTrue(controller.redo())
        XCTAssertTrue(controller.text.contains("## Inserted"))
    }

    func testPastingTableIntoHeadingKeepsHeadingBeforeAndParagraphAfter() {
        let original = "# Alpha middle omega\n\nTail"
        let controller = MarkdownEditorController(text: original)
        let range = NSRange(location: ("Alpha " as NSString).length,
                            length: ("middle " as NSString).length)
        XCTAssertTrue(controller.replaceSemanticTextRangeWithMarkdownBlocks(
            id: "block-0", range: range,
            markdown: "| A | B |\n| --- | --- |\n| 1 | 2 |"))
        XCTAssertEqual(controller.text,
                       "# Alpha \n\n| A | B |\n| --- | --- |\n| 1 | 2 |\n\nomega\n\nTail")
        XCTAssertEqual(controller.semanticDocument.blocks.count, 4)
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, original)
    }

    func testPastingAtParagraphEdgesDoesNotCreateEmptyBlocks() {
        let atStart = MarkdownEditorController(text: "Tail\n\nNeighbor")
        XCTAssertTrue(atStart.replaceSemanticTextRangeWithMarkdownBlocks(
            id: "block-0", range: NSRange(location: 0, length: 0), markdown: "## Start\n"))
        XCTAssertEqual(atStart.text, "## Start\n\nTail\n\nNeighbor")
        XCTAssertEqual(atStart.semanticDocument.blocks.count, 3)

        let atEnd = MarkdownEditorController(text: "Head\n\nNeighbor")
        XCTAssertTrue(atEnd.replaceSemanticTextRangeWithMarkdownBlocks(
            id: "block-0", range: NSRange(location: 4, length: 0), markdown: "- one\n- two"))
        XCTAssertEqual(atEnd.text, "Head\n\n- one\n- two\n\nNeighbor")
        XCTAssertEqual(atEnd.semanticDocument.blocks.count, 3)
    }

    func testInvalidUTF16AndUnsupportedBlockLeaveHistoryUntouched() {
        let controller = MarkdownEditorController(text: "A😀B\n\n```swift\nlet x = 1\n```")
        let original = controller.text
        XCTAssertFalse(controller.replaceSemanticTextRangeWithMarkdownBlocks(
            id: "block-0", range: NSRange(location: 2, length: 0), markdown: "## Inserted"))
        XCTAssertFalse(controller.replaceSemanticTextRangeWithMarkdownBlocks(
            id: "block-1", range: NSRange(location: 0, length: 0), markdown: "## Inserted"))
        XCTAssertEqual(controller.text, original)
        XCTAssertFalse(controller.canUndo)
    }

    func testPasteKeepsCompleteInlineMarksAndRejectsSplittingOne() {
        let original = "Before **bold** after"
        let rejected = MarkdownEditorController(text: original)
        XCTAssertFalse(rejected.replaceSemanticTextRangeWithMarkdownBlocks(
            id: "block-0", range: NSRange(location: ("Before **bo" as NSString).length, length: 0),
            markdown: "## Inserted"))
        XCTAssertEqual(rejected.text, original)
        XCTAssertFalse(rejected.canUndo)

        let accepted = MarkdownEditorController(text: original)
        XCTAssertTrue(accepted.replaceSemanticTextRangeWithMarkdownBlocks(
            id: "block-0", range: NSRange(location: ("Before **bold** " as NSString).length, length: 0),
            markdown: "## Inserted"))
        XCTAssertEqual(accepted.text, "Before **bold** \n\n## Inserted\n\nafter")
    }

    func testPasteRecognitionLeavesProseAndIMEOnNormalInputPath() {
        XCTAssertFalse(MarkdownEditorController.isStructuredBlockPaste("plain\ntext", hasMarkedText: false))
        XCTAssertFalse(MarkdownEditorController.isStructuredBlockPaste("# Heading", hasMarkedText: false))
        XCTAssertFalse(MarkdownEditorController.isStructuredBlockPaste("## Heading\nnext", hasMarkedText: true))
        XCTAssertTrue(MarkdownEditorController.isStructuredBlockPaste("## Heading\nnext", hasMarkedText: false))
        XCTAssertTrue(MarkdownEditorController.isStructuredBlockPaste("- one\n- two", hasMarkedText: false))
    }

    func testStaleRenderedBlockCannotPasteIntoReusedBlockID() {
        let controller = MarkdownEditorController(text: "Current")
        XCTAssertFalse(controller.replaceSemanticTextRangeWithMarkdownBlocks(
            id: "block-0", range: NSRange(location: 0, length: 0),
            markdown: "## New", ifTextIs: "Previous"))
        XCTAssertEqual(controller.text, "Current")
        XCTAssertFalse(controller.canUndo)
    }
}
