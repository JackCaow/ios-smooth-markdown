import SwiftUI
import XCTest
@testable import SmoothMarkdown

#if os(iOS)
import UIKit
#endif

@MainActor
final class HTMLReadableFlowTests: XCTestCase {
    func testSmallKeepsSourceAndCopyWhileUsingConfiguredTypography() throws {
        let source = "Before <small>小😀 e\u{301}</small> after <mark><small>marked</small></mark>"
        var style = MarkdownStyleSheet.default()
        style.designTokens.typography.paragraph = .init(size: 25)
        let reader = SmoothMarkdownView(markdown: source, enableHTML: true, styleSheet: style,
                                        selectable: true, scrollable: false)
        XCTAssertEqual(Array(reader.markdown.utf16), Array(source.utf16))
        let node = try XCTUnwrap(MarkdownSyntax.parse(source, enableHTML: true).child(at: 0))
        let document = try XCTUnwrap(ReaderSelectionDocument.compose([node], enableHTML: true, plugins: nil))
        XCTAssertEqual(document.copiedText, "Before 小😀 e\u{301} after marked")
        let small = try XCTUnwrap(document.lines.flatMap(\.runs).first { $0.text == "小😀 e\u{301}" })
        XCTAssertTrue(small.htmlSmall)
        XCTAssertTrue(document.lines.flatMap(\.runs).first { $0.text == "marked" }?.highlighted == true)
        let resolved = reader.styleSheet.resolvedHTMLStyle(.init(), underline: false, highlight: false, small: small.htmlSmall)
        XCTAssertEqual(resolved.fontSize, 20)
        style.smallStyle = .init(fontSize: 11, textColor: .purple)
        let customReader = SmoothMarkdownView(markdown: source, enableHTML: true, styleSheet: style)
        let custom = customReader.styleSheet.resolvedHTMLStyle(.init(), underline: false, highlight: false, small: true)
        XCTAssertEqual(custom.fontSize, 11)
        XCTAssertEqual(custom.textColor, .purple)
        let literal = try XCTUnwrap(MarkdownSyntax.parse(source, enableHTML: false).child(at: 0))
        XCTAssertEqual(ReaderSelectionDocument.compose([literal], enableHTML: false, plugins: nil)?.copiedText, source)
    }

    func testSameLineDetailsPreserveMarkdownBodyTailAndCodeLiterals() throws {
        let source = "before\n\n<details open><summary>Show **😀**</summary>Body `</details>` and <small>small</small></details> after\n\nlast"
        let reader = SmoothMarkdownView(markdown: source, enableHTML: true, selectable: true, scrollable: false)
        XCTAssertEqual(Array(reader.markdown.utf16), Array(source.utf16))
        let sections = DetailsSyntax.sections(reader.markdown, enableInlineHTML: true)
        let details = try XCTUnwrap(sections.compactMap { section -> DetailsSyntax.Block? in
            if case let .details(value) = section { return value }; return nil
        }.first)
        XCTAssertEqual(details.summary, "Show **😀**")
        XCTAssertEqual(details.content, "Body `</details>` and <small>small</small>")
        XCTAssertTrue(details.isOpen)
        XCTAssertEqual(sections.last, .markdown(" after\n\nlast"))
        let sourceDocument = Document(parsing: source)
        XCTAssertEqual(Array(sourceDocument.format().utf16), Array(source.utf16))
        let fenced = "```html\n<details><summary>literal</summary>body</details>\n```"
        XCTAssertFalse(DetailsSyntax.sections(fenced, enableInlineHTML: true).contains { if case .details = $0 { return true }; return false })
        for literal in ["Use `<details><summary>literal</summary>body</details>`", "    <details><summary>code</summary>body</details>"] {
            XCTAssertFalse(DetailsSyntax.sections(literal, enableInlineHTML: true).contains { if case .details = $0 { return true }; return false })
        }
    }

    func testListInlineDisclosureRetainsSourceCopyAndLiteralBoundaries() throws {
        let disclosure = "<details open><summary>展开 😀 &amp; e\u{301}</summary>Body<br>small <small>text</small> `</details>` <code></details> `code` 😀 e\u{301} `</code><details><summary>Nested</summary>inner</details></details>"
        let source = "- HTML：prefix " + disclosure + " tail &amp; after\n\nnext"
        let document = MarkdownSyntax.parse(source, enableHTML: true)
        XCTAssertEqual(Array(document.format().utf16), Array(source.utf16))
        let paragraph = try XCTUnwrap(document.child(at: 0)?.child(at: 0)?.child(at: 0))
        let runs = InlineContent.runs(in: paragraph, enableHTML: true)
        let blocks = runs.compactMap { run -> (DetailsSyntax.Block, String)? in
            if case let .details(block, source) = run { return (block, source) }; return nil
        }
        XCTAssertEqual(blocks.count, 1)
        let block = try XCTUnwrap(blocks.first)
        XCTAssertEqual(Array(block.1.utf16), Array(disclosure.utf16))
        XCTAssertEqual(block.0.summary, "展开 😀 &amp; e\u{301}")
        XCTAssertTrue(block.0.content.contains("<code></details> `code` 😀 e\u{301} `</code>"))
        XCTAssertTrue(block.0.content.hasSuffix("<details><summary>Nested</summary>inner</details>"))
        XCTAssertNil(ReaderSelectionDocument.compose([paragraph], enableHTML: true, plugins: nil))
        let reader = SmoothMarkdownView(markdown: source, enableHTML: true, selectable: true, scrollable: false)
        #if os(iOS)
        XCTAssertNil(reader.wholeDocumentSelection, "Private expansion must not advertise a fixed native visible range")
        #endif
        let projection = ReaderVisibleDocumentProjection(markdown: source, enableHTML: true)
        let copied = try XCTUnwrap(projection.copiedText(in: NSRange(location: 0, length: projection.text.utf16.count)))
        XCTAssertEqual(copied, "• HTML：prefix " + disclosure + " tail & after\nnext")
        XCTAssertEqual(Array(reader.markdown.utf16), Array(source.utf16))
        XCTAssertFalse(InlineContent.runs(in: paragraph, enableHTML: false).contains { if case .details = $0 { return true }; return false })
        for literal in [
            "prefix `<details><summary>Code</summary>literal</details>` tail",
            "prefix \\<details><summary>Escaped</summary>literal</details> tail",
            "prefix <code><details><summary>HTML code</summary>literal</details></code> tail",
            "prefix <details><summary>Unclosed</summary>literal",
            "```html\n<details><summary>Fence</summary>literal</details>\n```",
            "    <details><summary>Indent</summary>literal</details>"
        ] {
            let node = try XCTUnwrap(MarkdownSyntax.parse(literal, enableHTML: true).child(at: 0))
            XCTAssertFalse(InlineContent.runs(in: node, enableHTML: true).contains { if case .details = $0 { return true }; return false }, literal)
            XCTAssertEqual(Array(Document(parsing: literal).format().utf16), Array(literal.utf16))
        }
    }

