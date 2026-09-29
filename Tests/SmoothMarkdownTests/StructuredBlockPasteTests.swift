import Foundation
import Markdown
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

    func testPastingChildListIntoFormattedItemKeepsMarkersSiblingAndOneUndoStep() {
        let original = "# Title\r\n\r\n- Parent target\r\n- Keep **exact**\r\n\r\nTail"
        let controller = MarkdownEditorController(text: original)
        let focus = controller.replaceSemanticListLineWithMarkdownBlocks(
            id: "block-1", index: 0,
            range: NSRange(location: ("Parent " as NSString).length,
                           length: ("target" as NSString).length),
            markdown: "- child A\n- child B")
        XCTAssertEqual(controller.text,
                       "# Title\r\n\r\n- Parent \r\n  - child A\r\n  - child B\r\n- Keep **exact**\r\n\r\nTail")
        XCTAssertEqual(focus?.index, 2)
        XCTAssertEqual(focus?.offset, ("child B" as NSString).length)
        XCTAssertEqual(controller.selectedText, "")
        XCTAssertEqual(controller.selection.location,
                       ("# Title\r\n\r\n- Parent \r\n  - child A\r\n  - child B" as NSString).length)
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, original)
        XCTAssertFalse(controller.canUndo)
        XCTAssertTrue(controller.redo())
        XCTAssertTrue(controller.text.contains("  - child B"))
    }

    func testTaskAndOrderedParentUseMarkerColumnAndKeepSource() {
        let original = "7) Parent\n   - [x] Task target\n   - Keep\n8) Next"
        let controller = MarkdownEditorController(text: original)
        let focus = controller.replaceSemanticListLineWithMarkdownBlocks(
            id: "block-0", index: 1,
            range: NSRange(location: ("Task " as NSString).length,
                           length: ("target" as NSString).length),
            markdown: "+ one\n+ two")
        XCTAssertEqual(controller.text,
                       "7) Parent\n   - [x] Task \n     + one\n     + two\n   - Keep\n8) Next")
        XCTAssertEqual(focus?.index, 3)
        XCTAssertEqual(focus?.offset, 3)
        let parsed = MarkdownSyntax.parse(controller.text)
        guard let outer = parsed.child(at: 0) as? OrderedList,
              let first = outer.child(at: 0) as? Markdown.ListItem,
              let tasks = first.child(at: 1) as? UnorderedList,
              let task = tasks.child(at: 0) as? Markdown.ListItem,
              let children = task.child(at: 1) as? UnorderedList else {
            return XCTFail("Pasted rows must remain nested under the checked task")
        }
        XCTAssertEqual(task.checkbox, .checked)
        XCTAssertEqual(children.childCount, 2)
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, original)
    }

    func testPastingAfterListContinuationKeepsParentAndNextItemEditable() {
        let original = "- Parent\n  continuation target\n- Keep"
        let controller = MarkdownEditorController(text: original)
        let focus = controller.replaceSemanticListLineWithMarkdownBlocks(
            id: "block-0", index: 0, continuationIndex: 0,
            range: NSRange(location: ("continuation " as NSString).length,
                           length: ("target" as NSString).length),
            markdown: "- child A\n- child B")
        XCTAssertEqual(controller.text,
                       "- Parent\n  continuation \n  - child A\n  - child B\n- Keep")
        XCTAssertEqual(focus?.index, 2)
        guard case let .list(list) = controller.semanticDocument.blocks[0].kind else {
            return XCTFail("Expected editable list")
        }
        XCTAssertEqual(list.items[0].continuations[0].content, "continuation ")
        XCTAssertEqual(list.items[3].content, "Keep")
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, original)
    }

    func testPastedChildContinuationKeepsFocusAtLastVisibleLine() {
        let controller = MarkdownEditorController(text: "- Parent target\n- Keep")
        let focus = controller.replaceSemanticListLineWithMarkdownBlocks(
            id: "block-0", index: 0,
            range: NSRange(location: ("Parent " as NSString).length,
                           length: ("target" as NSString).length),
            markdown: "- child\n  detail")
        XCTAssertEqual(controller.text, "- Parent \n  - child\n    detail\n- Keep")
        XCTAssertEqual(focus?.index, 1)
        XCTAssertEqual(focus?.continuationIndex, 0)
        XCTAssertEqual(focus?.offset, ("detail" as NSString).length)
    }

    func testNestedPasteRejectsUnsupportedSuffixAndLeavesHistoryUntouched() {
        for suffix in ["# Heading", "> quote", "---", "ordinary tail"] {
            let original = "- Before target \(suffix)\n- Keep"
            let controller = MarkdownEditorController(text: original)
            let range = NSRange(location: ("Before " as NSString).length,
                                length: ("target " as NSString).length)
            XCTAssertNil(controller.replaceSemanticListLineWithMarkdownBlocks(
                id: "block-0", index: 0, range: range,
                markdown: "- first\n- second"))
            XCTAssertEqual(controller.text, original)
            XCTAssertFalse(controller.canUndo)
        }
    }

    func testNestedPasteRejectsPlainLinesAndBrokenUTF16WithoutMutation() {
        let original = "- 😀 target\n- Keep"
        let controller = MarkdownEditorController(text: original)
        XCTAssertNil(controller.replaceSemanticListLineWithMarkdownBlocks(
            id: "block-0", index: 0, range: NSRange(location: 2, length: 0),
            markdown: "- one\n- two"))
        XCTAssertNil(controller.replaceSemanticListLineWithMarkdownBlocks(
            id: "block-0", index: 0, range: NSRange(location: 0, length: 0),
            markdown: "plain\nlines"))
        XCTAssertEqual(controller.text, original)
        XCTAssertFalse(controller.canUndo)
    }
}
