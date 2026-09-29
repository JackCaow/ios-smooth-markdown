import Foundation
import Markdown
import XCTest
@testable import SmoothMarkdown

@MainActor
final class VisibleInlineRangeEditorTests: XCTestCase {
    private func selection(_ source: String, _ first: String, _ start: Int, _ last: String, _ end: Int)
        -> MarkdownVisibleTextSelection {
        .init(source: source, anchor: .init(blockID: first, offset: start),
              focus: .init(blockID: last, offset: end))
    }

    private func visible(_ source: String) -> String {
        let document = MarkdownSyntax.parse(source, useCache: false)
        guard let paragraph = Array(document.children).first as? Paragraph else { return "" }
        return InlineContent.runs(in: paragraph, enableHTML: false).compactMap { run in
            if case let .text(value, _, _, _) = run { return value }
            return nil
        }.joined()
    }

    func testPartialVisibleRangeInsideExistingBoldItalicAndLink() throws {
        let cases: [(String, MarkdownInlineMark)] = [
            ("**bold**", .italic),
            ("*bold*", .bold),
            ("[bold](https://example.com/path)", .italic),
        ]
        for (source, mark) in cases {
            let edited = try XCTUnwrap(MarkdownInlineMarkEditor.applyVerifiedVisibleRange(
                mark, to: source, selection: NSRange(location: 1, length: 2)))
            XCTAssertEqual(visible(edited), "bold")
            XCTAssertEqual(MarkdownInlineMarkEditor.visibleUTF16Length(of: edited), 4)
            if source.contains("https://example.com/path") {
                XCTAssertTrue(edited.contains("https://example.com/path"))
            }
        }
    }

    func testPartialRangeAcrossHeadingAndParagraphKeepsExistingMarksAndOneUndo() {
        let original = "Before\r\n\r\n# Start **bold** end\r\n\r\nNext [link](https://example.com) end\r\n\r\nAfter"
        let controller = MarkdownEditorController(text: original)
        let selected = selection(original, "block-1", 7, "block-2", 6)
        XCTAssertTrue(controller.applySemanticInlineMarkToVisibleTextRange(selected, mark: .italic))
        XCTAssertTrue(controller.text.hasPrefix("Before\r\n\r\n# Start "))
        XCTAssertTrue(controller.text.hasSuffix(" end\r\n\r\nAfter"))
        XCTAssertTrue(controller.text.contains("https://example.com"))
        XCTAssertEqual(visible(controller.semanticDocument.blocks[1].plainText), "Start bold end")
        XCTAssertEqual(visible(controller.semanticDocument.blocks[2].plainText), "Next link end")
        let forward = controller.text
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, original)
        XCTAssertFalse(controller.canUndo)

        let reversed = MarkdownEditorController(text: original)
        let backward = selection(original, "block-2", 6, "block-1", 7)
        XCTAssertTrue(reversed.applySemanticInlineMarkToVisibleTextRange(backward, mark: .italic))
        XCTAssertEqual(reversed.text, forward)
    }

    func testWholeMixedBlocksAndEmptyEndpointsStayAtomic() {
        let original = "😀 First\n\n# Part *italic* end"
        let controller = MarkdownEditorController(text: original)
        let headingOnly = selection(original, "block-0", ("😀 First" as NSString).length, "block-1", 4)
        XCTAssertTrue(controller.applySemanticInlineMarkToVisibleTextRange(headingOnly, mark: .bold))
        XCTAssertEqual(visible(controller.semanticDocument.blocks[1].plainText), "Part italic end")
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, original)

        let paragraphOnly = selection(original, "block-0", 0, "block-1", 0)
        XCTAssertTrue(controller.applySemanticInlineMarkToVisibleTextRange(paragraphOnly, mark: .bold))
        XCTAssertEqual(controller.text, "**😀 First**\n\n# Part *italic* end")
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, original)
        XCTAssertFalse(controller.canUndo)
    }

    func testUnsafeLinkNestedLinkEmojiBoundaryAndInterveningListRejectAtomically() {
        let original = "😀 First\n\n# [link](https://example.com) end"
        let controller = MarkdownEditorController(text: original)
        let halfEmoji = selection(original, "block-0", 1, "block-1", 2)
        XCTAssertFalse(controller.applySemanticInlineMarkToVisibleTextRange(halfEmoji, mark: .bold))
        let insideLink = selection(original, "block-0", 0, "block-1", 3)
        XCTAssertFalse(controller.applySemanticInlineMarkToVisibleTextRange(
            insideLink, mark: .link(destination: "https://another.example")))
        for destination in ["javascript:alert(1)", "https://example.com/a]", "https://example.com/a) **bad**"] {
            XCTAssertFalse(controller.applySemanticInlineMarkToVisibleTextRange(
                insideLink, mark: .link(destination: destination)))
        }
        XCTAssertEqual(controller.text, original)
        XCTAssertFalse(controller.canUndo)

        let list = "First\n\n- item\n\nLast"
        let blocked = MarkdownEditorController(text: list)
        XCTAssertFalse(blocked.applySemanticInlineMarkToVisibleTextRange(
            selection(list, "block-0", 2, "block-2", 2), mark: .italic))
        XCTAssertEqual(blocked.text, list)
        XCTAssertFalse(blocked.canUndo)
    }

    func testStaleSourceRevisionRejectsWithoutAddingUndo() {
        let original = "Alpha\n\n# Beta"
        let controller = MarkdownEditorController(text: original)
        let selected = selection(original, "block-0", 1, "block-1", 2)
        controller.replaceRange(NSRange(location: 0, length: 0), with: "Intro\n\n")
        let changed = controller.text
        XCTAssertFalse(controller.applySemanticInlineMarkToVisibleTextRange(selected, mark: .bold))
        XCTAssertEqual(controller.text, changed)
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, original)
        XCTAssertFalse(controller.canUndo)
    }
}
