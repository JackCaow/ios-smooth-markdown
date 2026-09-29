import XCTest
@testable import SmoothMarkdown

@MainActor
final class QuoteTextRangeEditorTests: XCTestCase {
    private func point(_ line: Int, _ offset: Int) -> MarkdownSemanticTextPosition {
        .init(blockID: "block-1", offset: offset, quoteLineIndex: line)
    }

    func testCopyPreservesInlineMarkersBlankQuoteLineAndCRLF() {
        let source = "Before\r\n\r\n> **Alpha**\r\n>\r\n> Beta 😀\r\n\r\nAfter"
        let controller = MarkdownEditorController(text: source)
        let selection = MarkdownSemanticTextSelection(anchor: point(0, 0), focus: point(2, 7), source: source)
        XCTAssertEqual(controller.copySemanticTextRange(selection), "> **Alpha**\r\n>\r\n> Beta 😀")
        XCTAssertEqual(controller.semanticQuoteLineHighlightRanges(selection)?["block-1"]?[2],
                       NSRange(location: 0, length: 7))
        XCTAssertEqual(controller.text, source)
    }

    func testCrossLineDeleteAndReplacePreserveUntouchedSourceWithOneUndo() {
        let source = "Before\r\n\r\n> Alpha\r\n> Beta 😀\r\n> Gamma\r\n\r\nAfter"
        let controller = MarkdownEditorController(text: source)
        let selection = MarkdownSemanticTextSelection(anchor: point(0, 2), focus: point(1, 5), source: source)
        XCTAssertEqual(controller.copySemanticTextRange(selection), "> pha\r\n> Beta ")
        XCTAssertTrue(controller.replaceSemanticTextRange(selection, with: "X"))
        XCTAssertEqual(controller.text, "Before\r\n\r\n> AlX😀\r\n> Gamma\r\n\r\nAfter")
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, source)
        XCTAssertFalse(controller.canUndo)
        XCTAssertTrue(controller.redo())
        XCTAssertEqual(controller.text, "Before\r\n\r\n> AlX😀\r\n> Gamma\r\n\r\nAfter")
    }

    func testNestedQuoteLineEditPreservesPrefixAndAdjacentLines() {
        let source = "Top\n\n> > one 😀\n> > **two**\n> > end\n\nTail"
        let controller = MarkdownEditorController(text: source)
        XCTAssertTrue(controller.replaceSemanticQuoteLine(id: "block-1", lineIndex: 1, with: "**updated**"))
        XCTAssertEqual(controller.text, "Top\n\n> > one 😀\n> > **updated**\n> > end\n\nTail")
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, source)
    }

    func testLazyContinuationStructuredChildrenAndStaleEndpointsFailClosed() {
        let lazy = "> Alpha\nlazy continuation\n> Beta"
        let lazyController = MarkdownEditorController(text: lazy)
        XCTAssertFalse(lazyController.replaceSemanticQuoteLine(id: "block-0", lineIndex: 0, with: "Changed"))
        let structured = "> Alpha\n> - child\n> Beta"
        let structuredController = MarkdownEditorController(text: structured)
        XCTAssertFalse(structuredController.replaceSemanticQuoteLine(id: "block-0", lineIndex: 0, with: "Changed"))
        let emojiController = MarkdownEditorController(text: "> 😀 done")
        let splitEmoji = MarkdownSemanticTextSelection(
            anchor: .init(blockID: "block-0", offset: 1, quoteLineIndex: 0),
            focus: .init(blockID: "block-0", offset: 2, quoteLineIndex: 0))
        XCTAssertNil(emojiController.copySemanticTextRange(splitEmoji))
        XCTAssertFalse(emojiController.deleteSemanticTextRange(splitEmoji))
        XCTAssertFalse(emojiController.replaceSemanticQuoteLine(id: "block-0", lineIndex: 0,
                                                                 with: "- child"))
        XCTAssertEqual(emojiController.text, "> 😀 done")
        let source = "Before\n\n> one\n> two\n\nAfter"
        let controller = MarkdownEditorController(text: source)
        let mixed = MarkdownSemanticTextSelection(anchor: point(0, 1), focus: point(1, 1), source: source)
        XCTAssertFalse(controller.canReplaceSemanticTextRange(mixed, with: "\n"))
        XCTAssertFalse(controller.deleteSemanticTextRange(.init(anchor: point(0, 1),
                                                                focus: point(1, 1), source: "stale")))
        XCTAssertEqual(controller.text, source)
        XCTAssertFalse(controller.canUndo)
    }

    func testDifferentNestingDepthRejectsCrossLineMutationButAllowsCopy() {
        let source = "Before\n\n> one\n> > nested\n> three\n\nAfter"
        let controller = MarkdownEditorController(text: source)
        let selection = MarkdownSemanticTextSelection(anchor: point(0, 1), focus: point(1, 2), source: source)
        XCTAssertEqual(controller.copySemanticTextRange(selection), "> ne\n> > ne")
        XCTAssertFalse(controller.deleteSemanticTextRange(selection))
        XCTAssertEqual(controller.text, source)
    }
}
