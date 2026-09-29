import Markdown
import XCTest
@testable import SmoothMarkdown

final class FootnoteSyntaxTests: XCTestCase {
    func testReferencesKeepNamedAndNumericLabelsInOrder() {
        XCTAssertEqual(FootnoteSyntax.parts(in: "Text[^1] and[^note] end"), [
            .text("Text"), .reference("1"), .text(" and"), .reference("note"), .text(" end")
        ])
        XCTAssertEqual(FootnoteSyntax.parts(in: "[^] and [^unclosed"), [.text("[^] and [^unclosed")])
    }

    func testDefinitionIncludesIndentedContinuationAndFormattingSource() {
        let sections = FootnoteSyntax.sections("""
        Some text[^note]

        [^note]: This is **bold** footnote
            Second line
            Third line

        Tail
        """)
        XCTAssertEqual(sections, [
            .markdown("Some text[^note]\n"),
            .definition(.init(label: "note", content: "This is **bold** footnote\nSecond line\nThird line")),
            .markdown("Tail")
        ])
        guard case let .definition(definition) = sections[1] else { return XCTFail("Expected definition") }
        let content = MarkdownSyntax.parse(definition.content).child(at: 0)!
        XCTAssertTrue(Array(content.children).contains { $0 is Strong })
    }

    func testDefinitionsInsideFencesRemainCodeAndInvalidDefinitionsStayLiteral() {
        let sections = FootnoteSyntax.sections("""
        ```md
        [^code]: literal
        ```
        [^]: empty label
        [^valid]: Real footnote
        """)
        XCTAssertEqual(sections, [
            .markdown("```md\n[^code]: literal\n```\n[^]: empty label"),
            .definition(.init(label: "valid", content: "Real footnote"))
        ])
    }

    func testInlineRunsExposeReferenceWithoutChangingCode() {
        let paragraph = MarkdownSyntax.parse("Some **bold[^1]** and `[^code]` text").child(at: 0)!
        let runs = InlineContent.runs(in: paragraph, enableHTML: false)
        XCTAssertEqual(runs.filter { if case .footnote = $0 { return true }; return false }.count, 1)
        XCTAssertTrue(runs.contains { if case let .footnote(label) = $0 { return label == "1" }; return false })
        XCTAssertTrue(runs.contains { if case let .text(value, _, _, code) = $0 { return code && value == "[^code]" }; return false })
    }

    func testReaderGroupsReferenceWithAdjacentProseInVisibleOrder() {
        let source = "Before 😀[^note] after `[^code]`.\n\nSecond paragraph."
        let nodes = Array(MarkdownSyntax.parse(source).children)
        let groups = ReaderSelectionGroup.group(nodes, enableHTML: false, plugins: nil)
        guard groups.count == 1, case let .selectable(selected) = groups[0],
              let document = ReaderSelectionDocument.compose(selected, enableHTML: false, plugins: nil) else {
            return XCTFail("Expected continuous native reader group")
        }
        XCTAssertEqual(document.selectionText, "Before 😀[note] after [^code].\nSecond paragraph.")
        XCTAssertEqual(document.copiedText, document.selectionText)
        XCTAssertEqual(document.lines[0].runs.filter(\.footnoteReference).map(\.text), ["[note]"])
    }

    func testFootnoteReferenceKeepsUTF16CopyEndpointAcrossImage() {
        let source = "Before 🐈[^note] after.\n\n![hidden](https://example.com/a.png)\n\nTail 😀 end."
        let nodes = Array(MarkdownSyntax.parse(source).children)
        let bridge = ReaderBlockRangeDocument(nodes, enableHTML: false, plugins: nil)!
        let first = ReaderSelectionDocument.compose(bridge.segments[0].nodes,
                                                     enableHTML: false, plugins: nil)!.selectionText as NSString
        let last = ReaderSelectionDocument.compose(bridge.segments[2].nodes,
                                                    enableHTML: false, plugins: nil)!.selectionText as NSString
        let start = first.range(of: "[note]").location
        let emoji = last.range(of: "😀")
        XCTAssertEqual(bridge.copiedText(in: 0...2, startUTF16: start,
                                         endUTF16: emoji.location + emoji.length,
                                         enableHTML: false, plugins: nil), "[note] after.\nTail 😀")
        XCTAssertNil(bridge.copiedText(in: 0...2, startUTF16: start - 1,
                                       enableHTML: false, plugins: nil),
                     "A UTF-16 endpoint inside the cat surrogate pair is invalid")
    }

    func testTableTextCopiesVisibleFootnoteLabel() {
        let table = MarkdownSyntax.parse("| A |\n| - |\n| text[^1] |")
            .child(at: 0)!
        XCTAssertEqual(ReaderBlockRangeDocument.tableText(table, enableHTML: false, plugins: nil),
                       "A\ntext[1]")
    }

    #if os(iOS)
    @MainActor
    func testNativeReferenceUsesFootnoteFontColorAndBaseline() {
        let nodes = Array(MarkdownSyntax.parse("Text[^1] more").children)
        let document = ReaderSelectionDocument.compose(nodes, enableHTML: false, plugins: nil)!
        let style = MarkdownStyleSheet.light()
        let renderer = ReaderSelectionTextView(document: document, styleSheet: style,
                                               onLinkTap: nil, onTextLongPress: nil,
                                               selectable: true, onCharacterTap: nil)
        let traits = MarkdownTypography.traits(for: .large)
        let text = renderer.attributedContent(traits: traits).text
        XCTAssertEqual(text.string, "Text[1] more")
        let range = (text.string as NSString).range(of: "[1]")
        let font = text.attribute(.font, at: range.location, effectiveRange: nil) as? UIFont
        XCTAssertEqual(font?.pointSize ?? 0,
                       MarkdownTypography.font(textStyle: .footnote, weight: .regular,
                                               customSize: nil, traits: traits).pointSize,
                       accuracy: 0.1)
        XCTAssertEqual((text.attribute(.baselineOffset, at: range.location,
                                       effectiveRange: nil) as? NSNumber)?.doubleValue, 5)
        XCTAssertEqual(text.attribute(.foregroundColor, at: range.location,
                                      effectiveRange: nil) as? UIColor, UIColor(style.footnoteColor!))
    }
    #endif
}
