@testable import SmoothMarkdown
#if canImport(SmoothMarkdownCore)
@_spi(ReaderInternals) import SmoothMarkdownCore
#endif
import XCTest

@MainActor
final class StreamMarkdownRenderSessionTests: XCTestCase {
    private func requireRust() throws {
        guard NativeMarkdownExtensionProjection.isAvailable else { throw XCTSkip("Packaged Rust backend required") }
    }

    private func signature(_ node: Markup) -> String {
        let text = (node as? Markdown.Text)?.string ?? ""
        return "\(type(of: node))|\(node.range.map(String.init(describing:)) ?? "nil")|\(node.format())|\(text)[" +
            node.children.map(signature).joined(separator: ";") + "]"
    }

    func testStreamDeltasMatchWholeASTAtEveryPrefix() throws {
        try requireRust()
        let sources = [
            "# Head\r\n\r\nFirst 🐈 e\u{301}.\r\n\r\nSecond **bold** $x$.\r\n\r\nThird.",
            "Heading\n=======\n\n- One\n- Two\n\n> Quote\n> next\n\nTail",
            "| A | B |\n| --- | --- |\n| C | D |\n\n~~~swift\nlet n = 1\n~~~\n\nAfter",
            "Before [x][ref].\n\n[ref]: https://example.com\n\n[^a:b]: first\n    second\n\nAfter[^a:b].",
            "\\$escaped$ \\[^literal]\n\n> $$\n> x\n> $$\n\n![photo](https://example.com/a.png)"
        ]
        for source in sources {
            let session = NativeMarkdownStreamSession()
            var prefix = ""
            for character in source {
                prefix.append(character)
                let result = try XCTUnwrap(session.update(prefix))
                let expected = try XCTUnwrap(NativeMarkdownExtensionProjection.parse(prefix))
                XCTAssertEqual(result.tree, expected, prefix)
            }
        }
    }

    func testReaderReusesCommittedMarkupAndPreservesSourceLocations() throws {
        try requireRust()
        let session = StreamMarkdownRenderSession()
        let source = "# Head 🐈\r\n\r\nOne e\u{301}.\r\n\r\nTwo.\r\n\r\nTail"
        let first = try XCTUnwrap(session.update(source))
        let next = source + " grows.\r\n\r\nMore."
        let second = try XCTUnwrap(session.update(next))
        XCTAssertGreaterThan(session.reusedBlocks, 0)
        XCTAssertTrue(first.document.children.first === second.document.children.first)
        let full = try XCTUnwrap(PluginSharedSyntax.document(next, registry: nil, enableHTML: false))
        XCTAssertEqual(signature(second.document), signature(full))
        let projection = ReaderVisibleDocumentProjection(markdown: next, preparsedDocument: second.document)
        let expected = ReaderVisibleDocumentProjection(markdown: next)
        XCTAssertEqual(projection.text, expected.text)
        XCTAssertEqual(projection.copiedText(in: NSRange(location: 0, length: projection.text.utf16.count)),
                       expected.copiedText(in: NSRange(location: 0, length: expected.text.utf16.count)))
    }

    func testReferenceDefinitionInvalidatesCommittedBlocks() throws {
        try requireRust()
        let session = StreamMarkdownRenderSession()
        let initial = "[target]\n\nOne\n\nTwo\n\nTail"
        _ = try XCTUnwrap(session.update(initial))
        let source = initial + "\n\n[target]: https://example.com"
        let result = try XCTUnwrap(session.update(source))
        XCTAssertEqual(session.reusedBlocks, 0)
        let paragraph = try XCTUnwrap(result.document.children.first as? Paragraph)
        XCTAssertEqual((paragraph.children.first as? Markdown.Link)?.destination, "https://example.com")
        XCTAssertEqual(signature(result.document), signature(try XCTUnwrap(PluginSharedSyntax.document(source, registry: nil, enableHTML: false))))
    }

    func testSourceIdentityUsesExactUTF16AndReplacementResets() throws {
        try requireRust()
        let session = StreamMarkdownRenderSession()
        let decomposed = "e\u{301}\n\nOne\n\nTwo\n\nTail"
        let composed = "é\n\nOne\n\nTwo\n\nTail"
        XCTAssertEqual(decomposed, composed)
        XCTAssertNotEqual(Array(decomposed.utf16), Array(composed.utf16))
        let previous = try XCTUnwrap(session.update(decomposed))
        XCTAssertFalse(previous.matches(composed, plugins: nil, enableHTML: false))
        let replaced = try XCTUnwrap(session.update(composed))
        XCTAssertEqual(Array(replaced.document.format().utf16), Array(composed.utf16))
        XCTAssertEqual(session.reusedBlocks, 0)
        XCTAssertFalse(previous.document.children.first === replaced.document.children.first)
        XCTAssertEqual(signature(replaced.document), signature(try XCTUnwrap(PluginSharedSyntax.document(composed, registry: nil, enableHTML: false))))
        session.reset()
        XCTAssertEqual(try XCTUnwrap(session.update("new")).document.format(), "new")
    }

