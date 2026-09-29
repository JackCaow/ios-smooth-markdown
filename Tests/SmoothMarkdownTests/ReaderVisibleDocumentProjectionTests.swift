import Foundation
import SwiftUI
import XCTest
@testable import SmoothMarkdown

final class ReaderVisibleDocumentProjectionTests: XCTestCase {
    func testUTF16CopyAcrossImageAndEmojiUsesVisibleText() {
        let source = "Before 🐈 **bold**.\n\n![hidden alt](https://example.com/p.png)\n\nAfter 😀 `$x$`."
        let document = ReaderVisibleDocumentProjection(markdown: source)
        XCTAssertEqual(document.segments.map(\.kind), [.text, .image, .text])
        XCTAssertEqual(document.copiedText(in: NSRange(location: 0, length: document.text.utf16.count)),
                       "Before 🐈 bold.\nAfter 😀 $x$.")
        let before = document.text as NSString
        let emoji = before.range(of: "🐈")
        XCTAssertNil(document.copiedText(in: NSRange(location: emoji.location + 1, length: 1)),
                     "UTF-16 offsets must never split a surrogate pair")
        let start = before.range(of: "bold").location
        let end = NSMaxRange(before.range(of: "After 😀"))
        XCTAssertEqual(document.copiedText(in: NSRange(location: start, length: end - start)),
                       "bold.\nAfter 😀")
    }

    func testCodeTableMathFootnoteAndInlineMath() {
        let source = """
        # Header

        Inline $E=mc^2$ and footnote[^1].

        | Name | Value |
        | --- | --- |
        | A | 2 |

        ```swift
        let x = 1
        ```

        $$
        a+b
        $$

        [^1]: Footnote content.
        """
        let document = ReaderVisibleDocumentProjection(markdown: source)
        XCTAssertTrue(document.segments.contains { $0.kind == .heading })
        XCTAssertTrue(document.segments.contains { $0.kind == .table })
        XCTAssertTrue(document.segments.contains { $0.kind == .code })
        XCTAssertTrue(document.segments.contains { $0.kind == .displayMath })
        XCTAssertTrue(document.segments.contains { $0.kind == .footnote })
        let formula = document.segments.first { $0.kind == .displayMath }!
        XCTAssertEqual(formula.text, ReaderVisibleDocumentProjection.attachment)
        XCTAssertEqual(document.copiedText(in: formula.range), "a+b")
        let copied = document.copiedText(in: NSRange(location: 0, length: document.text.utf16.count))!
        XCTAssertTrue(copied.contains("Inline E=mc^2 and footnote[1]."))
        XCTAssertTrue(copied.contains("Name\tValue\nA\t2"))
        XCTAssertTrue(copied.contains("let x = 1"))
        XCTAssertTrue(copied.contains("a+b"))
        XCTAssertTrue(copied.contains("[1]: Footnote content."))
    }

    func testDetailsCopyOnlyVisibleContentAndExplicitExpansionState() {
        let source = """
        Before.

        <details>
        <summary>Hidden **section**</summary>
        Secret body.
        </details>

        <details open>
        <summary>Open section</summary>
        Visible body.
        </details>

        After.
        """
        let initial = ReaderVisibleDocumentProjection(markdown: source)
        let summaries = initial.segments.filter { $0.kind == .detailsSummary }
        XCTAssertEqual(summaries.count, 2)
        XCTAssertFalse(initial.text.contains("Secret body"))
        XCTAssertTrue(initial.text.contains("Visible body"))
        let expanded = ReaderVisibleDocumentProjection(markdown: source,
                                                         expansion: [summaries[0].id: true,
                                                                     summaries[1].id: false])
        XCTAssertEqual(expanded.segments.filter { $0.kind == .detailsSummary }.map(\.id),
                       summaries.map(\.id))
        XCTAssertTrue(expanded.text.contains("Secret body"))
        XCTAssertFalse(expanded.text.contains("Visible body"))
        XCTAssertFalse(expanded.copiedText(in: NSRange(location: 0, length: expanded.text.utf16.count))!
            .contains("<details>"))
        XCTAssertEqual(initial.segments.last?.id, expanded.segments.last?.id,
                       "Opening a disclosure must not renumber later segment IDs")
    }

    func testStableIDsSurviveAnUnrelatedInsertionAndDuplicateContentIsDistinct() {
        let original = ReaderVisibleDocumentProjection(markdown: "Alpha\n\nBeta\n\nBeta")
        let revised = ReaderVisibleDocumentProjection(markdown: "New\n\nAlpha\n\nBeta\n\nBeta")
        XCTAssertEqual(Array(original.segments.map(\.id)), Array(revised.segments.dropFirst().map(\.id)))
        XCTAssertNotEqual(original.segments[1].id, original.segments[2].id)
        XCTAssertEqual(original.segments.map(\.range.location), [0, 6, 11])
    }

    func testListWithFormulaAndImageUsesAContinuousCopyProjection() {
        let source = "- First $x+y$ item\n- Second ![visual](https://example.com/p.png) item"
        let document = ReaderVisibleDocumentProjection(markdown: source)
        XCTAssertEqual(document.segments.count, 1)
        XCTAssertEqual(document.copiedText(in: NSRange(location: 0, length: document.text.utf16.count)),
                       "• First x+y item\n• Second  item")
        XCTAssertTrue(document.text.contains(ReaderVisibleDocumentProjection.attachment))
    }

