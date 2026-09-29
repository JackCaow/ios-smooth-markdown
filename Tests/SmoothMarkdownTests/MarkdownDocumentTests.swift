import XCTest
@testable import SmoothMarkdown

final class MarkdownDocumentTests: XCTestCase {
    func testLosslessRoundTripForUnsupportedAndWhitespaceVariants() {
        let sources = [
            "", "\n\n", "Plain", "Plain\n", "Plain\n\n\nNext\n",
            "# Heading\nParagraph without a blank line", "~~~mermaid theme=dark\ngraph LR\nA --> B\n~~~",
            "$$\nE = mc^2\n$$\n", "<details>\n<summary>More</summary>\nBody\n</details>",
            "5. Five\n6. Six\n", "| A | B |\n|---|---|\n| 1 | 2 |\n",
            "Emoji 😀\r\n\r\n> quote\r\n", "```swift\n``` in text\nnot a close\n```\n",
        ]
        let codec = MarkdownDocumentCodec()
        for source in sources { XCTAssertEqual(codec.serialize(codec.parse(source)), source, "round trip: \(source)") }
    }

    func testCodecPreservesMixedSourceExactly() {
        let source = """
        #  Heading *style*

        Paragraph with [link](https://example.com) and `code`.
        Continuation line.

        ~~~~swift title=Demo
        let value = 1
        ~~~~

        ---

        <custom data-x="a">*do not normalize*</custom>

        - [x] Keep this list source
        - [ ] Second item

        """
        let codec = MarkdownDocumentCodec()
        let document = codec.parse(source)
        XCTAssertEqual(document.toMarkdown(), source)
        XCTAssertEqual(codec.serialize(document), source)
        XCTAssertEqual(document.blocks.map(\.kind), [
            .heading(level: 1, markdown: "Heading *style*"),
            .paragraph(markdown: "Paragraph with [link](https://example.com) and `code`.\nContinuation line."),
            .fencedCode(fence: "~~~~", info: "swift title=Demo", code: "let value = 1"),
            .horizontalRule, .raw,
            .list(MarkdownSourceList.parse("- [x] Keep this list source\n- [ ] Second item\n")!),
        ])
        XCTAssertEqual(Set(document.blocks.map(\.id)).count, document.blocks.count)
    }

    func testPreservesCRLFAndFrontmatterAsRaw() {
        let source = "---\r\ntitle: Demo\r\n---\r\n\r\n## Heading\r\n\r\nBody\r\n"
        let document = MarkdownDocumentCodec().parse(source)
        XCTAssertEqual(document.toMarkdown(), source)
        XCTAssertEqual(document.blocks.count, 3)
        XCTAssertEqual(document.blocks.first?.kind, .raw)
        XCTAssertEqual(document.blocks[1].kind, .heading(level: 2, markdown: "Heading"))
        XCTAssertEqual(document.blocks[2].kind, .paragraph(markdown: "Body"))
    }

    func testEditingOneBlockPreservesOtherRawSourceAndIsUndoable() {
        let source = "#  Original\n\n<custom>&nbsp;*literal*</custom>\n\nBefore\n"
        let editor = MarkdownDocumentEditor(markdown: source)
        XCTAssertTrue(editor.replaceBlockContent(id: "block-0", with: "Updated"))
        XCTAssertEqual(editor.document.toMarkdown(), "#  Updated\n\n<custom>&nbsp;*literal*</custom>\n\nBefore\n")
        XCTAssertFalse(editor.replaceBlockContent(id: "block-1", with: "unsafe"))
        XCTAssertTrue(editor.canUndo)
        XCTAssertTrue(editor.undo())
        XCTAssertEqual(editor.document.toMarkdown(), source)
        XCTAssertTrue(editor.redo())
        XCTAssertTrue(editor.document.toMarkdown().contains("#  Updated"))
        XCTAssertTrue(editor.replaceBlockContent(id: "block-2", with: "After"))
        XCTAssertFalse(editor.canRedo)
        XCTAssertFalse(editor.replaceBlockContent(id: "block-2", with: "# New heading"))
        XCTAssertEqual(editor.document.blocks[2].kind, .paragraph(markdown: "After"))
    }

    func testMovePreservesSeparatorSlotsAndUndo() {
        let editor = MarkdownDocumentEditor(markdown: "# First\n\nSecond\n")
        XCTAssertTrue(editor.moveTopLevelBlock(id: "block-1", to: 0))
        XCTAssertEqual(editor.document.toMarkdown(), "Second\n\n# First\n")
        XCTAssertTrue(editor.undo())
        XCTAssertEqual(editor.document.toMarkdown(), "# First\n\nSecond\n")
    }

    func testFencedCodeEditKeepsFenceInfoAndCRLF() {
        let source = "~~~~swift title=Demo\r\nlet a = 1\r\n~~~~\r\n"
        let editor = MarkdownDocumentEditor(markdown: source)
        XCTAssertTrue(editor.replaceBlockContent(id: "block-0", with: "let b = 2"))
        let updated = editor.document.toMarkdown()
        XCTAssertEqual(updated, "~~~~swift title=Demo\r\nlet b = 2\r\n~~~~\r\n")
        XCTAssertEqual(MarkdownDocumentCodec().parse(updated).blocks[0].kind,
                       .fencedCode(fence: "~~~~", info: "swift title=Demo", code: "let b = 2"))
        XCTAssertTrue(editor.undo())
        XCTAssertEqual(editor.document.toMarkdown(), source)
    }

    @MainActor
    func testControllerSemanticEditUsesExistingUndoStack() {
        let controller = MarkdownEditorController(text: "# Start\n\n<custom>raw</custom>")
        XCTAssertEqual(controller.semanticDocument.blocks.count, 2)
        XCTAssertTrue(controller.replaceSemanticBlockContent(id: "block-0", with: "Finish"))
        XCTAssertEqual(controller.text, "# Finish\n\n<custom>raw</custom>")
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, "# Start\n\n<custom>raw</custom>")
        XCTAssertTrue(controller.redo())
        XCTAssertEqual(controller.text, "# Finish\n\n<custom>raw</custom>")
    }
}
