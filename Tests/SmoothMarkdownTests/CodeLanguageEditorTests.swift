import XCTest
@testable import SmoothMarkdown

@MainActor
final class CodeLanguageEditorTests: XCTestCase {
    func testChangingLanguagePreservesFenceCodeCRLFAndNeighborsWithOneUndoStep() {
        let source = "Before 😀\r\n\r\n  ~~~~swift title=Demo\r\nlet value = 1\r\n  ~~~~\r\n\r\nAfter\r\n"
        let controller = MarkdownEditorController(text: source)
        let document = controller.semanticDocument
        XCTAssertEqual(document.blocks.count, 3)
        let codeID = document.blocks[1].id
        let codeOffset = (source as NSString).range(of: "let value").location
        controller.setSelection(NSRange(location: codeOffset, length: 0))

        XCTAssertTrue(controller.setCodeBlockLanguage(id: codeID, to: "mermaid"))
        let changed = "Before 😀\r\n\r\n  ~~~~mermaid\r\nlet value = 1\r\n  ~~~~\r\n\r\nAfter\r\n"
        XCTAssertEqual(controller.text, changed)
        XCTAssertEqual(controller.selection.location, (changed as NSString).range(of: "let value").location)
        XCTAssertEqual(controller.semanticDocument.blocks[0], document.blocks[0])
        XCTAssertEqual(controller.semanticDocument.blocks[2], document.blocks[2])
        XCTAssertEqual(controller.semanticDocument.blocks[1].kind,
                       .fencedCode(fence: "~~~~", info: "mermaid", code: "let value = 1"))
        XCTAssertTrue(controller.canUndo)
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, source)
        XCTAssertFalse(controller.canUndo)
        XCTAssertTrue(controller.redo())
        XCTAssertEqual(controller.text, changed)

        XCTAssertTrue(controller.setCodeBlockLanguage(id: codeID, to: ""))
        XCTAssertTrue(controller.text.contains("  ~~~~\r\nlet value = 1"))
    }

    func testLanguageCommandRejectsUnsafeInputAndNonCodeBlocksWithoutHistory() {
        let source = "# Title\n\n```kotlin\nprintln(1)\n```\n"
        let controller = MarkdownEditorController(text: source)
        let blocks = controller.semanticDocument.blocks
        XCTAssertFalse(controller.setCodeBlockLanguage(id: blocks[0].id, to: "swift"))
        XCTAssertFalse(controller.setCodeBlockLanguage(id: "missing", to: "swift"))
        XCTAssertFalse(controller.setCodeBlockLanguage(id: blocks[1].id, to: "bad\n# heading"))
        XCTAssertFalse(controller.setCodeBlockLanguage(id: blocks[1].id, to: "py`thon"))
        XCTAssertFalse(controller.setCodeBlockLanguage(id: blocks[1].id, to: "kotlin"))
        XCTAssertEqual(controller.text, source)
        XCTAssertFalse(controller.canUndo)

        XCTAssertTrue(controller.setCodeBlockLanguage(id: blocks[1].id, to: "python"))
        XCTAssertEqual(controller.text, "# Title\n\n```python\nprintln(1)\n```\n")
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, source)
    }
}