    func testMermaidDiagramRemainsAnOpaqueAnchor() {
        let source = """
        Before.

        ```mermaid
        flowchart LR
          A --> B
        ```

        After.
        """
        let document = ReaderVisibleDocumentProjection(markdown: source,
                                                        plugins: .builtIns())
        XCTAssertEqual(document.segments.map(\.kind), [.text, .plugin("mermaid"), .text])
        XCTAssertEqual(document.copiedText(in: NSRange(location: 0, length: document.text.utf16.count)),
                       "Before.\nAfter.")
    }

    func testHostedBuiltInCardsHaveOneMeasuredAnchorAndExactSemanticCopy() {
        let source = """
        Before.

        ::: warning Heads up
        Careful.
        :::

        ```mermaid
        flowchart LR
          A --> B
        ```

        After.
        """
        let document = ReaderVisibleDocumentProjection(markdown: source, plugins: .builtIns(),
                                                       hostBuiltInPlugins: true)
        XCTAssertEqual(document.segments.map(\.kind),
                       [.text, .plugin("admonition"), .plugin("mermaid"), .text])
        XCTAssertEqual(document.segments[1].text, ReaderVisibleDocumentProjection.attachment)
        XCTAssertEqual(document.segments[2].text, ReaderVisibleDocumentProjection.attachment)
        XCTAssertEqual(document.copiedText(in: NSRange(location: 0, length: document.text.utf16.count)),
                       "Before.\nHeads up\nCareful.\nAfter.")
    }

    func testBuiltInInlinePluginRunsAgreeWithVisibleProjection() throws {
        let source = "Hello @alice :smile: #release.\n\nAfter."
        let nodes = Array(MarkdownSyntax.parse(source).children)
        let selection = try XCTUnwrap(ReaderSelectionDocument.compose(
            nodes, enableHTML: false, plugins: .builtIns(), visualBlockAnchors: true))
        let projection = ReaderVisibleDocumentProjection(markdown: source, plugins: .builtIns())
        XCTAssertEqual(selection.selectionText, projection.text)
        XCTAssertEqual(selection.copiedText, "Hello @alice 😄 #release.\nAfter.")
        XCTAssertEqual(selection.lines[0].runs.filter(\.pluginAccent).map(\.text),
                       ["@alice", "#release"])
    }

    func testThirdPartyPluginWithoutSelectionContractIsOpaque() throws {
        let plugins = ParserPluginRegistry()
        try plugins.register(BadgePlugin())
        let document = ReaderVisibleDocumentProjection(markdown: "A %badge B", plugins: plugins)
        XCTAssertEqual(document.segments.count, 1)
        XCTAssertTrue(document.text.contains(ReaderVisibleDocumentProjection.attachment))
        XCTAssertEqual(document.copiedText(in: NSRange(location: 0, length: document.text.utf16.count)),
                       "A  B")
    }

    func testBuiltInPluginVisibleTextAndCollapsedThinking() {
        let source = "Hello @alice :smile:.\n\n::: warning Heads up\nCareful.\n:::" +
            "\n\n<thinking>\nHidden thought.\n</thinking>"
        let plugins = ParserPluginRegistry.builtIns()
        let initial = ReaderVisibleDocumentProjection(markdown: source, plugins: plugins)
        let copied = initial.copiedText(in: NSRange(location: 0, length: initial.text.utf16.count))!
        XCTAssertTrue(copied.contains("Hello @alice 😄."))
        XCTAssertTrue(copied.contains("Heads up\nCareful."))
        XCTAssertTrue(copied.contains("Thinking..."))
        XCTAssertFalse(copied.contains("Hidden thought."))
        let thinking = initial.segments.first { $0.kind == .plugin("thinking") }!
        let expanded = ReaderVisibleDocumentProjection(markdown: source, plugins: plugins,
                                                        expansion: [thinking.id: true])
        XCTAssertTrue(expanded.text.contains("Hidden thought."))
    }

    func testFlutterReadmeFixtureKeepsClosedDetailsHidden() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "FlutterREADME", withExtension: "md"))
        let source = try String(contentsOf: url)
        let document = ReaderVisibleDocumentProjection(markdown: source)
        XCTAssertTrue(document.segments.contains { $0.kind == .detailsSummary })
        XCTAssertTrue(document.text.contains("Text Formatting"))
        XCTAssertFalse(document.text.contains("Hidden content here."))
        XCTAssertEqual(document.segments.count, Set(document.segments.map(\.id)).count)
        XCTAssertNotNil(document.copiedText(in: NSRange(location: 0, length: document.text.utf16.count)))
    }
}

private struct BadgePlugin: InlineParserPlugin {
    let id = "test_badge"
    let name = "Badge"
    let triggerCharacter: Character = "%"

    func canParse(_ text: String, at index: String.Index) -> Bool {
        text[index...].hasPrefix("%badge")
    }

    func parse(_ text: String, at index: String.Index) -> InlinePluginMatch? {
        canParse(text, at: index) ? InlinePluginMatch(consumed: 6, text: "badge") : nil
    }

    func render(_ match: InlinePluginMatch) -> AnyView { AnyView(Text("visual badge")) }
}
