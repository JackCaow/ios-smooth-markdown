#if os(iOS)
import SwiftUI
import XCTest
@testable import SmoothMarkdown

@MainActor
final class MarkdownEditorCustomBlockTests: XCTestCase {
    func testReplacementPreservesNeighborsAndIsUndoable() {
        let original = "# Title\r\n\r\n<callout>old</callout>\r\n\r\nAfter\r\n"
        let controller = MarkdownEditorController(text: original)
        XCTAssertEqual(controller.semanticDocument.blocks[1].kind, .raw)
        XCTAssertTrue(controller.replaceCustomBlockMarkdown(id: "block-1", expectedText: original,
                                                            with: "<callout>new</callout>\r\n"))
        XCTAssertEqual(controller.text, "# Title\r\n\r\n<callout>new</callout>\r\n\r\nAfter\r\n")
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, original)
        XCTAssertTrue(controller.redo())
        XCTAssertTrue(controller.text.contains("new"))
    }

    func testStaleContextAndBoundaryChangingReplacementAreRejected() {
        let original = "<callout>old</callout>\n\nAfter\n"
        let controller = MarkdownEditorController(text: original)
        XCTAssertFalse(controller.replaceCustomBlockMarkdown(id: "block-0", expectedText: original,
                                                             with: "<callout>new</callout>\n# New heading\n"))
        XCTAssertEqual(controller.text, original)
        controller.insertMarkdownBlock("# New")
        let changed = controller.text
        XCTAssertFalse(controller.replaceCustomBlockMarkdown(id: "block-0", expectedText: original,
                                                             with: "<callout>new</callout>\n"))
        XCTAssertEqual(controller.text, changed)
    }

    func testDeletePreservesRemainingSourceAndUndo() {
        let original = "# Title\n\n<callout>old</callout>\n\nAfter\n"
        let controller = MarkdownEditorController(text: original)
        XCTAssertTrue(controller.deleteCustomBlock(id: "block-1", expectedText: original))
        XCTAssertEqual(controller.text, "# Title\n\nAfter\n")
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, original)
    }

    func testPublicEditorAcceptsExplicitMatcherAndBothBuilders() {
        let controller = MarkdownEditorController(text: "<callout>old</callout>\n")
        let editor = SmoothMarkdownEditor(controller: controller,
            customBlockMatcher: { block in
                if case .raw = block.kind { return block.source.hasPrefix("<callout>") }
                return false
            },
            customBlockBuilder: { context in
                AnyView(Button(context.plainText, action: context.edit))
            },
            customBlockEditorBuilder: { context in
                AnyView(Button("Finish", action: context.finishEditing))
            })
        _ = editor
    }
}
#endif
