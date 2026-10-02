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

    func testIndentedMathSourceRemainsCodeInNativeAndFallbackReaderProjection() {
        for source in ["    \\[\\]\n", "\t\\[x\\]", "    $$x$$"] {
            XCTAssertEqual(MarkdownCoreParser().parse(source).children[0].kind, .indentedCode)
            for native in [true, false] {
                XCTAssertEqual(MathSyntax.sections(source, useNativeProjection: native), [.markdown(source)])
            }
        }
    }

    func testDisplayLiteralAndTrailingProseKeepSeparateSourceRanges() {
        for source in [#"\[x\] trailing"#, "\\[\nx\n\\] trailing"] {
            let nodes = MarkdownCoreParser().parse(source).children
            XCTAssertEqual(nodes.count, 2)
            XCTAssertEqual(nodes[0].kind, .blockMath)
            XCTAssertEqual(nodes[0].literalText, "x")
            XCTAssertTrue(nodes[0].source.hasSuffix(#"\]"#))
            XCTAssertEqual(nodes[1].kind, .paragraph)
            XCTAssertEqual(nodes[1].source, " trailing")
            XCTAssertEqual(NSMaxRange(nodes[0].sourceRange), nodes[1].sourceRange.location)
            for native in [true, false] {
                XCTAssertEqual(MathSyntax.sections(source, useNativeProjection: native), [.block("x"), .markdown(" trailing")])
            }
        }
    }
    func testOrdinaryEscapedBracketsRemainProseAndUnclosedMathStaysMutable() {
        for source in [#"\[^escaped] and [^real]"#, #"\[ordinary] prose"#] {
            XCTAssertEqual(MarkdownCoreParser().parse(source).children[0].kind, .paragraph)
            for native in [true, false] { XCTAssertEqual(MathSyntax.sections(source, useNativeProjection: native), [.markdown(source)]) }
        }
        XCTAssertEqual(MathSyntax.sections("\\[\nx[0]\n"), [.block("x[0]")])
        XCTAssertEqual(MathSyntax.sections(#"\[unfinished"#), [.block("unfinished")])
        XCTAssertEqual(MathSyntax.sections(#"\[x[0]\]"#), [.block("x[0]")])
        for (source, literal) in [("\\[x[0]\n+1\n\\]", "x[0]\n+1"), (#"\[x[0]"#, "x[0]")] {
            XCTAssertEqual(MarkdownCoreParser().parse(source).children[0].literalText, literal)
            for native in [true, false] { XCTAssertEqual(MathSyntax.sections(source, useNativeProjection: native), [.block(literal)]) }
        }
    }

}