    #if os(iOS)
    func testListInlineDisclosureWrapsAtPhoneWidthWithPrefixAndTail() {
        let words = Array(repeating: "content wraps at phone width", count: 7).joined(separator: " ")
        let source = "- HTML：prefix <details open><summary>" + words + "</summary>" + words + "<br>last</details> tail\n\nnext"
        let reader = SmoothMarkdownView(markdown: source, enableHTML: true, selectable: true, scrollable: false)
        let narrow = UIHostingController(rootView: reader)
        let wide = UIHostingController(rootView: reader)
        let narrowSize = narrow.sizeThatFits(in: CGSize(width: 280, height: 2000))
        let wideSize = wide.sizeThatFits(in: CGSize(width: 600, height: 2000))
        XCTAssertLessThanOrEqual(narrowSize.width, 281)
        XCTAssertGreaterThan(narrowSize.height, wideSize.height + 30, "Summary and open body must wrap within the disclosure proposal")
        XCTAssertGreaterThan(narrowSize.height, 160)
    }

    func testNativeSmallAttributesAndSameLineDisclosureExpansionUseRealReaderProjection() throws {
        var style = MarkdownStyleSheet.default()
        style.smallStyle = .init(fontSize: 10, textColor: .purple)
        let source = "Before <small>small😀</small> after"
        let paragraph = try XCTUnwrap(MarkdownSyntax.parse(source, enableHTML: true).child(at: 0))
        let document = try XCTUnwrap(ReaderSelectionDocument.compose([paragraph], enableHTML: true, plugins: nil))
        let renderer = ReaderSelectionTextView(document: document, styleSheet: style,
                                              onLinkTap: nil, onTextLongPress: nil,
                                              selectable: true, onCharacterTap: nil)
        let text = renderer.attributedContent(traits: MarkdownTypography.traits(for: .large)).text
        let range = (text.string as NSString).range(of: "small😀")
        XCTAssertNotEqual(range.location, NSNotFound)
        XCTAssertEqual((text.attribute(.font, at: range.location, effectiveRange: nil) as? UIFont)?.pointSize ?? 0, 10, accuracy: 0.1)
        XCTAssertEqual(text.attribute(.foregroundColor, at: range.location, effectiveRange: nil) as? UIColor, UIColor(Color.purple))
        let wholeText = NSRange(location: 0, length: text.length)
        let transformed = QuoteTextView.transformedCopyText(in: text, ruleRegions: [], range: wholeText)
        XCTAssertNil(transformed, "Small text has no visual anchors requiring a Copy transformation")
        // Match the native selection-menu path: ordinary text uses its unchanged
        // selected substring when the transform helper requests native Copy.
        let copied = transformed ?? (text.string as NSString).substring(with: wholeText)
        XCTAssertEqual(copied, document.copiedText)
        XCTAssertEqual(copied, "Before small😀 after")

        let detailsSource = "before\n\n<details><summary>Show 😀</summary>Body <small>small</small></details> after"
        let reader = SmoothMarkdownView(markdown: detailsSource, enableHTML: true, styleSheet: style,
                                        selectable: true, scrollable: false)
        let closed = try XCTUnwrap(reader.wholeDocumentSelection)
        XCTAssertFalse(closed.selection.copiedText.contains("Body"))
        let id = try XCTUnwrap(closed.projection.document.segments.first { $0.kind == .detailsSummary }?.id)
        let open = try XCTUnwrap(reader.wholeDocumentSelection(expansion: [id: true]))
        XCTAssertEqual(open.selection.copiedText, "before\nShow 😀\nBody small\nafter")
        XCTAssertEqual(open.projection.document.copiedText(in: NSRange(location: 0, length: open.projection.document.text.utf16.count)),
                       open.selection.copiedText)
        XCTAssertEqual(Array(reader.markdown.utf16), Array(detailsSource.utf16))
    }
    #endif
}
