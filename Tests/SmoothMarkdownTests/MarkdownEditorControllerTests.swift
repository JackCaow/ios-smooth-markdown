import Foundation
import SmoothMarkdown
import XCTest

@MainActor
final class MarkdownEditorControllerTests: XCTestCase {
    func testWrapsUTF16SelectionAndRestoresHistory() {
        let controller = MarkdownEditorController(text: "😀hi")
        controller.setSelection(NSRange(location: 2, length: 2))
        controller.applyCommand(.bold)
        XCTAssertEqual(controller.text, "😀**hi**")
        XCTAssertEqual(controller.selection, NSRange(location: 4, length: 2))
        XCTAssertTrue(controller.isDirty)
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, "😀hi")
        XCTAssertTrue(controller.redo())
        XCTAssertEqual(controller.text, "😀**hi**")
        controller.markSaved()
        XCTAssertFalse(controller.isDirty)
    }

    func testFormatsOnlySelectedLinesWhenSelectionEndsAtNewline() {
        let controller = MarkdownEditorController(text: "one\ntwo\nthree")
        controller.setSelection(NSRange(location: 0, length: 8))
        controller.applyCommand(.heading2)
        XCTAssertEqual(controller.text, "## one\n## two\nthree")
    }

    func testTransactionIsOneUndoStep() {
        let controller = MarkdownEditorController(text: "a")
        controller.transaction {
            controller.insertMarkdown("b")
            controller.insertMarkdown("c")
        }
        XCTAssertEqual(controller.text, "abc")
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, "a")
        XCTAssertFalse(controller.canUndo)
    }

    func testFindsAndSelectsNextMatch() {
        let controller = MarkdownEditorController(text: "Alpha beta alpha")
        XCTAssertEqual(controller.findMatches("alpha"), [NSRange(location: 0, length: 5), NSRange(location: 11, length: 5)])
        controller.setSelection(NSRange(location: 0, length: 5))
        XCTAssertEqual(controller.selectNextMatch("alpha"), NSRange(location: 11, length: 5))
    }

    func testFormattedSlashCommandUsesSourceRangeAndOneUndoStep() {
        let controller = MarkdownEditorController(text: "😀\n\n/h2")
        let block = try! XCTUnwrap(controller.semanticDocument.blocks.last)
        let match = try! XCTUnwrap(controller.slashCommandMatch(
            inBlock: block.id, selection: NSRange(location: 3, length: 0)))
        XCTAssertEqual(match.range, NSRange(location: 4, length: 3))
        XCTAssertEqual(match.query, "h2")

        XCTAssertTrue(controller.applySlashCommand(.heading2, match: match))
        XCTAssertEqual(controller.text, "😀\n\n## ")
        XCTAssertEqual(controller.selection, NSRange(location: 7, length: 0))
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, "😀\n\n/h2")
        XCTAssertEqual(controller.selection, NSRange(location: 7, length: 0))
        XCTAssertFalse(controller.canUndo)
        XCTAssertTrue(controller.redo())
        XCTAssertEqual(controller.text, "😀\n\n## ")
        XCTAssertEqual(controller.selection, NSRange(location: 7, length: 0))
    }

    func testSlashCommandRejectsNonPrefixAndStaleTrigger() {
        let controller = MarkdownEditorController(text: "Before /h2\n\n```\n/h2\n```\n\n/task")
        let blocks = controller.semanticDocument.blocks
        XCTAssertNil(controller.slashCommandMatch(inBlock: blocks[0].id,
                                                  selection: NSRange(location: 10, length: 0)))
        XCTAssertNil(controller.slashCommandMatch(inBlock: blocks[1].id,
                                                  selection: NSRange(location: 3, length: 0)))
        let match = try! XCTUnwrap(controller.slashCommandMatch(inBlock: blocks[2].id,
                                                                selection: NSRange(location: 5, length: 0)))
        controller.replaceRange(match.range, with: "/changed")
        let changed = controller.text
        XCTAssertFalse(controller.applySlashCommand(.taskList, match: match))
        XCTAssertEqual(controller.text, changed)
    }

    func testSlashWikilinkLeavesCaretInsideOpeningBrackets() {
        let controller = MarkdownEditorController(text: "/wiki")
        let block = try! XCTUnwrap(controller.semanticDocument.blocks.first)
        let match = try! XCTUnwrap(controller.slashCommandMatch(
            inBlock: block.id, selection: NSRange(location: 5, length: 0)))
        XCTAssertTrue(controller.applySlashCommand(.wikilink, match: match))
        XCTAssertEqual(controller.text, "[[")
        XCTAssertEqual(controller.selection, NSRange(location: 2, length: 0))
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, "/wiki")
    }

    func testParagraphRemovesTaskMarker() {
        let controller = MarkdownEditorController(text: "- [x] done")
        controller.applyCommand(.paragraph)
        XCTAssertEqual(controller.text, "done")
    }

    func testTableInsertionMatchesFlutterDefaults() {
        let controller = MarkdownEditorController()
        controller.insertTable(rows: 2, columns: 2)
        XCTAssertEqual(controller.text, "| Column | Column |\n| --- | --- |\n| Cell | Cell |")
    }

    func testTableStructureEditsKeepAlignmentAndSupportUndo() {
        let controller = MarkdownEditorController(text: "before\n\n| A | B |\n| --- | ---: |\n| 1 | 2 |\n\nafter")
        controller.setSelection(NSRange(location: (controller.text as NSString).range(of: "| 1").location, length: 0))
        XCTAssertTrue(controller.insertTableColumnAfter(0))
        XCTAssertTrue(controller.replaceTableCellText(rowIndex: 0, columnIndex: 1, text: "inserted"))
        XCTAssertTrue(controller.insertTableRowAfter(0))
        XCTAssertEqual(controller.text, "before\n\n| A |  | B |\n| --- | --- | ---: |\n| 1 | inserted | 2 |\n|  |  |  |\n\nafter")
        XCTAssertTrue(controller.undo())
        XCTAssertFalse(controller.text.contains("|  |  |  |"))
    }

    func testTableLookupSkipsFencedCodeAndEscapedPipes() {
        let controller = MarkdownEditorController(text: "```\n| X | Y |\n| --- | --- |\n```\n\n| A \\| B | C |\n| --- | --- |")
        controller.setSelection(NSRange(location: (controller.text as NSString).range(of: "| X").location, length: 0))
        XCTAssertNil(controller.tableAtSelection())
        controller.setSelection(NSRange(location: (controller.text as NSString).range(of: "| A").location, length: 0))
        XCTAssertEqual(controller.tableAtSelection()?.headers, ["A \\| B", "C"])
    }

    func testTableOffsetAfterEmojiUsesUTF16AndLongFenceStaysClosed() {
        let controller = MarkdownEditorController(text: "😀\n\n````\n```\n| X |\n| --- |\n````\n\n| A |\n| --- |")
        controller.setSelection(NSRange(location: (controller.text as NSString).range(of: "| X").location, length: 0))
        XCTAssertNil(controller.tableAtSelection())
        controller.setSelection(NSRange(location: (controller.text as NSString).range(of: "| A").location, length: 0))
        XCTAssertEqual(controller.tableAtSelection()?.headers, ["A"])
    }
}
