import XCTest
@testable import SmoothMarkdown

final class SourceListEditorTests: XCTestCase {
    func testMixedListRoundTripsMarkersIndentAndLineEndings() {
        let source = "Intro\r\n\r\n  7)  Seven\r\n    8) Eight\r\n\t* [X]\tDone\r\n\t- [ ] Pending\r\n\r\n<custom>raw</custom>\r\n"
        let document = MarkdownDocumentCodec().parse(source)
        XCTAssertEqual(document.toMarkdown(), source)
        guard case let .list(list) = document.blocks[1].kind else { return XCTFail("Expected editable list") }
        XCTAssertEqual(list.items.map(\.marker), ["7)", "8)", "*", "-"])
        XCTAssertEqual(list.items.map(\.indent), ["  ", "    ", "\t", "\t"])
        XCTAssertEqual(list.items.map(\.kind), [.ordered, .ordered, .task, .task])
        XCTAssertEqual(list.items.map(\.checked), [nil, nil, true, false])
        XCTAssertEqual(document.blocks[2].kind, .raw)
    }

    @MainActor
    func testItemTextAndTaskStatePreserveUntouchedSourceAndUndo() {
        let source = "# Title\r\n\r\n  7)  Seven\r\n    8) Eight\r\n\t- [ ] Pending\r\n\r\n<custom>raw</custom>\r\n"
        let controller = MarkdownEditorController(text: source)
        XCTAssertTrue(controller.updateSemanticList(id: "block-1") { $0.replacingItemContent(at: 1, with: "Eighth **bold**") })
        XCTAssertTrue(controller.updateSemanticList(id: "block-1") { $0.settingTaskChecked(at: 2, to: true) })
        let changed = "# Title\r\n\r\n  7)  Seven\r\n    8) Eighth **bold**\r\n\t- [x] Pending\r\n\r\n<custom>raw</custom>\r\n"
        XCTAssertEqual(controller.text, changed)
        XCTAssertTrue(controller.undo())
        XCTAssertTrue(controller.text.contains("\t- [ ] Pending\r\n"))
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, source)
        XCTAssertTrue(controller.redo())
        XCTAssertTrue(controller.redo())
        XCTAssertEqual(controller.text, changed)
    }

    @MainActor
    func testContinuationAndNestedItemsEditWithoutRewritingOtherSource() {
        let source = "# Title\r\n\r\n- Parent\r\n  parent continuation\r\n  + Child **bold**\r\n    child continuation\r\n    second line\r\n- Sibling\r\n\r\n<custom>raw</custom>\r\n"
        let controller = MarkdownEditorController(text: source)
        guard case let .list(list) = controller.semanticDocument.blocks[1].kind else {
            return XCTFail("Nested multiline list should be editable in Blocks")
        }
        XCTAssertEqual(list.items.map(\.indent), ["", "  ", ""])
        XCTAssertEqual(list.items[0].continuations.map(\.content), ["parent continuation"])
        XCTAssertEqual(list.items[1].continuations.map(\.content), ["child continuation", "second line"])
        XCTAssertEqual(controller.semanticDocument.blocks[1].plainText,
                       "Parent\nparent continuation\nChild **bold**\nchild continuation\nsecond line\nSibling")
        XCTAssertTrue(controller.updateSemanticList(id: "block-1") {
            $0.replacingItemContent(at: 1, with: "Child revised")
        })
        XCTAssertTrue(controller.updateSemanticList(id: "block-1") {
            $0.replacingContinuationContent(at: 1, lineIndex: 0, with: "child continuation revised")
        })
        let changed = source.replacingOccurrences(of: "  + Child **bold**\r\n    child continuation",
                                                  with: "  + Child revised\r\n    child continuation revised")
        XCTAssertEqual(controller.text, changed)
        XCTAssertTrue(controller.undo())
        XCTAssertTrue(controller.text.contains("  + Child revised\r\n    child continuation\r\n"))
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, source)
        XCTAssertTrue(controller.redo())
        XCTAssertTrue(controller.redo())
        XCTAssertEqual(controller.text, changed)
    }

    @MainActor
    func testContinuationListAndInvalidEdits() {
        let source = "- First\n  continuation\n\n- Simple\n"
        let controller = MarkdownEditorController(text: source)
        guard case let .list(list) = controller.semanticDocument.blocks[0].kind else {
            return XCTFail("Paragraph continuation should be an editable list")
        }
        XCTAssertEqual(list.items[0].continuations.map(\.content), ["continuation"])
        XCTAssertTrue(controller.updateSemanticList(id: "block-0") {
            $0.replacingContinuationContent(at: 0, lineIndex: 0, with: "continued")
        })
        XCTAssertEqual(controller.text, "- First\n  continued\n\n- Simple\n")
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, source)
        XCTAssertFalse(controller.updateSemanticList(id: "block-1") { $0.settingTaskChecked(at: 0, to: true) })
        XCTAssertFalse(controller.updateSemanticList(id: "block-1") { $0.replacingItemContent(at: 0, with: "two\nlines") })
        XCTAssertFalse(controller.updateSemanticList(id: "block-0") {
            $0.replacingContinuationContent(at: 0, lineIndex: 0, with: "- new item")
        })
        XCTAssertEqual(controller.text, source)
        XCTAssertTrue(controller.canRedo)
    }

    @MainActor
    func testIndentAndOutdentMoveNestedSubtreeWithoutRewritingOtherSource() {
        let source = "# Title\r\n\r\n- Parent\r\n- Child\r\n  continuation\r\n  - Grandchild\r\n- After\r\n\r\nEnd\r\n"
        let controller = MarkdownEditorController(text: source)
        let indented = "# Title\r\n\r\n- Parent\r\n  - Child\r\n    continuation\r\n    - Grandchild\r\n- After\r\n\r\nEnd\r\n"

        XCTAssertTrue(controller.updateSemanticList(id: "block-1") { $0.indentingItem(at: 1) })
        XCTAssertEqual(controller.text, indented)
        XCTAssertTrue(controller.updateSemanticList(id: "block-1") { $0.outdentingItem(at: 1) })
        XCTAssertEqual(controller.text, source)
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, indented)
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, source)
        XCTAssertTrue(controller.redo())
        XCTAssertTrue(controller.redo())
        XCTAssertEqual(controller.text, source)
    }

    @MainActor
    func testIndentRejectsFirstItemAndOutdentRejectsRootItem() {
        let source = "- Parent\n- Child\n"
        let controller = MarkdownEditorController(text: source)
        XCTAssertFalse(controller.updateSemanticList(id: "block-0") { $0.indentingItem(at: 0) })
        XCTAssertFalse(controller.updateSemanticList(id: "block-0") { $0.outdentingItem(at: 1) })
        XCTAssertEqual(controller.text, source)
        XCTAssertFalse(controller.canUndo)
    }

    @MainActor
    func testReturnAddsSiblingAfterNestedSubtreeAndPreservesOtherSource() {
        let source = "# Title\r\n\r\n7) Parent\r\n   - Child\r\n8) Next\r\n\r\nEnd\r\n"
        let controller = MarkdownEditorController(text: source)
        XCTAssertTrue(controller.updateSemanticList(id: "block-1") { $0.insertingEmptyItem(after: 0) })
        XCTAssertEqual(controller.text,
                       "# Title\r\n\r\n7) Parent\r\n   - Child\r\n8) \r\n8) Next\r\n\r\nEnd\r\n")
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, source)
        XCTAssertTrue(controller.redo())
        XCTAssertTrue(controller.text.contains("8) \r\n8) Next"))
    }

    func testReturnAddsUncheckedTaskAndHandlesLastLineWithoutNewline() {
        let task = MarkdownSourceList.parse("- [x] Done\n")!
        XCTAssertEqual(task.insertingEmptyItem(after: 0)?.toMarkdown(), "- [x] Done\n- [ ] \n")
        let bullet = MarkdownSourceList.parse("* Last")!
        XCTAssertEqual(bullet.insertingEmptyItem(after: 0)?.toMarkdown(), "* Last\n* ")
    }
}
