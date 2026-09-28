import Foundation
import XCTest
@testable import SmoothMarkdown

@MainActor
final class InlineMarkEditorTests: XCTestCase {
    func testHeadingBoldToggleKeepsSourceTriviaUTF16SelectionAndUndo() {
        let original = "#  Hi 😀world\r\n\r\n<raw>stay</raw>\r\n"
        let controller = MarkdownEditorController(text: original)
        controller.mode = .formatted
        let range = ("Hi 😀world" as NSString).range(of: "😀world")
        let selected = controller.applySemanticInlineMark(id: "block-0", selection: range, mark: .bold)
        XCTAssertEqual(selected, NSRange(location: range.location + 2, length: range.length))
        XCTAssertEqual(controller.text, "#  Hi **😀world**\r\n\r\n<raw>stay</raw>\r\n")
        XCTAssertEqual((controller.text as NSString).substring(with: controller.selection), "😀world")
        XCTAssertEqual(controller.semanticDocument.blocks[0].kind, .heading(level: 1, markdown: "Hi **😀world**"))
        XCTAssertEqual(controller.applySemanticInlineMark(id: "block-0", selection: selected!, mark: .bold), range)
        XCTAssertEqual(controller.text, original)
        XCTAssertTrue(controller.undo())
        XCTAssertTrue(controller.text.contains("**😀world**"))
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, original)
        XCTAssertTrue(controller.redo())
        XCTAssertTrue(controller.text.contains("**😀world**"))
    }

    func testItalicLinkAndCodeEditOnlySelectedParagraphWithUndo() {
        let original = "Alpha beta gamma\n\n> quoted **source**\n"
        let controller = MarkdownEditorController(text: original)
        let beta = ("Alpha beta gamma" as NSString).range(of: "beta")
        XCTAssertNotNil(controller.applySemanticInlineMark(id: "block-0", selection: beta, mark: .italic))
        let gamma = (controller.semanticDocument.blocks[0].plainText as NSString).range(of: "gamma")
        XCTAssertNotNil(controller.applySemanticInlineMark(id: "block-0", selection: gamma,
                                                           mark: .link(destination: "https://example.com/a(b)")))
        let alpha = (controller.semanticDocument.blocks[0].plainText as NSString).range(of: "Alpha")
        XCTAssertNotNil(controller.applySemanticInlineMark(id: "block-0", selection: alpha, mark: .code))
        XCTAssertEqual(controller.text,
                       "`Alpha` *beta* [gamma](https://example.com/a%28b%29)\n\n> quoted **source**\n")
        XCTAssertTrue(controller.undo())
        XCTAssertFalse(controller.text.contains("`Alpha`"))
        XCTAssertTrue(controller.undo())
        XCTAssertFalse(controller.text.contains("[gamma]"))
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, original)
    }

    func testInvalidSelectionUnsafeLinkAndUnsupportedBlockDoNotMutateDocument() {
        let original = "😀 text\n\n- raw item\n"
        let controller = MarkdownEditorController(text: original)
        XCTAssertNil(controller.applySemanticInlineMark(id: "block-0", selection: NSRange(location: 1, length: 1), mark: .bold))
        XCTAssertNil(controller.applySemanticInlineMark(id: "block-0", selection: NSRange(location: 0, length: 0), mark: .italic))
        XCTAssertNil(controller.applySemanticInlineMark(id: "block-0", selection: NSRange(location: 3, length: 4),
                                                        mark: .link(destination: "javascript:alert(1)")))
        XCTAssertNil(controller.applySemanticInlineMark(id: "block-1", selection: NSRange(location: 0, length: 3), mark: .code))
        XCTAssertEqual(controller.text, original)
        XCTAssertFalse(controller.canUndo)
    }

    func testInlineCodeUsesLongerDelimiterWhenSelectionContainsBackticks() {
        let source = "Use x`y here"
        let range = (source as NSString).range(of: "x`y")
        let edit = MarkdownInlineMarkEditor.apply(.code, to: source, selection: range)
        XCTAssertEqual(edit?.markdown, "Use `` x`y `` here")
        XCTAssertEqual((edit!.markdown as NSString).substring(with: edit!.selection), "x`y")
    }
}
