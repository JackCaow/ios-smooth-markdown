import XCTest
@testable import SmoothMarkdown

@MainActor
final class SemanticInlineRangeParityTests: XCTestCase {
    private func selection(_ first: MarkdownSemanticTextPosition, _ last: MarkdownSemanticTextPosition,
                           source: String? = nil) -> MarkdownSemanticTextSelection {
        .init(anchor: first, focus: last, source: source)
    }

    func testListPrimaryRowsFormatWithOneUndoAndPreserveMarkersAndLineEndings() {
        let original = "Before\r\n\r\n- [x] Alpha one\r\n- Beta two\r\n\r\nAfter"
        let controller = MarkdownEditorController(text: original)
        let range = selection(.init(blockID: "block-1", offset: 6, listItemIndex: 0),
                              .init(blockID: "block-1", offset: 4, listItemIndex: 1), source: original)
        XCTAssertTrue(controller.canApplySemanticInlineMarkToTextRange(range))
        XCTAssertTrue(controller.applySemanticInlineMarkToTextRange(range, mark: .bold))
        XCTAssertEqual(controller.text, "Before\r\n\r\n- [x] Alpha **one**\r\n- **Beta** two\r\n\r\nAfter")
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, original)
        XCTAssertFalse(controller.canUndo)
    }

    func testQuoteLinesFormatOnlyContentAndPreservePrefixes() {
        let original = "Intro\n\n> Alpha one\n> Beta two\n\nTail"
        let controller = MarkdownEditorController(text: original)
        let range = selection(.init(blockID: "block-1", offset: 6, quoteLineIndex: 0),
                              .init(blockID: "block-1", offset: 4, quoteLineIndex: 1))
        XCTAssertTrue(controller.canApplySemanticInlineMarkToTextRange(range))
        XCTAssertTrue(controller.applySemanticInlineMarkToTextRange(range, mark: .italic))
        XCTAssertEqual(controller.text, "Intro\n\n> Alpha *one*\n> *Beta* two\n\nTail")
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, original)
        XCTAssertFalse(controller.canUndo)
    }

    func testNestedListContinuationAndTrailingLinesKeepTheirOwners() {
        let original = "- Parent\n  first continuation\n  - Child\n\n  last trailing\n- Next"
        let controller = MarkdownEditorController(text: original)
        let range = selection(.init(blockID: "block-0", offset: 6,
                                    listItemIndex: 0, listContinuationIndex: 0),
                              .init(blockID: "block-0", offset: 4,
                                    listItemIndex: 0, listTrailingIndex: 0))
        XCTAssertTrue(controller.canApplySemanticInlineMarkToTextRange(range))
        XCTAssertTrue(controller.applySemanticInlineMarkToTextRange(range, mark: .bold))
        XCTAssertEqual(controller.text,
                       "- Parent\n  first **continuation**\n  - **Child**\n\n  **last** trailing\n- Next")
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, original)
    }

    func testTableCellsAcrossRowsFormatWithoutChangingGeometryOrEscapedPipe() {
        let original = "| First | Other |\n| --- | --- |\n| Alpha | Pipe \\| kept |\n| Last | Tail |\n\nAfter"
        let controller = MarkdownEditorController(text: original)
        let range = selection(.init(blockID: "block-0", offset: 2, tableRow: 0, tableColumn: 0),
                              .init(blockID: "block-0", offset: 4, tableRow: 1, tableColumn: 0))
        XCTAssertTrue(controller.canApplySemanticInlineMarkToTextRange(range))
        XCTAssertEqual(controller.semanticTableCellHighlightRanges(range)?["block-0"], [
            0: [0: NSRange(location: 2, length: 3), 1: NSRange(location: 0, length: 5)],
            1: [0: NSRange(location: 0, length: 4)],
        ])
        XCTAssertTrue(controller.applySemanticInlineMarkToTextRange(range, mark: .strikethrough))
        XCTAssertEqual(controller.text,
                       "| Fi~~rst~~ | ~~Other~~ |\n| --- | --- |\n| ~~Alph~~a | Pipe \\| kept |\n| Last | Tail |\n\nAfter")
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, original)
        XCTAssertFalse(controller.canUndo)
    }

    func testInlineCodeAcrossProseListAndTableCommitsOneEdit() {
        let original = "Lead one\n\n- List two\n\n| Cell three |\n| --- |\n| Keep |\n\nTail"
        let controller = MarkdownEditorController(text: original)
        let range = selection(.init(blockID: "block-0", offset: 5),
                              .init(blockID: "block-2", offset: 4, tableRow: 0, tableColumn: 0))
        XCTAssertTrue(controller.canApplySemanticInlineMarkToTextRange(range))
        XCTAssertTrue(controller.applySemanticInlineMarkToTextRange(range, mark: .code))
        XCTAssertEqual(controller.text,
                       "Lead `one`\n\n- `List two`\n\n| `Cell` three |\n| --- |\n| Keep |\n\nTail")
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, original)
        XCTAssertFalse(controller.canUndo)
    }

    func testUnsafeFieldOrBoundaryRejectsAtomically() {
        let original = "Start\n\n- Plain\n- **nested**\n\nEnd"
        let controller = MarkdownEditorController(text: original)
        let range = selection(.init(blockID: "block-0", offset: 2),
                              .init(blockID: "block-2", offset: 2))
        XCTAssertTrue(controller.canApplySemanticInlineMarkToTextRange(range))
        XCTAssertFalse(controller.applySemanticInlineMarkToTextRange(range, mark: .code))
        XCTAssertEqual(controller.text, original)
        XCTAssertFalse(controller.canUndo)

        let stale = selection(.init(blockID: "block-1", offset: 0, listItemIndex: 0),
                              .init(blockID: "block-1", offset: 2, listItemIndex: 1), source: "stale")
        XCTAssertFalse(controller.canApplySemanticInlineMarkToTextRange(stale))
        XCTAssertFalse(controller.applySemanticInlineMarkToTextRange(stale, mark: .bold))
        let listRange = selection(.init(blockID: "block-1", offset: 0, listItemIndex: 0),
                                  .init(blockID: "block-1", offset: 2, listItemIndex: 1))
        XCTAssertFalse(controller.canApplySemanticInlineMarkToTextRange(
            listRange, mark: .link(destination: "https://example.com")))
        XCTAssertFalse(controller.applySemanticInlineMarkToTextRange(
            listRange, mark: .link(destination: "https://example.com")))
        XCTAssertEqual(controller.text, original)
    }

    func testCrossBlockQuoteAndCodeRemainExplicitBoundaries() {
        let original = "Before\n\n> Quoted\n\nAfter"
        let controller = MarkdownEditorController(text: original)
        let quoteToProse = selection(.init(blockID: "block-1", offset: 1, quoteLineIndex: 0),
                                     .init(blockID: "block-2", offset: 2))
        XCTAssertFalse(controller.canApplySemanticInlineMarkToTextRange(quoteToProse))
        XCTAssertFalse(controller.applySemanticInlineMarkToTextRange(quoteToProse, mark: .bold))
        XCTAssertEqual(controller.text, original)

        let withCode = MarkdownEditorController(text: "Before\n\n```\ncode\n```\n\nAfter")
        let acrossCode = selection(.init(blockID: "block-0", offset: 2),
                                   .init(blockID: "block-2", offset: 2))
        XCTAssertFalse(withCode.canApplySemanticInlineMarkToTextRange(acrossCode))
        XCTAssertFalse(withCode.applySemanticInlineMarkToTextRange(acrossCode, mark: .italic))
        XCTAssertFalse(withCode.canUndo)
    }
}
