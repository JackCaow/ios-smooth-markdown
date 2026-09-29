import XCTest
@testable import SmoothMarkdown
#if canImport(UIKit)
import UIKit
#endif

final class SourceListEditorTests: XCTestCase {
    @MainActor
    func testParentContinuationAfterChildrenStaysEditableAndRoundTrips() {
        let source = "- Before \r\n  - child A\r\n  - child B\r\n\r\n   after\r\n- Keep"
        let controller = MarkdownEditorController(text: source)
        guard case let .list(list) = controller.semanticDocument.blocks[0].kind else {
            return XCTFail("Loose parent paragraph must remain an editable list")
        }
        XCTAssertEqual(controller.semanticDocument.toMarkdown(), source)
        XCTAssertEqual(list.items.count, 4)
        XCTAssertEqual(list.items[0].trailingContinuations.map(\.content), ["after"])
        XCTAssertEqual(list.items[0].trailingContinuations[0].leadingTrivia, "\r\n")
        XCTAssertEqual(list.trailingOwners(after: 2), [0])
        XCTAssertEqual(list.sourceLine(at: 0, trailingIndex: 0)?.content, "after")
        XCTAssertEqual(list.sourceOffset(ofItemAt: 3),
                       ("- Before \r\n  - child A\r\n  - child B\r\n\r\n   after\r\n" as NSString).length)
        XCTAssertEqual(list.items[3].source, "- Keep")
        XCTAssertTrue(controller.updateSemanticList(id: "block-0") {
            $0.replacingTrailingContinuationContent(at: 0, lineIndex: 0, with: "after edit")
        })
        XCTAssertEqual(controller.text, source.replacingOccurrences(of: "   after", with: "   after edit"))
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, source)
    }

    func testUnsafeTrailingBlockDoesNotBecomeEditableParentParagraph() {
        for source in ["- Parent\n  - child\n\n  > quote\n- Keep",
                       "- Parent\n  - child\n\n  # Heading\n- Keep",
                       "- Parent\n  - child\n\n      code\n- Keep"] {
            XCTAssertNil(MarkdownSourceList.parse(source))
            XCTAssertEqual(MarkdownDocumentCodec().parse(source).toMarkdown(), source)
        }
    }
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

    @MainActor
    func testReturnInMiddleSplitsLeafItemAndPreservesMarkersUndo() {
        let source = "# Title\r\n\r\n  7)  Alpha🐱Beta\r\n  8)  Next\r\n\r\nTail\r\n"
        let controller = MarkdownEditorController(text: source)
        XCTAssertTrue(controller.submitSemanticListItem(id: "block-1", at: 0, contentOffset: 7))
        let expected = "# Title\r\n\r\n  7)  Alpha🐱\r\n  8)  Beta\r\n  8)  Next\r\n\r\nTail\r\n"
        XCTAssertEqual(controller.text, expected)
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, source)
        XCTAssertTrue(controller.redo())
        XCTAssertEqual(controller.text, expected)
    }

    @MainActor
    func testReturnAtStartMovesLeafContentToUncheckedTaskSibling() {
        let controller = MarkdownEditorController(text: "- [x] Complete\n- [ ] Next")
        XCTAssertTrue(controller.submitSemanticListItem(id: "block-0", at: 0, contentOffset: 0))
        XCTAssertEqual(controller.text, "- [x] \n- [ ] Complete\n- [ ] Next")
    }

    @MainActor
    func testMiddleReturnRejectsContinuationChildAndSurrogateOffset() {
        let controller = MarkdownEditorController(text: "- Parent\n  - Child\n- Body\n  continuation\n- 🐱tail")
        XCTAssertFalse(controller.submitSemanticListItem(id: "block-0", at: 0, contentOffset: 2))
        XCTAssertFalse(controller.submitSemanticListItem(id: "block-0", at: 2, contentOffset: 2))
        XCTAssertFalse(controller.submitSemanticListItem(id: "block-0", at: 3, contentOffset: 1))
        XCTAssertEqual(controller.text, "- Parent\n  - Child\n- Body\n  continuation\n- 🐱tail")
        XCTAssertFalse(controller.canUndo)
    }

    @MainActor
    func testReturnOutdentsEmptyNestedItemAndKeepsUndoHistory() {
        let source = "# Title\r\n\r\n- Parent\r\n  - \r\n- After\r\n"
        let controller = MarkdownEditorController(text: source)
        XCTAssertTrue(controller.submitSemanticListItem(id: "block-1", at: 1))
        XCTAssertEqual(controller.text, "# Title\r\n\r\n- Parent\r\n- \r\n- After\r\n")
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, source)
        XCTAssertTrue(controller.redo())
        XCTAssertEqual(controller.text, "# Title\r\n\r\n- Parent\r\n- \r\n- After\r\n")
    }

    @MainActor
    func testIndentedRootItemExitsListOnReturn() {
        let controller = MarkdownEditorController(text: "  - \n")
        XCTAssertTrue(controller.submitSemanticListItem(id: "block-0", at: 0))
        XCTAssertEqual(controller.text, "")
        XCTAssertEqual(controller.pendingListParagraph?.sourceOffset, 0)
        XCTAssertTrue(controller.updatePendingListParagraph("Paragraph"))
        XCTAssertEqual(controller.text, "Paragraph")
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, "")
        XCTAssertEqual(controller.pendingListParagraph?.draft, "")
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, "  - \n")
        XCTAssertNil(controller.pendingListParagraph)
    }

    @MainActor
    func testEmptyRootReturnSplitsListAndKeepsParagraphEditableThroughUndoRedo() {
        let source = "# Title\r\n\r\n- Before\r\n- \r\n- After\r\n\r\nTail\r\n"
        let exited = "# Title\r\n\r\n- Before\r\n\r\n- After\r\n\r\nTail\r\n"
        let typed = "# Title\r\n\r\n- Before\r\n\r\nBody 🐱\r\n- After\r\n\r\nTail\r\n"
        let controller = MarkdownEditorController(text: source)
        XCTAssertTrue(controller.submitSemanticListItem(id: "block-1", at: 1))
        XCTAssertEqual(controller.text, exited)
        XCTAssertEqual(controller.pendingListParagraph?.draft, "")
        XCTAssertTrue(controller.updatePendingListParagraph("Body 🐱"))
        XCTAssertEqual(controller.text, typed)
        XCTAssertEqual(controller.semanticDocument.blocks.map(\.plainText), ["Title", "Before", "Body 🐱", "After", "Tail"])
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, exited)
        XCTAssertEqual(controller.pendingListParagraph?.draft, "")
        XCTAssertTrue(controller.redo())
        XCTAssertEqual(controller.text, typed)
        XCTAssertEqual(controller.pendingListParagraph?.draft, "Body 🐱")
        controller.finishPendingListParagraph()
        XCTAssertNil(controller.pendingListParagraph)
        XCTAssertEqual(controller.text, typed)
    }

    @MainActor
    func testEmptyFirstAndLastRootItemsProduceParagraphAtCorrectPosition() {
        let first = MarkdownEditorController(text: "- \n- Next\n")
        XCTAssertTrue(first.submitSemanticListItem(id: "block-0", at: 0))
        XCTAssertEqual(first.text, "- Next\n")
        XCTAssertEqual(first.pendingListParagraph?.sourceOffset, 0)
        XCTAssertTrue(first.updatePendingListParagraph("Intro"))
        XCTAssertEqual(first.text, "Intro\n- Next\n")

        let last = MarkdownEditorController(text: "- Before\n- ")
        XCTAssertTrue(last.submitSemanticListItem(id: "block-0", at: 1))
        XCTAssertEqual(last.text, "- Before\n\n")
        XCTAssertEqual(last.pendingListParagraph?.sourceOffset, (last.text as NSString).length)
        XCTAssertTrue(last.updatePendingListParagraph("Outro"))
        XCTAssertEqual(last.text, "- Before\n\nOutro")
    }

    @MainActor
    func testEmptyRootWithNestedChildDoesNotExitList() {
        let controller = MarkdownEditorController(text: "- \n  - Child\n")
        XCTAssertTrue(controller.submitSemanticListItem(id: "block-0", at: 0))
        XCTAssertEqual(controller.text, "- \n  - Child\n- \n")
        XCTAssertNil(controller.pendingListParagraph)
    }

    #if canImport(UIKit)
    @MainActor
    func testHardwareTabCommandsRouteIndentAndOutdentThroughSourceHistory() {
        let source = "- Parent\n- Child\n"
        let controller = MarkdownEditorController(text: source)
        let field = FormattedListKeyboardTextField()
        field.onIndent = { outdent in
            controller.updateSemanticList(id: "block-0") { list in
                outdent ? list.outdentingItem(at: 1) : list.indentingItem(at: 1)
            }
        }

        let commands = field.keyCommands ?? []
        guard let tab = commands.first(where: { $0.input == "\t" && $0.modifierFlags.isEmpty }),
              let shiftTab = commands.first(where: { $0.input == "\t" && $0.modifierFlags == .shift }) else {
            return XCTFail("List field must register Tab and Shift+Tab")
        }
        XCTAssertTrue(tab.wantsPriorityOverSystemBehavior)
        XCTAssertTrue(shiftTab.wantsPriorityOverSystemBehavior)
        _ = field.perform(tab.action)
        XCTAssertEqual(controller.text, "- Parent\n  - Child\n")
        _ = field.perform(shiftTab.action)
        XCTAssertEqual(controller.text, source)
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, "- Parent\n  - Child\n")
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, source)
    }

    @MainActor
    func testListTextFieldReturnsCollapsedCaretOffset() {
        let field = FormattedListKeyboardTextField()
        field.text = "Alpha🐱Beta"
        var submitted: Int?
        field.onReturnAtCaret = { submitted = $0 }
        let caret = field.position(from: field.beginningOfDocument, offset: 7)!
        field.selectedTextRange = field.textRange(from: caret, to: caret)
        XCTAssertTrue(field.submitAtCurrentCaret())
        XCTAssertEqual(submitted, 7)
        let end = field.endOfDocument
        field.selectedTextRange = field.textRange(from: caret, to: end)
        submitted = nil
        XCTAssertFalse(field.submitAtCurrentCaret())
        XCTAssertNil(submitted)
    }
    #endif
}
