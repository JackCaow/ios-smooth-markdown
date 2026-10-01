import XCTest
@testable import SmoothMarkdown
@testable import SmoothMarkdownCore

final class RustEditorAndHTMLIntegrationTests: XCTestCase {
    private func requireRust() throws {
        guard RustMarkdownBridge.isAvailable else {
            if ProcessInfo.processInfo.environment["SMOOTH_MARKDOWN_RUST_REQUIRED"] == "1" {
                throw NSError(domain: "RequiredRustBackendUnavailable", code: 1)
            }
            throw XCTSkip("Rust binary required for integration verification")
        }
    }

    func testEditorUsesSharedTableGrammarAndPreservesSourceTrivia() throws {
        try requireRust()
        // One-hyphen delimiters are GFM syntax; the old editor table scanner
        // independently required three and misclassified this valid table.
        let source = "\r\n| 😀 | B |\r\n| - | :- |\r\n| **x** | `a\\|b` |\r\n\r\nAfter\r\n"
        let before = RustMarkdownBridge.successfulParseCount
        let document = MarkdownDocumentCodec().parse(source)
        XCTAssertGreaterThan(RustMarkdownBridge.successfulParseCount, before)
        XCTAssertEqual(document.toMarkdown(), source)
        XCTAssertEqual(document.blocks.count, 2)
        guard case let .table(table) = document.blocks[0].kind else { return XCTFail("Rust GFM table expected") }
        XCTAssertEqual(table.headers, ["😀", "B"])
        XCTAssertEqual(table.rows, [["**x**", "`a\\|b`"]])
        XCTAssertEqual(table.alignments, [nil, .left])
        XCTAssertEqual(document.blocks[0].leadingTrivia, "\r\n")
        XCTAssertEqual(document.blocks[1].leadingTrivia, "\r\n")
        XCTAssertNotNil(MarkdownSourceTable.parse("| A |\n| - |\n| value |"))
        XCTAssertNil(MarkdownSourceTable.parse("```\n| A |\n| - |\n```"))
    }

    func testListEntryPointRequiresSharedGrammarBeforeLosslessProjection() throws {
        try requireRust()
        // A ten-digit ordered marker is ordinary CommonMark prose.
        XCTAssertNil(MarkdownSourceList.parse("1234567890. prose\n"))
        XCTAssertNotNil(MarkdownSourceList.parse("123456789. item\r\n"))
        let source = "- First\r\n  continuation\r\n\r\n- Second\r\n"
        let document = MarkdownDocumentCodec().parse(source)
        XCTAssertEqual(document.toMarkdown(), source)
        XCTAssertEqual(document.blocks.count, 2)
        XCTAssertEqual(document.blocks[1].leadingTrivia, "\r\n")
    }

    func testInlineEditorUsesSharedUTF16SpansAndKeepsSelectionSemantics() throws {
        try requireRust()
        let source = "😀 **bold** and _italic_"
        let before = RustMarkdownBridge.successfulParseCount
        XCTAssertEqual(MarkdownInlineMarkEditor.visibleText(of: source), "😀 bold and italic")
        XCTAssertGreaterThan(RustMarkdownBridge.successfulParseCount, before)
        let boundary = try XCTUnwrap(MarkdownInlineMarkEditor.visibleBoundary(in: source, at: 4))
        XCTAssertEqual(boundary.sourceOffset, 6)
        XCTAssertEqual(boundary.closeTokens, "**")
        XCTAssertEqual(boundary.openTokens, "**")
        XCTAssertEqual(MarkdownInlineMarkEditor.applyVerifiedVisibleRange(.italic, to: source,
            selection: NSRange(location: 3, length: 4)), "😀 ***bold*** and _italic_")
    }

