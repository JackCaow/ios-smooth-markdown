import XCTest
@testable import SmoothMarkdown
import SmoothMarkdownCore

final class BackslashMathTests: XCTestCase {
    func testPublicCoreExtensionsAndSourceRanges() {
        let source = #"😀 Math \(x_1\) and $y_2$"#
        let core = MarkdownCoreParser(enableExtensions: true)
        let nodes = core.parse(source).children[0].children.filter { $0.kind == .inlineMath }
        XCTAssertEqual(nodes.map(\.literalText), ["x_1", "y_2"])
        XCTAssertEqual(nodes[0].source, #"\(x_1\)"#)
        XCTAssertEqual(nodes[0].sourceRange, NSRange(location: 8, length: 7))
        XCTAssertFalse(MarkdownCoreParser(enableExtensions: false).parse(source).children[0].children.contains { $0.kind == .inlineMath })
        XCTAssertEqual(MathSyntax.inlineParts(in: source), [.text("😀 Math "), .math("x_1"), .text(" and "), .math("y_2")])
    }
    func testBlockProjectionAndReaderFormula() throws {
        let source = "Before\n\\[\n\\frac{x}{y}\n\\]\nAfter"
        XCTAssertEqual(MathSyntax.sections(source), [.markdown("Before"), .block(#"\frac{x}{y}"#), .markdown("After")])
        XCTAssertEqual(MathSyntax.sections(#"\[x\]"#), [.block("x")])
        let document = PluginSharedSyntax.document(#"Math \(x_1\) and $y_2$"#, registry: nil, enableHTML: false)
        let paragraph = try XCTUnwrap(document?.children.first as? Paragraph)
        let runs = InlineContent.runs(in: paragraph, enableHTML: false)
        XCTAssertEqual(runs.compactMap { if case let .math(latex) = $0 { return latex }; return nil }, ["x_1", "y_2"])
        let selection = ReaderVisibleDocumentProjection(markdown: #"Math \(x_1\) and $y_2$"#)
        XCTAssertEqual(selection.copiedText(in: NSRange(location: 0, length: selection.text.utf16.count)), "Math x_1 and y_2")
    }
    @MainActor func testCodeEscapesUnclosedAndStreamEligibility() async {
        XCTAssertEqual(MathSyntax.inlineParts(in: #"`\(code\)` \\(escaped\) \(open"#), [.text(#"`\(code\)` \\(escaped\) \(open"#)])
        XCTAssertEqual(MathSyntax.sections("```\n\\[x\\]\n```"), [.markdown("```\n\\[x\\]\n```")])
        let session = StreamMarkdownRenderSession()
        XCTAssertFalse(session.isBackgroundEligible(#"\(x\)"#))
        XCTAssertFalse(session.isBackgroundEligible(#"\[x\]"#))
    }
    func testSourceFallbackBackslashAndEscapedDelimiters() {
        XCTAssertEqual(MathSyntax.inlineParts(in: #"Math \(x\) end"#, useNativeProjection: false), [.text("Math "), .math("x"), .text(" end")])
        XCTAssertEqual(MathSyntax.inlineParts(in: #"\\(escaped\) \"#, useNativeProjection: false), [.text(#"\\(escaped\) \"#)])
        XCTAssertEqual(MathSyntax.inlineParts(in: #"\(a\\)b\)"#, useNativeProjection: false), [.math(#"a\\)b"#)])
        XCTAssertEqual(MathSyntax.sections(#"\[x\]"#, useNativeProjection: false), [.block("x")])
        XCTAssertEqual(MathSyntax.sections("```\n\\[x\\]\n```", useNativeProjection: false), [.markdown("```\n\\[x\\]\n```")])
    }

}
