import XCTest
@testable import SmoothMarkdown

final class MathSyntaxTests: XCTestCase {
    func testInlineMathAndMalformedFallback() {
        XCTAssertEqual(MathSyntax.inlineParts(in: "$E=mc^2$"), [.math("E=mc^2")])
        XCTAssertEqual(MathSyntax.inlineParts(in: "Given $x=1$ and $y=2$"),
                       [.text("Given "), .math("x=1"), .text(" and "), .math("y=2")])
        XCTAssertEqual(MathSyntax.inlineParts(in: "$$"), [.text("$$")])
        XCTAssertEqual(MathSyntax.inlineParts(in: "$unclosed"), [.text("$unclosed")])
    }

    func testBlockMathVariantsAndParagraphBoundary() {
        XCTAssertEqual(MathSyntax.sections("Intro\n$$\nx^2 + y^2 = z^2\n$$"),
                       [.markdown("Intro"), .block("x^2 + y^2 = z^2")])
        XCTAssertEqual(MathSyntax.sections("$$E = mc^2$$"), [.block("E = mc^2")])
        XCTAssertEqual(MathSyntax.sections("$$\na + b = c"), [.block("a + b = c")])
        XCTAssertEqual(MathSyntax.sections("$$\n$$"), [.block("")])
        XCTAssertEqual(MathSyntax.sections("$$\n\\sum_{i=1}^{n} x_i\n= x_1 + x_2 + x_n\n$$"),
                       [.block("\\sum_{i=1}^{n} x_i\n= x_1 + x_2 + x_n")])
    }

    func testCodeIsNotMathAndMixedInlineRunsPreserveOrder() {
        XCTAssertEqual(MathSyntax.sections("```text\n$$\nx\n$$\n```"),
                       [.markdown("```text\n$$\nx\n$$\n```")])
        let paragraph = MarkdownSyntax.parse("Before $E=mc^2$ and `literal $x$` after").child(at: 0)!
        let runs = InlineContent.runs(in: paragraph, enableHTML: false)
        XCTAssertEqual(runs.compactMap { if case let .math(latex) = $0 { return latex }; return nil }, ["E=mc^2"])
        XCTAssertTrue(runs.contains { if case let .text(value, _, _, code) = $0 { return code && value == "literal $x$" }; return false })
        let subscriptParagraph = MarkdownSyntax.parse("Value $x_i + y_j$").child(at: 0)!
        let subscriptRuns = InlineContent.runs(in: subscriptParagraph, enableHTML: false)
        XCTAssertEqual(subscriptRuns.compactMap { if case let .math(latex) = $0 { return latex }; return nil }, ["x_i + y_j"])
    }
}
