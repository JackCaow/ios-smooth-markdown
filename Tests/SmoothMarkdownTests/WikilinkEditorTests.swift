import Foundation
@testable import SmoothMarkdown
import XCTest

@MainActor
final class WikilinkEditorTests: XCTestCase {
    func testParserKeepsWholeTargetAndRejectsMalformedClosingBracket() {
        let plugin = WikilinkPlugin()
        let valid = "[[Daily Notes|today]]"
        let match = plugin.parse(valid, at: valid.startIndex)
        XCTAssertEqual(match?.consumed, valid.count)
        XCTAssertEqual(match?.text, "Daily Notes|today")
        XCTAssertEqual(match?.attributes["target"], "Daily Notes|today")
        for invalid in ["[[]]", "[[A]B]]", "[[unfinished", "[single]"] {
            XCTAssertNil(plugin.parse(invalid, at: invalid.startIndex), invalid)
        }
    }

    func testPreviewPluginIsOptInAndLeavesDisabledSourceLiteral() throws {
        let source = "Open [[Daily Notes]]"
        let disabled = PluginInlineSyntax.parts(in: source, registry: nil)
        guard case let .text(literal) = disabled.first else { return XCTFail("Expected literal source") }
        XCTAssertEqual(literal, source)

        let enabled = ParserPluginRegistry()
        try enabled.register(WikilinkPlugin())
        let parsed = PluginInlineSyntax.parts(in: source, registry: enabled)
        XCTAssertEqual(parsed.count, 2)
        guard case let .plugin(_, match) = parsed.last else { return XCTFail("Expected wikilink") }
        XCTAssertEqual(match.attributes["target"], "Daily Notes")
    }

    func testTriggerRequiresWhitespacePrefixAndOutsideCode() {
        XCTAssertEqual(WikilinkTrigger.match(in: "See [[Al", cursor: 8),
                       .init(range: NSRange(location: 4, length: 4), query: "Al"))
        XCTAssertNil(WikilinkTrigger.match(in: "Word[[Al", cursor: 9))
        XCTAssertNil(WikilinkTrigger.match(in: "Use `code [[Al", cursor: 14))
        XCTAssertNil(WikilinkTrigger.match(in: "See [[A]] and", cursor: 8))
        XCTAssertNil(WikilinkTrigger.match(in: "See [[A\nB", cursor: 9))
        XCTAssertEqual(WikilinkTrigger.match(in: "😀 [[Al", cursor: 7)?.range,
                       NSRange(location: 3, length: 4))
    }

    func testSuggestionsFilterIgnoreCaseAndLimitToTen() {
        let notes = ["Daily Notes", "Project Plan", "Research Index"]
        XCTAssertEqual(WikilinkTrigger.suggestions(notes, for: "nOt"), ["Daily Notes"])
        XCTAssertEqual(WikilinkTrigger.suggestions(notes, for: "missing"), [])
        XCTAssertEqual(WikilinkTrigger.suggestions((1...12).map { "Note \($0)" }, for: "Note").count, 10)
    }

    func testSuggestionReplacesOnlyActiveTriggerAndIsOneUndoStep() {
        let original = "# Heading\r\n\r\nSee [[Al and [[Be!\r\n\r\nTail"
        let controller = MarkdownEditorController(text: original)
        let paragraph = controller.semanticDocument.blocks[1]
        let caret = (paragraph.plainText as NSString).length - 1
        let next = controller.insertWikilinkSuggestion("Beta Note", inBlock: paragraph.id,
                                                       selection: NSRange(location: caret, length: 0))
        XCTAssertEqual(controller.text, "# Heading\r\n\r\nSee [[Al and [[Beta Note]]!\r\n\r\nTail")
        XCTAssertEqual(next?.location, ("See [[Al and [[Beta Note]]" as NSString).length)
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, original)
        XCTAssertFalse(controller.canUndo)
        XCTAssertTrue(controller.redo())
        XCTAssertEqual(controller.text, "# Heading\r\n\r\nSee [[Al and [[Beta Note]]!\r\n\r\nTail")
    }

    func testHeadingSuggestionPreservesMarkerAndRejectsBadTitle() {
        let controller = MarkdownEditorController(text: "  ## See [[Al\n\nOther")
        let heading = controller.semanticDocument.blocks[0]
        XCTAssertNil(controller.insertWikilinkSuggestion("Bad]Title", inBlock: heading.id,
                                                        selection: NSRange(location: 8, length: 0)))
        let next = controller.insertWikilinkSuggestion("Alpha", inBlock: heading.id,
                                                       selection: NSRange(location: (heading.plainText as NSString).length,
                                                                          length: 0))
        XCTAssertEqual(controller.text, "  ## See [[Alpha]]\n\nOther")
        XCTAssertEqual(next?.location, ("See [[Alpha]]" as NSString).length)
    }

    func testSuggestionCannotRewriteCodeBlockOrStaleTrigger() {
        let controller = MarkdownEditorController(text: "```\n[[Al\n```\n\nSee [[Al")
        let code = controller.semanticDocument.blocks[0]
        XCTAssertNil(controller.insertWikilinkSuggestion("Alpha", inBlock: code.id,
                                                        selection: NSRange(location: 4, length: 0)))
        let paragraph = controller.semanticDocument.blocks[1]
        XCTAssertNil(controller.insertWikilinkSuggestion("Alpha", inBlock: paragraph.id,
                                                        selection: NSRange(location: 4, length: 0)))
        XCTAssertEqual(controller.text, "```\n[[Al\n```\n\nSee [[Al")
    }
}
