import Foundation
import XCTest
@testable import SmoothMarkdown

@MainActor
final class FormattedRangeBlockPasteTests: XCTestCase {
    func testReplacesReversedProseRangeWithHeadingAndListInOneUndoStep() {
        let source = "Prelude\r\n\r\n# Alpha **bold**\r\n\r\nBeta tail\r\n\r\nNeighbor `exact`"
        let controller = MarkdownEditorController(text: source)
        let selected = MarkdownSemanticTextSelection(
            anchor: .init(blockID: "block-2", offset: 5),
            focus: .init(blockID: "block-1", offset: 6), source: source)
        let paste = "## Inserted\n\n- one\n- two"
        XCTAssertTrue(controller.canReplaceSemanticTextRangeWithMarkdownBlocks(selected, markdown: paste))
        XCTAssertTrue(controller.replaceSemanticTextRangeWithMarkdownBlocks(selected, markdown: paste))
        XCTAssertEqual(controller.text,
                       "Prelude\r\n\r\n# Alpha \r\n\r\n## Inserted\n\n- one\n- two\r\n\r\ntail\r\n\r\nNeighbor `exact`")
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, source)
        XCTAssertFalse(controller.canUndo)
    }

    func testFullRangeAfterFrontmatterKeepsEnvelopeAndFollowingBlock() {
        let source = "\u{FEFF}---\nname: Demo\n---\n\nOne\n\nTwo\n\nTail"
        let controller = MarkdownEditorController(text: source)
        let selected = MarkdownSemanticTextSelection(
            anchor: .init(blockID: "block-1", offset: 0),
            focus: .init(blockID: "block-2", offset: 3), source: source)
        XCTAssertTrue(controller.replaceSemanticTextRangeWithMarkdownBlocks(selected,
            markdown: "| A |\n| --- |\n| B |"))
        XCTAssertEqual(controller.text,
            "\u{FEFF}---\nname: Demo\n---\n\n| A |\n| --- |\n| B |\n\nTail")
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, source)
    }

    func testRejectsStaleRangeSplitInlineMarkAndStructuredInterveningBlock() {
        let source = "First **bold**\n\nMiddle\n\nLast"
        let controller = MarkdownEditorController(text: source)
        let stale = MarkdownSemanticTextSelection(
            anchor: .init(blockID: "block-0", offset: 1),
            focus: .init(blockID: "block-2", offset: 2), source: "old")
        XCTAssertFalse(controller.replaceSemanticTextRangeWithMarkdownBlocks(stale, markdown: "## New"))
        let split = MarkdownSemanticTextSelection(
            anchor: .init(blockID: "block-0", offset: 10),
            focus: .init(blockID: "block-2", offset: 2), source: source)
        XCTAssertFalse(controller.replaceSemanticTextRangeWithMarkdownBlocks(split, markdown: "## New"))
        XCTAssertEqual(controller.text, source)
        XCTAssertFalse(controller.canUndo)

        let structured = "First\n\n- item\n\nLast"
        let other = MarkdownEditorController(text: structured)
        let throughList = MarkdownSemanticTextSelection(
            anchor: .init(blockID: "block-0", offset: 1),
            focus: .init(blockID: "block-2", offset: 2), source: structured)
        XCTAssertFalse(other.replaceSemanticTextRangeWithMarkdownBlocks(throughList, markdown: "## New"))
        XCTAssertEqual(other.text, structured)
    }
}
