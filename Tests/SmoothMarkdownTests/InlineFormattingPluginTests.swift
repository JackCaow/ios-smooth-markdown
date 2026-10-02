import SwiftUI
import XCTest
@testable import SmoothMarkdown

final class InlineFormattingPluginTests: XCTestCase {
    private func registry() throws -> ParserPluginRegistry {
        let registry = ParserPluginRegistry()
        try registry.registerAll([HighlightPlugin(), SuperscriptPlugin(), SubscriptPlugin()])
        return registry
    }
    private func document(_ source: String, plugins: ParserPluginRegistry) throws -> Document {
        try XCTUnwrap(PluginSharedSyntax.document(source, registry: plugins, enableHTML: false))
    }
    private func text(_ document: Markup, plugins: ParserPluginRegistry) -> String {
        document.children.map { child in
            InlineContent.runs(in: child, enableHTML: false, plugins: plugins).compactMap { run in
                if case let .text(value, _, _, _) = run { return value }
                return nil
            }.joined()
        }.joined(separator: "\n")
    }

    func testOptInSharedHooksPreserveOriginalUTF16RangesAndVisibleStyles() throws {
        let plugins = try registry()
        let source = "😀 ==高亮== x^2^ H~2~O"
        let parsed = try XCTUnwrap(PluginSharedSyntax.parse(source, registry: plugins))
        XCTAssertEqual(parsed.tree.source, source)
        let ranges = parsed.custom.keys.sorted { $0.location < $1.location }
        XCTAssertEqual(ranges.map { (source as NSString).substring(with: $0) }, ["==高亮==", "^2^", "~2~"])
        XCTAssertEqual(ranges.first?.location, 3)
        let doc = try document(source, plugins: plugins)
        XCTAssertEqual(text(doc, plugins: plugins), "😀 高亮 x2 H2O")
        let runs = InlineContent.runs(in: try XCTUnwrap(doc.children.first), enableHTML: false, plugins: plugins)
        let styled = runs.compactMap { run -> (String, InlineContent.Style)? in
            if case let .text(value, style, _, _) = run, style.highlighted || style.script != nil { return (value, style) }
            return nil
        }
        XCTAssertEqual(styled.map(\.0), ["高亮", "2", "2"])
        XCTAssertTrue(styled[0].1.highlighted)
        XCTAssertEqual(styled[1].1.script, .sup)
        XCTAssertEqual(styled[2].1.script, .sub)
        let ordinary = MarkdownSyntax.parse(source, useCache: false)
        XCTAssertEqual(text(ordinary, plugins: ParserPluginRegistry()), "😀 ==高亮== x^2^ H2O")
        XCTAssertTrue(InlineContent.runs(in: ordinary.children.first!, enableHTML: false).contains {
            if case let .text(_, style, _, _) = $0 { return style.strike }; return false
        }, "Single-tilde GFM remains the default")
    }

    private struct FormattingOverride: MarkdownWidgetBuilder {
        var onBuild: ((MarkdownPluginNode) -> Void)? = nil
        func canBuild(_ node: Markup) -> Bool { false }
        func build(_ node: Markup, context: MarkdownRenderContext) -> AnyView { AnyView(Text("unused")) }
        func canBuild(_ node: MarkdownPluginNode) -> Bool {
            ["highlight", "superscript", "subscript"].contains(node.type)
        }
        func build(_ node: MarkdownPluginNode, context: MarkdownRenderContext) -> AnyView {
            onBuild?(node)
            return AnyView(Text("override: " + node.content))
        }
    }

