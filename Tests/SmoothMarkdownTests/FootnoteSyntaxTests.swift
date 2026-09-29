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
}
