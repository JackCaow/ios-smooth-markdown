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

    func testParagraphRemovesTaskMarker() {
        let controller = MarkdownEditorController(text: "- [x] done")
        controller.applyCommand(.paragraph)
        XCTAssertEqual(controller.text, "done")
    }
}