    @MainActor
    func testExplicitPluginBuildersKeepPriorityOverNativeFormatting() throws {
        let plugins = try registry()
        let builders = BuilderRegistry()
        for id in ["highlight", "superscript", "subscript"] {
            builders.register(id, builder: FormattingOverride())
        }
        let source = "==highlight== x^2^ H~2~O"
        let paragraph = try XCTUnwrap(try document(source, plugins: plugins).children.first)
        let runs = InlineContent.runs(in: paragraph, enableHTML: false, plugins: plugins,
                                     hasCustomPluginBuilder: { builders.findBuilder($0) != nil })
        let overridden = runs.compactMap { run -> String? in
            if case let .plugin(plugin, match) = run {
                XCTAssertNotNil(builders.findBuilder(MarkdownPluginNode(plugin: plugin, match: match)))
                return plugin.id
            }
            return nil
        }
        XCTAssertEqual(overridden, ["highlight", "superscript", "subscript"])
        let projection = ReaderVisibleDocumentProjection(markdown: source, plugins: plugins, builderRegistry: builders)
        XCTAssertEqual(projection.text.filter { String($0) == ReaderVisibleDocumentProjection.attachment }.count, 3)

        let reader = SmoothMarkdownView(markdown: source, plugins: plugins, builderRegistry: builders,
                                        selectable: true, selectionController: SmoothSelectionController(), scrollable: false)
        XCTAssertTrue(reader.containsCustomBlockBuilder(paragraph))
        #if os(iOS)
        XCTAssertNil(reader.wholeDocumentSelection, "Custom plugin views cannot silently become native selection text")
        var rendered: Set<String> = []
        for id in ["highlight", "superscript", "subscript"] {
            builders.register(id, builder: FormattingOverride(onBuild: { rendered.insert($0.type) }))
        }
        let host = UIHostingController(rootView: SmoothMarkdownView(markdown: source + " <kbd>K</kbd>",
            enableHTML: true, plugins: plugins, builderRegistry: builders, scrollable: false))
        _ = host.sizeThatFits(in: CGSize(width: 300, height: 1000))
        XCTAssertEqual(rendered, ["highlight", "superscript", "subscript"],
                       "Explicit plugin views take priority even beside native keycaps")
        #endif
    }

    func testCodeEscapesLinksAndGFMStrikeStayInTheirNativeGrammar() throws {
        let plugins = try registry()
        let protected = "`==code== x^2^ H~2~O` \\==escaped== x\\^2^ H\\~2~O\n\n```\n==fenced== x^2^ H~2~O\n```"
        XCTAssertTrue(try XCTUnwrap(PluginSharedSyntax.parse(protected, registry: plugins)).custom.isEmpty)
        for source in ["~deleted~", "~~deleted~~", "a~word~b", "H~~2~~O", "^two words^", "== unfinished", "==`code`=="] {
            XCTAssertTrue(try XCTUnwrap(PluginSharedSyntax.parse(source, registry: plugins)).custom.isEmpty, source)
        }
        let link = "[==label==](https://example.test/^2^/H~2~O)"
        let parsed = try XCTUnwrap(PluginSharedSyntax.parse(link, registry: plugins))
        XCTAssertEqual(parsed.custom.count, 1)
        XCTAssertEqual((link as NSString).substring(with: parsed.custom.keys.first!), "==label==")
        let copied = try XCTUnwrap(ReaderSelectionDocument.compose(Array(try document(link, plugins: plugins).children), enableHTML: false, plugins: plugins))
        XCTAssertEqual(copied.copiedText, "label")
        XCTAssertEqual(copied.lines[0].runs[0].style.link?.absoluteString, URL(string: "https://example.test/^2^/H~2~O")!.absoluteString)
    }

    func testTableCellsKeepStyledCopyableTextAndStreamingPrefixesRemainLiteralUntilClosed() throws {
        let plugins = try registry()
        let source = "| A | B |\n| - | - |\n| ==高亮== | x^2^ H~2~O |"
        let doc = try document(source, plugins: plugins)
        let table = try XCTUnwrap(doc.children.first as? Markdown.Table)
        let row = try XCTUnwrap(table.body.children.first)
        let cellRuns = row.children.compactMap { ReaderSelectionDocument.copyableInlineRuns($0, enableHTML: false, plugins: plugins) }
        XCTAssertEqual(cellRuns.count, 2)
        XCTAssertEqual(cellRuns[0].map(\.text).joined(), "高亮")
        XCTAssertTrue(cellRuns[0][0].highlighted)
        XCTAssertEqual(cellRuns[1].map(\.text).joined(), "x2 H2O")
        XCTAssertEqual(cellRuns[1].compactMap { $0.style.script }, [.sup, .sub])
        for (open, complete, visible) in [("==高亮", "==高亮==", "高亮"), ("x^2", "x^2^", "x2"), ("H~2", "H~2~O", "H2O")] {
            XCTAssertTrue(try XCTUnwrap(PluginSharedSyntax.parse(open, registry: plugins)).custom.isEmpty)
            let cached = MarkdownParseCache(maxSize: 2)
            _ = try XCTUnwrap(cached.parseShared(open, plugins: plugins, enableHTML: false))
            let final = try XCTUnwrap(cached.parseShared(complete, plugins: plugins, enableHTML: false))
            XCTAssertEqual(text(final, plugins: plugins), visible)
            XCTAssertEqual(text(try document(complete, plugins: plugins), plugins: plugins), visible)
        }
    }

