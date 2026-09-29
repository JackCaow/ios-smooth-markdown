import Foundation
import XCTest
@testable import SmoothMarkdown

@MainActor
final class BlockRangeTransformTests: XCTestCase {
    func testPartialTextEndpointsTransformWholeSiblingBlocksIntoOneOrderedListAndUndo() {
        let source = "# First **bold**\r\n\r\nSecond `code`\r\n\r\n```swift\r\nprint(1)\r\n```\r\n"
        let controller = MarkdownEditorController(text: source)
        let range = MarkdownSemanticTextSelection(
            anchor: .init(blockID: "block-1", offset: 3),
            focus: .init(blockID: "block-0", offset: 2), source: source)
        XCTAssertTrue(controller.canApplySemanticBlockCommandToTextRange(range, command: .orderedList))
        XCTAssertTrue(controller.applySemanticBlockCommandToTextRange(range, command: .orderedList))
        XCTAssertEqual(controller.text,
                       "1. First **bold**\r\n2. Second `code`\r\n\r\n```swift\r\nprint(1)\r\n```\r\n")
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, source)
        XCTAssertFalse(controller.canUndo)
    }

    func testBlockRangeGroupsQuoteAndPreservesUnselectedSource() {
        let source = "Prelude\n\nFirst *item*\n\nSecond item\n\nAfter"
        let controller = MarkdownEditorController(text: source)
        XCTAssertTrue(controller.canApplySemanticBlockCommandToBlockRange(
            from: "block-2", to: "block-1", command: .blockquote))
        XCTAssertTrue(controller.applySemanticBlockCommandToBlockRange(
            from: "block-2", to: "block-1", command: .blockquote))
        XCTAssertEqual(controller.text, "Prelude\n\n> First *item*\n> Second item\n\nAfter")
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, source)
    }

    func testHeadingAndParagraphTransformRetainInlineMarkdownAndBlockTrivia() {
        let source = "# One **strong**\n\n## Two `code`\n\nTail"
        let controller = MarkdownEditorController(text: source)
        XCTAssertTrue(controller.applySemanticBlockCommandToBlockRange(
            from: "block-0", to: "block-1", command: .paragraph))
        XCTAssertEqual(controller.text, "One **strong**\n\nTwo `code`\n\nTail")
        let second = MarkdownSemanticTextSelection(
            anchor: .init(blockID: "block-0", offset: 1),
            focus: .init(blockID: "block-1", offset: 2), source: controller.text)
        XCTAssertTrue(controller.applySemanticBlockCommandToTextRange(second, command: .heading3))
        XCTAssertEqual(controller.text, "### One **strong**\n\n### Two `code`\n\nTail")
    }

    func testMultilineProseBecomesIndentedListContinuation() {
        let source = "First line\nsecond line\n\nAnother"
        let controller = MarkdownEditorController(text: source)
        XCTAssertTrue(controller.applySemanticBlockCommandToBlockRange(
            from: "block-0", to: "block-1", command: .taskList))
        XCTAssertEqual(controller.text, "- [ ] First line\n      second line\n- [ ] Another")
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, source)
    }

    func testTransformAfterFrontmatterRetainsEnvelopeAndFollowingMarkdown() {
        let source = "\u{FEFF}---\r\ntitle: Demo\r\n---\r\n\r\nAlpha\r\n\r\nBeta\r\n"
        let controller = MarkdownEditorController(text: source)
        XCTAssertTrue(controller.applySemanticBlockCommandToBlockRange(
            from: "block-1", to: "block-2", command: .unorderedList))
        XCTAssertEqual(controller.text, "\u{FEFF}---\r\ntitle: Demo\r\n---\r\n\r\n- Alpha\r\n- Beta\r\n")
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, source)
    }

    func testRejectsStaleStructuredAndUnsafeReparseWithoutMutation() {
        let source = "First\n\n| A |\n|---|\n| B |\n\nLast"
        let controller = MarkdownEditorController(text: source)
        let selected = MarkdownSemanticTextSelection(
            anchor: .init(blockID: "block-0", offset: 1),
            focus: .init(blockID: "block-2", offset: 1), source: source)
        XCTAssertFalse(controller.applySemanticBlockCommandToTextRange(selected, command: .taskList))
        XCTAssertEqual(controller.text, source)
        XCTAssertFalse(controller.canUndo)

        let stale = MarkdownSemanticTextSelection(
            anchor: .init(blockID: "block-0", offset: 1),
            focus: .init(blockID: "block-0", offset: 2), source: "old")
        XCTAssertFalse(controller.applySemanticBlockCommandToTextRange(stale, command: .blockquote))
        XCTAssertEqual(controller.text, source)
    }
}