    func testSourceHTMLExportRunsInRustWithoutHostASTDecode() throws {
        try requireRust()
        let beforeExports = RustMarkdownBridge.successfulHTMLExportCount
        let beforeParses = RustMarkdownBridge.successfulParseCount
        XCTAssertEqual(NativeMarkdownHTMLSerializer.format("**changed**"), "<p><strong>changed</strong></p>\n")
        XCTAssertEqual(MarkdownCoreParser().renderHTML("# Heading"), "<h1>Heading</h1>\n")
        XCTAssertEqual(RustMarkdownBridge.successfulHTMLExportCount - beforeExports, 2)
        XCTAssertEqual(RustMarkdownBridge.successfulParseCount, beforeParses,
                       "Source export must use the shared parse/render batch, not decode a host AST first")
    }

    func testManualASTExportsActualLiteralDestinationAndTitle() throws {
        try requireRust()
        let text = node(.text, source: "original", literal: "changed & 😀")
        let link = node(.link("/new target"), source: "[old](/old)", children: [text], title: "new \"title\"")
        let paragraph = node(.paragraph, source: "this source must never be reparsed", children: [link])
        let before = RustMarkdownBridge.successfulHTMLExportCount
        XCTAssertEqual(NativeMarkdownHTMLSerializer.render(paragraph),
            "<p><a href=\"/new%20target\" title=\"new &quot;title&quot;\">changed &amp; 😀</a></p>\n")
        XCTAssertGreaterThan(RustMarkdownBridge.successfulHTMLExportCount, before)
    }

    func testManualASTExportsListMetadataAndSwiftTransparentCells() throws {
        try requireRust()
        let paragraph = node(.paragraph, children: [node(.text, literal: "item")])
        let item = node(.listItem(checked: true), children: [paragraph])
        let list = NativeMarkdownNode(kind: .list(ordered: true), source: "not a list", sourceRange: .init(location: 0, length: 0),
            children: [item], isTight: false, listStart: 7)
        XCTAssertEqual(NativeMarkdownHTMLSerializer.render(list),
            "<ol start=\"7\">\n<li>\n<p><input checked=\"\" disabled=\"\" type=\"checkbox\"> item</p>\n</li>\n</ol>\n")
        let cell = node(.tableCell, children: [node(.strong, children: [node(.text, literal: "cell")])])
        XCTAssertEqual(NativeMarkdownHTMLSerializer.render(cell), "<strong>cell</strong>")
        XCTAssertEqual(NativeMarkdownHTMLSerializer.render(node(.tableRow, children: [cell])), "<strong>cell</strong>")
        let html = node(.inlineHTML, source: "<style>")
        XCTAssertEqual(NativeMarkdownHTMLSerializer.render(html), "<style>",
                       "Caller AST render must not apply source parsing's automatic GFM filter")
    }

