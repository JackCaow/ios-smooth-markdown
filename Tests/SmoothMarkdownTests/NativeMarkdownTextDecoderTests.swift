import XCTest
@testable import SmoothMarkdown

final class NativeMarkdownTextDecoderTests: XCTestCase {
    func testNamedAndNumericReferencesAndEscapedPunctuation() {
        XCTAssertEqual(NativeMarkdownTextDecoder.decode("&amp; &NotEqualTilde; &#169; &#x1F600;"),
                       "& ≂̸ © 😀")
        XCTAssertEqual(NativeMarkdownTextDecoder.decode(#"\*literal\* \[x\]"#), "*literal* [x]")
        XCTAssertEqual(NativeMarkdownTextDecoder.decode("&#0; &#xD800; &#x110000;"), "� � �")
        XCTAssertEqual(NativeMarkdownTextDecoder.decode("&unknown; &amp &#12 &#00000001;"),
                       "&unknown; &amp &#12 &#00000001;")
    }

    func testCodeSpanNormalizesWhitespaceWithoutDecodingEntities() {
        XCTAssertEqual(NativeMarkdownTextDecoder.codeSpan("` a\nb `"), "a b")
        XCTAssertEqual(NativeMarkdownTextDecoder.codeSpan("`` &amp; ``"), "&amp;")
        XCTAssertEqual(NativeMarkdownTextDecoder.codeSpan("`  `"), "  ")
    }

    func testASTKeepsSpellingAndExposesDecodedSemanticText() {
        let source = #"Text &copy; and \*word\* with ` x ` [link](https://example.com/?a=1&amp;b=2)"#
        let nodes = NativeMarkdownASTParser().parse(source).children[0].children
        XCTAssertEqual(nodes.first?.semanticText, "Text © and *word* with ")
        XCTAssertEqual(nodes.first(where: { $0.kind == .inlineCode })?.semanticText, "x")
        XCTAssertTrue(nodes.contains { $0.kind == .link("https://example.com/?a=1&b=2") })
        for node in nodes {
            XCTAssertEqual((source as NSString).substring(with: node.sourceRange), node.source)
        }
    }
}
