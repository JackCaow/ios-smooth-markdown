import Combine
import Foundation
@testable import SmoothMarkdown
import XCTest

@MainActor
final class MarkdownEditorControllerTests: XCTestCase {
    func testHostEventSourcesTrackEditsUndoModesAndUTF16Selection() {
        let controller = MarkdownEditorController(text: "A")
        var sources: [String] = []
        var modes: [MarkdownEditorMode] = []
        var selections: [NSRange] = []
        let subscriptions = [
            controller.committedTextChanges.sink { sources.append($0) },
            controller.$mode.dropFirst().removeDuplicates().sink { modes.append($0) },
            controller.$selection.dropFirst().removeDuplicates().sink { selections.append($0) },
        ]

        controller.setSelection(NSRange(location: 0, length: 1))
        controller.setSelection(NSRange(location: 0, length: 1))
        controller.updateFromInput(text: "A😀", selection: NSRange(location: 3, length: 0))
        controller.replaceSelection("!")
        controller.mode = .formatted
        controller.mode = .preview
        XCTAssertTrue(controller.undo())
        XCTAssertTrue(controller.redo())
        controller.transaction {
            controller.replaceSelection("x")
            controller.replaceSelection("y")
        }

        XCTAssertEqual(sources, ["A😀", "A😀!", "A😀", "A😀!", "A😀!xy"])
        XCTAssertEqual(modes, [.formatted, .preview])
        XCTAssertEqual(selections, [NSRange(location: 0, length: 1),
                                    NSRange(location: 3, length: 0),
                                    NSRange(location: 4, length: 0),
                                    NSRange(location: 3, length: 0),
                                    NSRange(location: 4, length: 0),
                                    NSRange(location: 5, length: 0),
                                    NSRange(location: 6, length: 0)])
        withExtendedLifetime(subscriptions) { }
    }

    func testSourceCompositionEmitsOnlyFinalCommittedText() {
        let controller = MarkdownEditorController(text: "A")
        var sources: [String] = []
        let subscription = controller.committedTextChanges.sink { sources.append($0) }
        controller.updateFromInput(text: "Ap", selection: NSRange(location: 2, length: 0), isComposing: true)
        controller.updateFromInput(text: "A拼", selection: NSRange(location: 2, length: 0), isComposing: true)
        XCTAssertTrue(sources.isEmpty)
        controller.updateFromInput(text: "A拼", selection: NSRange(location: 2, length: 0), isComposing: false)
        XCTAssertEqual(sources, ["A拼"])
        controller.updateFromInput(text: "A临", selection: NSRange(location: 2, length: 0), isComposing: true)
        controller.updateFromInput(text: "A拼", selection: NSRange(location: 2, length: 0), isComposing: false)
        XCTAssertEqual(sources, ["A拼"])
        withExtendedLifetime(subscription) { }
    }

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

    func testCustomSlashInsertsSeparatedBlockAsOneUndoStep() {
        let controller = MarkdownEditorController(text: "before\n\n/card\n\nafter")
        let block = try! XCTUnwrap(controller.semanticDocument.blocks.first { $0.plainText == "/card" })
        let match = try! XCTUnwrap(controller.slashCommandMatch(
            inBlock: block.id, selection: NSRange(location: 5, length: 0)))
        XCTAssertTrue(controller.applyCustomSlashCommand("  > Note  ", match: match))
        XCTAssertEqual(controller.text, "before\n\n> Note\n\nafter")
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, "before\n\n/card\n\nafter")
        XCTAssertFalse(controller.canUndo)
    }

    func testCustomSlashRejectsStaleTriggerAndEmptyMarkdown() {
        let controller = MarkdownEditorController(text: "/embed")
        let block = try! XCTUnwrap(controller.semanticDocument.blocks.first)
        let match = try! XCTUnwrap(controller.slashCommandMatch(
            inBlock: block.id, selection: NSRange(location: 6, length: 0)))
        XCTAssertFalse(controller.applyCustomSlashCommand("  ", match: match))
        XCTAssertEqual(controller.text, "/embed")
        controller.replaceRange(match.range, with: "/other")
        XCTAssertFalse(controller.applyCustomSlashCommand("content", match: match))
        XCTAssertEqual(controller.text, "/other")
    }

    func testEditorCapabilitiesFilterCommands() {
        let capabilities = MarkdownEditorCapabilities(disabledCommands: [.bold, .heading2])
        XCTAssertFalse(capabilities.supports(.bold))
        XCTAssertFalse(capabilities.supports(.heading2))
        XCTAssertTrue(capabilities.supports(.italic))
        XCTAssertTrue(MarkdownEditorCapabilities.all.supports(.bold))
        XCTAssertEqual(capabilities.visibleToolbarCommands([.heading2, .italic, .bold, .table]),
                       [.italic, .table])
        XCTAssertEqual(MarkdownEditorCapabilities.all.visibleToolbarCommands([.wikilink, .link],
                                                                               enableWikilinks: false), [.link])
        XCTAssertEqual(MarkdownEditorCapabilities.all.visibleToolbarCommands().first, .bold)
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
