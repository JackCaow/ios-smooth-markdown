import XCTest
@testable import SmoothMarkdown

@MainActor
final class CrossBlockEditorTests: XCTestCase {
    private func range(_ first: String, _ start: Int, _ last: String, _ end: Int)
        -> MarkdownSemanticTextSelection {
        .init(anchor: .init(blockID: first, offset: start),
              focus: .init(blockID: last, offset: end))
    }

    func testCharacterRangeCopiesExactSourceAndReplacesWithOneUndoStep() {
        let original = "Lead\r\n\r\n# One 😀\r\n\r\nSecond\r\n\r\nKeep\r\n"
        let controller = MarkdownEditorController(text: original)
        let selected = range("block-1", 4, "block-2", 3)
        XCTAssertEqual(controller.copySemanticTextRange(selected), "😀\r\n\r\nSec")
        XCTAssertTrue(controller.canReplaceSemanticTextRange(selected, with: "X"))
        XCTAssertTrue(controller.replaceSemanticTextRange(selected, with: "X"))
        XCTAssertEqual(controller.text, "Lead\r\n\r\n# One Xond\r\n\r\nKeep\r\n")
        XCTAssertEqual(controller.selection, NSRange(location: ("Lead\r\n\r\n# One X" as NSString).length, length: 0))
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, original)
        XCTAssertFalse(controller.canUndo)
        XCTAssertTrue(controller.redo())
        XCTAssertEqual(controller.text, "Lead\r\n\r\n# One Xond\r\n\r\nKeep\r\n")
    }

    func testReverseCharacterRangeAndEmojiBoundary() {
        let original = "Hello 😀\n\nworld!\n\nKeep"
        let controller = MarkdownEditorController(text: original)
        let reversed = range("block-1", 5, "block-0", 4)
        XCTAssertEqual(controller.copySemanticTextRange(reversed), "o 😀\n\nworld")
        XCTAssertTrue(controller.deleteSemanticTextRange(reversed))
        XCTAssertEqual(controller.text, "Hell!\n\nKeep")
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, original)
        let surrogateSplit = range("block-0", 7, "block-1", 1)
        XCTAssertNil(controller.copySemanticTextRange(surrogateSplit))
        XCTAssertFalse(controller.deleteSemanticTextRange(surrogateSplit))
        XCTAssertEqual(controller.text, original)
    }

    func testNativeDragHighlightsExactUTF16FragmentsInBothDirections() {
        let controller = MarkdownEditorController(text: "First 😀\n\n# Middle\n\nLast line")
        let selected = range("block-2", 4, "block-0", 6)
        let expected: [String: NSRange] = [
            "block-0": NSRange(location: 6, length: 2),
            "block-1": NSRange(location: 0, length: 6),
            "block-2": NSRange(location: 0, length: 4),
        ]
        XCTAssertEqual(controller.semanticTextHighlightRanges(selected), expected)
        XCTAssertEqual(controller.copySemanticTextRange(selected), "😀\n\n# Middle\n\nLast")
        XCTAssertEqual(controller.semanticTextHighlightRanges(range("block-0", 6, "block-2", 4)), expected)
        XCTAssertNil(controller.semanticTextHighlightRanges(range("block-0", 7, "block-1", 1)),
                     "A drag endpoint must never split an emoji surrogate pair")
    }

    func testNativeDragHighlightsWholeStructuredBlockBetweenProseEndpoints() {
        let controller = MarkdownEditorController(text: "Before\n\n- item\n\nAfter")
        let selected = range("block-0", 2, "block-2", 2)
        let highlights = controller.semanticTextHighlightRanges(selected)
        XCTAssertEqual(highlights?["block-0"], NSRange(location: 2, length: 4))
        XCTAssertNotNil(highlights?["block-1"], "The complete list row must be visibly selected")
        XCTAssertEqual(highlights?["block-2"], NSRange(location: 0, length: 2))
    }

    func testCharacterCopyIncludesOnlySelectedHeadingMarkers() {
        let controller = MarkdownEditorController(text: "# Start\n\n# End\n\nTail")
        XCTAssertEqual(controller.copySemanticTextRange(range("block-0", 0, "block-1", 2)),
                       "# Start\n\n# En")
        XCTAssertEqual(controller.copySemanticTextRange(range("block-0", 3, "block-1", 0)),
                       "rt\n\n")
    }

    func testCharacterRangeRejectsStructuralAndInvalidEndpoints() {
        let controller = MarkdownEditorController(text: "Before\n\n# Heading\n\nAfter")
        let selected = range("block-0", 3, "block-1", 2)
        XCTAssertFalse(controller.replaceSemanticTextRange(selected, with: "\n\n- item\n\n"))
        XCTAssertEqual(controller.text, "Before\n\n# Heading\n\nAfter")
        XCTAssertFalse(controller.canUndo)

        let list = MarkdownEditorController(text: "Before\n\n- item\n\nAfter")
        let crossingList = range("block-0", 2, "block-2", 2)
        XCTAssertEqual(list.copySemanticTextRange(crossingList), "fore\n\n- item\n\nAf")
        XCTAssertTrue(list.deleteSemanticTextRange(crossingList))
        XCTAssertEqual(list.text, "Beter")
        XCTAssertTrue(list.undo())
        XCTAssertEqual(list.text, "Before\n\n- item\n\nAfter")
        XCTAssertNil(list.copySemanticTextRange(range("block-1", 2, "block-2", 2)),
                     "Partial endpoints inside a list require a separate source coordinate API")
        XCTAssertNil(list.copySemanticTextRange(range("block-0", 2, "missing", 0)))
    }

    func testCharacterRangeCopiesAndReplacesAcrossCompleteListCodeAndTable() {
        let original = "Start alpha\n\n- one\n- two\n\n```swift\nlet x = 1\n```\n\n| A | B |\n| --- | --- |\n| 1 | 2 |\n\nEnd omega\n\nKeep"
        let controller = MarkdownEditorController(text: original)
        let selected = range("block-4", 3, "block-0", 6)
        XCTAssertEqual(controller.copySemanticTextRange(selected),
                       "alpha\n\n- one\n- two\n\n```swift\nlet x = 1\n```\n\n| A | B |\n| --- | --- |\n| 1 | 2 |\n\nEnd")
        XCTAssertFalse(controller.canApplySemanticInlineMarkToTextRange(selected))
        XCTAssertFalse(controller.applySemanticInlineMarkToTextRange(selected, mark: .bold))
        XCTAssertEqual(controller.text, original)
        XCTAssertTrue(controller.canReplaceSemanticTextRange(selected, with: "X"))
        XCTAssertTrue(controller.replaceSemanticTextRange(selected, with: "X"))
        XCTAssertEqual(controller.text, "Start X omega\n\nKeep")
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, original)
        XCTAssertFalse(controller.canUndo)
        XCTAssertTrue(controller.redo())
        XCTAssertEqual(controller.text, "Start X omega\n\nKeep")
    }

    func testPartialCodeToProsePreservesFenceTriviaAndOneUndo() {
        let original = "Before\r\n\r\n```swift\r\nalpha beta\r\n```\r\n\r\n| A | B |\r\n| - | - |\r\n| 1 | 2 |\r\n\r\nAfter omega\r\n\r\nKeep"
        let controller = MarkdownEditorController(text: original)
        let selected = range("block-1", 6, "block-3", 5)
        XCTAssertEqual(controller.copySemanticTextRange(selected),
                       "```swift\r\nbeta\r\n```\r\n\r\n| A | B |\r\n| - | - |\r\n| 1 | 2 |\r\n\r\nAfter")
        XCTAssertEqual(controller.semanticTextHighlightRanges(selected)?["block-1"],
                       NSRange(location: 6, length: 4))
        XCTAssertTrue(controller.canReplaceSemanticTextRange(selected, with: "X"))
        XCTAssertTrue(controller.replaceSemanticTextRange(selected, with: "X"))
        XCTAssertEqual(controller.text,
                       "Before\r\n\r\n```swift\r\nalpha X\r\n```\r\n\r\n omega\r\n\r\nKeep")
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, original)
        XCTAssertFalse(controller.canUndo)
    }

    func testPartialProseToCodeRetainsOpeningFenceAndCodeSuffix() {
        let original = "Before alpha\r\n\r\nMiddle\r\n\r\n~~~txt\r\ncode omega\r\n~~~\r\n\r\nKeep"
        let controller = MarkdownEditorController(text: original)
        let selected = range("block-0", 7, "block-2", 5)
        XCTAssertEqual(controller.copySemanticTextRange(selected),
                       "alpha\r\n\r\nMiddle\r\n\r\n~~~txt\r\ncode \r\n~~~\r\n")
        XCTAssertTrue(controller.replaceSemanticTextRange(selected, with: "X"))
        XCTAssertEqual(controller.text,
                       "Before X\r\n\r\n~~~txt\r\nomega\r\n~~~\r\n\r\nKeep")
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, original)
        XCTAssertFalse(controller.canUndo)
    }

    func testReverseCodeRangeAndStaleSnapshotStayAtomic() {
        let original = "Before alpha\n\n```txt\ncode omega\n```\n\nKeep"
        let controller = MarkdownEditorController(text: original)
        let selected = MarkdownSemanticTextSelection(
            anchor: .init(blockID: "block-1", offset: 5),
            focus: .init(blockID: "block-0", offset: 7), source: original)
        XCTAssertEqual(controller.copySemanticTextRange(selected),
                       "alpha\n\n```txt\ncode \n```\n")
        XCTAssertTrue(controller.deleteSemanticTextRange(selected))
        XCTAssertEqual(controller.text, "Before \n\n```txt\nomega\n```\n\nKeep")
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, original)
        controller.replaceRange(NSRange(location: 0, length: 0), with: "New\n\n")
        let changed = controller.text
        XCTAssertNil(controller.copySemanticTextRange(selected))
        XCTAssertFalse(controller.deleteSemanticTextRange(selected))
        XCTAssertEqual(controller.text, changed)
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, original)
        XCTAssertFalse(controller.canUndo)
    }

    func testCodeAndHeadingEndpointsKeepHeadingMarker() {
        let original = "```js\nlet value\n```\n\n# Heading tail\n\nEnd"
        let controller = MarkdownEditorController(text: original)
        let selected = range("block-0", 4, "block-1", 7)
        XCTAssertTrue(controller.replaceSemanticTextRange(selected, with: "X"))
        XCTAssertEqual(controller.text, "```js\nlet X\n```\n\n#  tail\n\nEnd")
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, original)

        let headingFirst = MarkdownEditorController(text: "# Heading tail\n\n```js\nlet value\n```\n\nEnd")
        XCTAssertTrue(headingFirst.deleteSemanticTextRange(range("block-0", 8, "block-1", 4)))
        XCTAssertEqual(headingFirst.text, "# Heading \n\n```js\nvalue\n```\n\nEnd")
        XCTAssertTrue(headingFirst.undo())
    }

    func testListToCodeCopyBalancesBothMarkersWithoutMutatingSource() {
        let original = "- first item\n\n```txt\ncode tail\n```\n\nKeep"
        let controller = MarkdownEditorController(text: original)
        let selected = MarkdownSemanticTextSelection(
            anchor: .init(blockID: "block-0", offset: 6, listItemIndex: 0),
            focus: .init(blockID: "block-1", offset: 4), source: original)
        XCTAssertEqual(controller.copySemanticTextRange(selected),
                       "- item\n\n```txt\ncode\n```\n")
        XCTAssertFalse(controller.canReplaceSemanticTextRange(selected))
        XCTAssertEqual(controller.text, original)
        XCTAssertFalse(controller.canUndo)
    }

    func testWithinCodeBodyUsesExactSourceAndRejectsUnsafeFence() {
        let original = "Intro\n\n```swift\nfirst 😀 line\n```\n\nEnd"
        let controller = MarkdownEditorController(text: original)
        let selected = range("block-1", 6, "block-1", 8)
        XCTAssertEqual(controller.copySemanticTextRange(selected), "😀")
        XCTAssertTrue(controller.deleteSemanticTextRange(selected))
        XCTAssertEqual(controller.text, "Intro\n\n```swift\nfirst  line\n```\n\nEnd")
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, original)
        XCTAssertFalse(controller.deleteSemanticTextRange(range("block-1", 7, "block-1", 8)),
                       "A code endpoint cannot split a UTF-16 surrogate pair")
        XCTAssertFalse(controller.replaceSemanticTextRange(selected, with: "\n```\n"))
        XCTAssertEqual(controller.text, original)
        XCTAssertFalse(controller.canUndo)
    }

    func testCharacterRangeDeletesCompleteRuleAndRawHtmlWithoutChangingOuterSource() {
        let original = "Start alpha\r\n\r\n---\r\n\r\n<div>raw</div>\r\n\r\nEnd omega\r\n\r\nKeep"
        let controller = MarkdownEditorController(text: original)
        let selected = range("block-0", 6, "block-3", 3)
        XCTAssertEqual(controller.copySemanticTextRange(selected),
                       "alpha\r\n\r\n---\r\n\r\n<div>raw</div>\r\n\r\nEnd")
        XCTAssertTrue(controller.deleteSemanticTextRange(selected))
        XCTAssertEqual(controller.text, "Start  omega\r\n\r\nKeep")
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, original)
    }

    func testTextRangeFormatsPartialHeadingAndParagraphWithoutChangingSourceTrivia() {
        let original = "Lead\r\n\r\n# One 😀\r\n\r\nSecond text\r\n\r\nTail"
        let controller = MarkdownEditorController(text: original)
        let selected = range("block-2", 6, "block-1", 4)
        XCTAssertTrue(controller.applySemanticInlineMarkToTextRange(selected, mark: .bold))
        XCTAssertEqual(controller.text,
                       "Lead\r\n\r\n# One **😀**\r\n\r\n**Second** text\r\n\r\nTail")
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, original)
        XCTAssertFalse(controller.canUndo)
    }

    func testTextRangeFormatsEveryTouchedPlainTextRowInOneUndoStep() {
        let original = "Alpha one\n\n# Middle\n\nOmega last"
        let controller = MarkdownEditorController(text: original)
        XCTAssertTrue(controller.applySemanticInlineMarkToTextRange(
            range("block-0", 6, "block-2", 5), mark: .italic))
        XCTAssertEqual(controller.text, "Alpha *one*\n\n# *Middle*\n\n*Omega* last")
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, original)
        XCTAssertFalse(controller.canUndo)
    }

    func testTextRangeRejectsNestedSyntaxAndUnsafeLinkAtomically() {
        let original = "Before\n\n# **nested**\n\nAfter"
        let controller = MarkdownEditorController(text: original)
        let selected = range("block-0", 2, "block-2", 3)
        XCTAssertFalse(controller.applySemanticInlineMarkToTextRange(selected, mark: .bold))
        XCTAssertEqual(controller.text, original)
        XCTAssertFalse(controller.canUndo)

        let plain = MarkdownEditorController(text: "First\n\nSecond")
        XCTAssertFalse(plain.applySemanticInlineMarkToTextRange(
            range("block-0", 0, "block-1", 6), mark: .link(destination: "javascript:alert(1)")))
        XCTAssertEqual(plain.text, "First\n\nSecond")
        XCTAssertFalse(plain.canUndo)
    }

    func testTextRangeItalicPreservesExistingBoldAcrossWholeHeadingAndParagraph() {
        let original = "# First **bold** end\n\nSecond [link](https://example.com) end\n\nTail"
        let controller = MarkdownEditorController(text: original)
        XCTAssertTrue(controller.applySemanticInlineMarkToTextRange(
            range("block-0", 0, "block-1",
                  ("Second [link](https://example.com) end" as NSString).length), mark: .italic))
        XCTAssertEqual(controller.text, "# *First **bold** end*\n\n"
                       + "*Second [link](https://example.com) end*\n\nTail")
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, original)
        XCTAssertFalse(controller.canUndo)
    }

    func testCopiesExactMarkdownAndDeletesRangeWithOneUndoStep() {
        let original = "# One 😀\r\n\r\nSecond\r\n\r\nThird\r\n"
        let controller = MarkdownEditorController(text: original)
        XCTAssertEqual(controller.copySemanticBlockRange(from: "block-1", to: "block-0"),
                       "# One 😀\r\n\r\nSecond\r\n")
        XCTAssertTrue(controller.canDeleteSemanticBlockRange(from: "block-0", to: "block-1"))
        XCTAssertTrue(controller.deleteSemanticBlockRange(from: "block-1", to: "block-0"))
        XCTAssertEqual(controller.text, "Third\r\n")
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, original)
        XCTAssertFalse(controller.canUndo)
        XCTAssertTrue(controller.redo())
        XCTAssertEqual(controller.text, "Third\r\n")
    }

    func testDeletionKeepsUntouchedOuterBlocksAndRejectsMerge() {
        let original = "Before\r\n\r\n# Heading\r\n\r\n---\r\n\r\nAfter"
        let controller = MarkdownEditorController(text: original)
        XCTAssertTrue(controller.deleteSemanticBlockRange(from: "block-1", to: "block-2"))
        XCTAssertEqual(controller.text, "Before\r\n\r\nAfter")
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, original)

        let unsafe = MarkdownEditorController(text: "Before\n```\nx\n```\n# Heading\nAfter")
        XCTAssertEqual(unsafe.semanticDocument.blocks.count, 4)
        XCTAssertFalse(unsafe.canDeleteSemanticBlockRange(from: "block-1", to: "block-2"))
        XCTAssertFalse(unsafe.deleteSemanticBlockRange(from: "block-1", to: "block-2"))
        XCTAssertEqual(unsafe.text, "Before\n```\nx\n```\n# Heading\nAfter")
        XCTAssertFalse(unsafe.canUndo)
    }

    func testWholeListCanBeCopiedAndDeletedWithUndoWhileInvalidRangeDoesNothing() {
        let original = "Before\n\n- item\n\nAfter"
        let controller = MarkdownEditorController(text: original)
        XCTAssertEqual(controller.copySemanticBlockRange(from: "block-0", to: "block-1"),
                       "Before\n\n- item\n")
        XCTAssertTrue(controller.canDeleteSemanticBlockRange(from: "block-0", to: "block-1"))
        XCTAssertNil(controller.copySemanticBlockRange(from: "block-0", to: "missing"))
        XCTAssertNil(controller.copySemanticBlockRange(from: "block-0", to: "block-0"))
        XCTAssertTrue(controller.deleteSemanticBlockRange(from: "block-0", to: "block-1"))
        XCTAssertEqual(controller.text, "After")
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, original)
        XCTAssertFalse(controller.canUndo)
    }

    func testWholeTableAndListDeletionKeepsUntouchedOuterBlocks() {
        let original = "Before\n\n- item\n\n| A | B |\n| - | - |\n| 1 | 2 |\n\nAfter"
        let controller = MarkdownEditorController(text: original)
        XCTAssertEqual(controller.semanticDocument.blocks.count, 4)
        XCTAssertTrue(controller.canDeleteSemanticBlockRange(from: "block-1", to: "block-2"))
        XCTAssertTrue(controller.deleteSemanticBlockRange(from: "block-2", to: "block-1"))
        XCTAssertEqual(controller.text, "Before\n\nAfter")
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, original)
        XCTAssertFalse(controller.canUndo)
    }

    func testRawHTMLBlockCanBeDeletedOnlyAsACompleteTopLevelRow() {
        let original = "Before\n\n<aside>opaque</aside>\n\n# Heading\n\nAfter"
        let controller = MarkdownEditorController(text: original)
        XCTAssertEqual(controller.semanticDocument.blocks.count, 4)
        XCTAssertTrue(controller.deleteSemanticBlockRange(from: "block-1", to: "block-2"))
        XCTAssertEqual(controller.text, "Before\n\nAfter")
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, original)
    }

    func testDeletingAllStructuredBlocksClearsTrailingTriviaAndUndoes() {
        let original = "- item\n\n| A | B |\n| - | - |\n| 1 | 2 |\n\n"
        let controller = MarkdownEditorController(text: original)
        XCTAssertEqual(controller.semanticDocument.blocks.count, 2)
        XCTAssertTrue(controller.deleteSemanticBlockRange(from: "block-0", to: "block-1"))
        XCTAssertEqual(controller.text, "")
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, original)
    }
}