    func testPluginFallbackKeepsWholeDocumentReferencesAndRegistryUpdates() throws {
        try requireRust()
        let session = StreamMarkdownRenderSession()
        let registry = ParserPluginRegistry()
        try registry.register(MentionPlugin())
        session.configure(plugins: registry, enableHTML: false)
        let source = "[one][ref] @alice\n\nTwo\n\n[ref]: https://example.com"
        let first = try XCTUnwrap(session.update(source))
        let paragraph = try XCTUnwrap(first.document.children.first as? Paragraph)
        XCTAssertEqual((paragraph.children.first as? Markdown.Link)?.destination, "https://example.com")
        XCTAssertTrue(paragraph.children.contains { $0 is SharedInlinePluginMarkup })
        XCTAssertEqual(session.reusedBlocks, 0)
        let repeated = try XCTUnwrap(session.update(source))
        XCTAssertFalse(first.document === repeated.document, "Host plugin state may change without a registry revision")
        registry.clear()
        XCTAssertFalse(first.matches(source, plugins: registry, enableHTML: false))
        let second = try XCTUnwrap(session.update(source))
        XCTAssertFalse(second.document.children.first!.children.contains { $0 is SharedInlinePluginMarkup })
    }

    func testFootnotePrefixesKeepReaderHookSourceSpans() throws {
        try requireRust()
        let session = StreamMarkdownRenderSession()
        let source = "Before[^a:b]\n\n[^a:b]: first\n    next line\n\nAfter"
        var prefix = ""
        for character in source {
            prefix.append(character)
            let snapshot = try XCTUnwrap(session.update(prefix))
            let full = try XCTUnwrap(PluginSharedSyntax.document(prefix, registry: nil, enableHTML: false))
            XCTAssertEqual(signature(snapshot.document), signature(full), prefix)
            if prefix.contains("[^") { XCTAssertEqual(session.reusedBlocks, 0) }
        }
    }

    func testMathPrefixesKeepReaderHookSemantics() throws {
        try requireRust()
        for source in ["$a $", "$$x$$tail", "Before\n\n$$\nx\n$$\n\nTail", "\\$escaped$ and $x$"] {
            let session = StreamMarkdownRenderSession()
            var prefix = ""
            for character in source {
                prefix.append(character)
                let snapshot = try XCTUnwrap(session.update(prefix))
                let full = try XCTUnwrap(PluginSharedSyntax.document(prefix, registry: nil, enableHTML: false))
                XCTAssertEqual(signature(snapshot.document), signature(full), prefix)
                if prefix.contains("$") { XCTAssertEqual(session.reusedBlocks, 0) }
            }
        }
    }

    func testHTMLAndDetailsUseExistingWholeDocumentPath() throws {
        try requireRust()
        let session = StreamMarkdownRenderSession()
        session.configure(plugins: nil, enableHTML: true)
        XCTAssertNil(session.update("<b>bold</b>"))
        session.configure(plugins: nil, enableHTML: false)
        XCTAssertNil(session.update("<details>\n<summary>Title</summary>\nBody\n</details>"))
        XCTAssertNotNil(session.update("plain"))
    }

    func testDecodedNodesRemainOwnedAfterResetAndSessionRelease() throws {
        try requireRust()
        let source = "# Owned 🐈\n\nParagraph **bold** and [link](https://example.com)."
        let expected = try XCTUnwrap(NativeMarkdownExtensionProjection.parse(source))
        var session: NativeMarkdownStreamSession? = NativeMarkdownStreamSession()
        let snapshot = try XCTUnwrap(session?.update(source))
        session?.reset()
        session = nil
        XCTAssertEqual(snapshot.tree, expected)
        XCTAssertEqual(snapshot.tree.children.first?.children.first?.semanticText, "Owned 🐈")
    }

    @MainActor
    func testReplacingRendererRegistryRefreshesCurrentSourceWithoutRestartingStream() throws {
        try requireRust()
        let accumulator = StreamMarkdownAccumulator(throttleMillis: 0)
        let first = ParserPluginRegistry()
        try first.register(MentionPlugin())
        accumulator.prepareRenderer(plugins: first, enableHTML: false)
        accumulator.append("@alice")
        XCTAssertTrue(accumulator.renderSnapshot!.document.children.first!.children.contains { $0 is SharedInlinePluginMarkup })
        let generation = accumulator.generation
        let replacement = ParserPluginRegistry()
        accumulator.prepareRenderer(plugins: replacement, enableHTML: false)
        XCTAssertEqual(accumulator.generation, generation)
        XCTAssertEqual(accumulator.visibleText, "@alice")
        XCTAssertFalse(accumulator.renderSnapshot!.document.children.first!.children.contains { $0 is SharedInlinePluginMarkup })
        XCTAssertTrue(accumulator.renderSnapshot!.matches("@alice", plugins: replacement, enableHTML: false))
        accumulator.append(" next")
        XCTAssertTrue(accumulator.renderSnapshot!.matches("@alice next", plugins: replacement, enableHTML: false))
    }

    @MainActor
    func testAccumulatorPublishesPreparedSnapshotAndRejectsPreviousGeneration() throws {
        try requireRust()
        let accumulator = StreamMarkdownAccumulator(throttleMillis: 0)
        accumulator.prepareRenderer(plugins: nil, enableHTML: false)
        accumulator.append("One\n\nTwo\n\nThree\n\nTail")
        XCTAssertEqual(accumulator.renderSnapshot?.source, accumulator.visibleText)
        let old = accumulator.generation
        accumulator.reset()
        XCTAssertNil(accumulator.renderSnapshot)
        accumulator.append("late", for: old)
        XCTAssertEqual(accumulator.visibleText, "")
        accumulator.append("new")
        accumulator.finish()
        XCTAssertEqual(accumulator.renderSnapshot?.document.format(), "new")
    }
}