    @MainActor
    func testStreamSessionAndBatchReaderAgreeAtEveryCharacterPrefix() throws {
        let plugins = try registry()
        let source = "Before 😀 ==高亮== x^2^ H~2~O ~deleted~ [link][ref]\n\n| A | B |\n| - | - |\n| ==table== | x^2^ |\n\n[ref]: /ok"
        let stream = StreamMarkdownRenderSession()
        stream.configure(plugins: plugins, enableHTML: false)
        var prefix = ""
        for character in source {
            prefix.append(character)
            let snapshot = try XCTUnwrap(stream.update(prefix))
            let batch = try document(prefix, plugins: plugins)
            XCTAssertEqual(text(snapshot.document, plugins: plugins), text(batch, plugins: plugins), prefix)
            XCTAssertEqual(snapshot.document.format(), batch.format(), prefix)
            XCTAssertEqual(snapshot.source.utf16.map { $0 }, prefix.utf16.map { $0 })
        }
    }

    #if os(iOS)
    @MainActor
    func testNativeSelectableReaderUsesHostHighlightAndScriptTokens() throws {
        let plugins = try registry()
        let source = "==高亮== x^2^ H~2~O"
        let doc = try document(source, plugins: plugins)
        let selection = try XCTUnwrap(ReaderSelectionDocument.compose(Array(doc.children), enableHTML: false, plugins: plugins))
        var sheet = MarkdownStyleSheet.light()
        sheet.highlightStyle = .init(textColor: .red, backgroundColor: .green)
        sheet.superscriptStyle = .init(fontSize: 11, textColor: .blue)
        sheet.subscriptStyle = .init(fontSize: 10, textColor: .orange)
        let reader = ReaderSelectionTextView(document: selection, styleSheet: sheet,
            onLinkTap: nil, onTextLongPress: nil, selectable: true, onCharacterTap: nil)
        let attributed = reader.attributedContent(traits: MarkdownTypography.traits(for: .large)).text
        XCTAssertEqual(attributed.string, "高亮 x2 H2O")
        XCTAssertEqual(selection.copiedText, attributed.string)
        let highlighted = (attributed.string as NSString).range(of: "高亮")
        XCTAssertEqual(attributed.attribute(.foregroundColor, at: highlighted.location, effectiveRange: nil) as? UIColor, UIColor(Color.red))
        XCTAssertEqual(attributed.attribute(.backgroundColor, at: highlighted.location, effectiveRange: nil) as? UIColor, UIColor(Color.green))
        let sup = (attributed.string as NSString).range(of: "x2").location + 1
        let sub = (attributed.string as NSString).range(of: "H2O").location + 1
        XCTAssertEqual((attributed.attribute(.font, at: sup, effectiveRange: nil) as? UIFont)?.pointSize, 11)
        XCTAssertEqual((attributed.attribute(.font, at: sub, effectiveRange: nil) as? UIFont)?.pointSize, 10)
        XCTAssertEqual(attributed.attribute(.foregroundColor, at: sup, effectiveRange: nil) as? UIColor, UIColor(Color.blue))
        XCTAssertEqual(attributed.attribute(.foregroundColor, at: sub, effectiveRange: nil) as? UIColor, UIColor(Color.orange))
        XCTAssertGreaterThan(attributed.attribute(.baselineOffset, at: sup, effectiveRange: nil) as? CGFloat ?? 0, 0)
        XCTAssertLessThan(attributed.attribute(.baselineOffset, at: sub, effectiveRange: nil) as? CGFloat ?? 0, 0)
        let publicReader = SmoothMarkdownView(markdown: source, plugins: plugins, selectable: true,
                                              selectionController: SmoothSelectionController(), scrollable: false)
        XCTAssertNotNil(publicReader.wholeDocumentSelection)
        let longHighlight = "==" + String(repeating: "wrapped highlight ", count: 8).trimmingCharacters(in: .whitespaces) + "=="
        let hosting = UIHostingController(rootView: SmoothMarkdownView(markdown: longHighlight, plugins: plugins, scrollable: false))
        XCTAssertGreaterThan(hosting.sizeThatFits(in: CGSize(width: 200, height: 1000)).height, 60)
    }
    #endif
}