    func testMutableASTRenderingMatchesAllOfficialExamples() throws {
        try requireRust()
        guard let path = ProcessInfo.processInfo.environment["COMMONMARK_SPEC_JSON"] else { throw XCTSkip("COMMONMARK_SPEC_JSON") }
        let examples = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path))) as? [[String: Any]])
        for example in examples {
            let source = try XCTUnwrap(example["markdown"] as? String)
            let tree = NativeMarkdownASTParser(enableGFM: false).parse(source)
            XCTAssertEqual(NativeMarkdownHTMLSerializer.render(tree), example["html"] as? String, "AST example \(example["example"]!)")
        }
        for fixture in ["gfm-tables", "gfm-inline", "gfm-tagfilter", "gfm-tasklist"] {
            let url = try XCTUnwrap(Bundle.module.url(forResource: fixture, withExtension: "json"))
            let examples = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: String]])
            for example in examples {
                let tree = NativeMarkdownASTParser().parse(try XCTUnwrap(example["markdown"]))
                XCTAssertEqual(NativeMarkdownHTMLSerializer.render(tree), example["html"], fixture)
            }
        }
    }

    func testReaderPluginsShareReferencesAndKeepSurroundingEmphasis() throws {
        try requireRust()
        let registry = ParserPluginRegistry()
        try registry.register(AdmonitionPlugin())
        try registry.register(EmojiSpanPlugin())
        let source = "**@😀 [link][id]**\r\n\r\n::: note Shared\r\nbody\r\n:::\r\n\r\n[id]: https://example.com/resolved\r\n"
        let sections = PluginBlockSyntax.sections(source, registry: registry)
        XCTAssertEqual(sections.count, 2)
        guard case let .parsed(document) = sections[0], let paragraph = document.children.first as? Paragraph else { return XCTFail("Shared parsed document") }
        let runs = InlineContent.runs(in: paragraph, enableHTML: false, plugins: registry)
        let links = runs.compactMap { run -> (String, InlineContent.Style)? in
            guard case let .text(text, style, _, _) = run, style.link != nil else { return nil }; return (text, style)
        }
        XCTAssertEqual(links.first?.0, "link")
        XCTAssertEqual(links.first?.1.link?.absoluteString, "https://example.com/resolved")
        XCTAssertEqual(links.first?.1.bold, true)
        XCTAssertTrue(runs.contains { if case let .plugin(plugin, match) = $0 { return plugin.id == "emoji-span" && match.text == "emoji" }; return false })
        XCTAssertEqual(MarkdownDocumentCodec(plugins: registry).parse(source).toMarkdown(), source)
        XCTAssertEqual(MarkdownDocumentCodec(plugins: registry).parse(source).blocks.count, 3)
    }

    func testHookedParsingProtectsCodeEscapesAndAcceptsUTF16ConsumedSpan() throws {
        try requireRust()
        let registry = ParserPluginRegistry(); try registry.register(EmojiSpanPlugin()); try registry.register(AdmonitionPlugin())
        let sections = PluginBlockSyntax.sections("\\@😀 `@😀` @😀 after\n\n```\n::: note\nbody\n:::\n```", registry: registry)
        guard case let .parsed(document) = sections.first, let paragraph = document.children.first else { return XCTFail("Parsed tree") }
        let runs = InlineContent.runs(in: paragraph, enableHTML: false, plugins: registry)
        XCTAssertEqual(runs.filter { if case .plugin = $0 { return true }; return false }.count, 1)
        XCTAssertTrue(runs.contains { if case let .text(text, _, _, code) = $0 { return code && text == "@😀" }; return false })
        XCTAssertTrue(document.children.last is CodeBlock)
        XCTAssertEqual(sections.count, 1)
    }

    func testExtensionsUseSameGlobalReferencesWithoutAPluginRegistry() throws {
        try requireRust()
        let source = "A [one][id]\n\n$$x$$\n\n[^a]: [two][id]\n\n[id]: https://example.com/resolved\n"
        let sections = PluginBlockSyntax.sections(source, registry: nil)
        guard case let .parsed(document) = sections.first else { return XCTFail("Complete shared source tree") }
        XCTAssertEqual(document.children.count, 3)
        XCTAssertTrue(document.children[1] is SharedBlockMathMarkup)
        let footnote = try XCTUnwrap(document.children[2] as? SharedFootnoteMarkup)
        let content = try XCTUnwrap(footnote.definition.parsedContent)
        let links = InlineContent.runs(in: content, enableHTML: false).compactMap { run -> URL? in
            guard case let .text(_, style, _, _) = run else { return nil }; return style.link
        }
        XCTAssertEqual(links.first?.absoluteString, "https://example.com/resolved")
    }

    func testRejectedHostASTExportKeepsVisibleSource() throws {
        try requireRust()
        var tree = node(.text, source: "<rejected>", literal: "visible")
        for _ in 0..<260 { tree = node(.strong, source: "<rejected>", children: [tree]) }
        XCTAssertNil(RustMarkdownBridge.renderHTML(tree))
        XCTAssertEqual(NativeMarkdownHTMLSerializer.render(tree), "&lt;rejected&gt;")
    }

    func testSharedReaderCacheTracksRegistryRevisionAndBypass() throws {
        try requireRust()
        let registry = ParserPluginRegistry()
        let source = "::: note Cached\nbody\n:::"
        let cache = MarkdownParseCache(maxSize: 2)
        let initial = try XCTUnwrap(cache.parseShared(source, plugins: registry, enableHTML: false))
        XCTAssertFalse(initial.children.first is SharedBlockPluginMarkup)
        _ = cache.parseShared(source, plugins: registry, enableHTML: false)
        XCTAssertEqual(cache.statistics.hits, 1)
        try registry.register(AdmonitionPlugin())
        let changed = try XCTUnwrap(cache.parseShared(source, plugins: registry, enableHTML: false))
        XCTAssertTrue(changed.children.first is SharedBlockPluginMarkup)
        XCTAssertEqual(cache.statistics.misses, 2)
        let before = RustMarkdownBridge.successfulParseCount
        _ = PluginBlockSyntax.sections(source, registry: registry, useCache: false)
        _ = PluginBlockSyntax.sections(source, registry: registry, useCache: false)
        XCTAssertEqual(RustMarkdownBridge.successfulParseCount - before, 2)
    }

    func testWholeParagraphInlinePluginDoesNotReplaceItsAncestors() throws {
        try requireRust()
        let registry = ParserPluginRegistry(); try registry.register(EmojiSpanPlugin())
        let source = "@😀"
        let result = try XCTUnwrap(PluginSharedSyntax.parse(source, registry: registry))
        XCTAssertNil(result.payload(for: result.tree))
        let paragraphNode = try XCTUnwrap(result.tree.children.first)
        XCTAssertEqual(paragraphNode.kind, .paragraph)
        XCTAssertNil(result.payload(for: paragraphNode))
        let sections = PluginBlockSyntax.sections(source, registry: registry)
        guard case let .parsed(document) = sections.first, let paragraph = document.children.first as? Paragraph else { return XCTFail("Preserved paragraph") }
        XCTAssertEqual(paragraph.children.count, 1)
        XCTAssertTrue(paragraph.children.first is SharedInlinePluginMarkup)
        let runs = InlineContent.runs(in: paragraph, enableHTML: false, plugins: registry)
        XCTAssertEqual(runs.count, 1)
        guard case .plugin = runs[0] else { return XCTFail("Inline payload") }
        let projection = ReaderVisibleDocumentProjection(markdown: source, enableHTML: false, plugins: registry)
        XCTAssertEqual(projection.segments.count, 1)
        XCTAssertEqual(projection.segments[0].atoms.count, 1)
    }

    func testManualASTSignedMetadataRendersInSharedBackend() throws {
        try requireRust()
        let before = RustMarkdownBridge.successfulHTMLExportCount
        for level in [-1, Int.min, Int.max] {
            XCTAssertEqual(NativeMarkdownHTMLSerializer.render(node(.heading(level), children: [node(.text, literal: "title")])),
                           "<h\(level)>title</h\(level)>\n")
        }
        let item = node(.listItem(checked: nil), children: [node(.text, literal: "item")])
        for start in [-1, Int.min, Int.max] {
            let list = NativeMarkdownNode(kind: .list(ordered: true), source: "ignored", sourceRange: .init(location: 0, length: 0),
                                          children: [item], isTight: true, listStart: start)
            XCTAssertEqual(NativeMarkdownHTMLSerializer.render(list), "<ol start=\"\(start)\">\n<li>item</li>\n</ol>\n")
        }
        XCTAssertEqual(RustMarkdownBridge.successfulHTMLExportCount - before, 6)
    }

    private struct EmojiSpanPlugin: InlineParserPlugin {
        let id = "emoji-span"; let name = "Emoji span"; let triggerCharacter: Character = "@"
        func canParse(_ text: String, at index: String.Index) -> Bool { text[index...].hasPrefix("@😀") }
        func parse(_ text: String, at index: String.Index) -> InlinePluginMatch? {
            canParse(text, at: index) ? .init(consumed: 2, text: "emoji") : nil
        }
    }

    private func node(_ kind: NativeMarkdownNode.Kind, source: String = "ignored", children: [NativeMarkdownNode] = [],
                      title: String? = nil, literal: String? = nil) -> NativeMarkdownNode {
        .init(kind: kind, source: source, sourceRange: NSRange(location: 100, length: 0),
              children: children, title: title, literalText: literal)
    }
}
