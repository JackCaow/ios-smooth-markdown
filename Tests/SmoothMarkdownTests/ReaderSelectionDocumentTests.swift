import XCTest
import Markdown
@testable import SmoothMarkdown

final class ReaderSelectionDocumentTests: XCTestCase {
    func testInlineCodeParagraphNativeRouteKeepsCodeAndAdjacentLink() {
        let source = "Before `var x = 42;` [link](https://example.com) after"
        guard let paragraph = MarkdownSyntax.parse(source).child(at: 0) as? Paragraph,
              let document = ReaderSelectionDocument.inlineCodeParagraph(
                  paragraph, enableHTML: false, plugins: nil) else {
            return XCTFail("Inline code paragraph should use native text layout")
        }
        XCTAssertEqual(document.copiedText, "Before var x = 42; link after")
        XCTAssertEqual(document.lines.flatMap(\.runs).filter(\.code).map(\.text), ["var x = 42;"])
        XCTAssertEqual(document.lines.flatMap(\.runs).compactMap(\.style.link),
                       [URL(string: "https://example.com")!])

        let prose = MarkdownSyntax.parse("Before and after").child(at: 0) as! Paragraph
        XCTAssertNil(ReaderSelectionDocument.inlineCodeParagraph(prose, enableHTML: false,
                                                                  plugins: nil))
        let mixed = MarkdownSyntax.parse("Before `code` ![image](https://example.com/a.png)")
            .child(at: 0) as! Paragraph
        XCTAssertNil(ReaderSelectionDocument.inlineCodeParagraph(mixed, enableHTML: false,
                                                                  plugins: nil),
                     "An image must retain the SwiftUI inline flow layout")
    }

    func testConsecutiveHeadingParagraphListAndQuoteComposeOneCopyRange() {
        let source = """
        # Heading

        First **bold** [link](https://example.com).

        - One
        - Two

        > Quoted text
        """
        let nodes = Array(MarkdownSyntax.parse(source).children)
        let groups = ReaderSelectionGroup.group(nodes, enableHTML: false, plugins: nil)
        XCTAssertEqual(groups.count, 1)
        guard case let .selectable(selected) = groups[0],
              let document = ReaderSelectionDocument.compose(selected, enableHTML: false, plugins: nil) else {
            return XCTFail("Expected one cross-block selection group")
        }
        XCTAssertEqual(document.lines.count, 5)
        XCTAssertEqual(document.lines[0].kind, .heading(1))
        XCTAssertEqual(document.lines[3].kind, .list)
        XCTAssertEqual(document.lines[4].kind, .quote)
        XCTAssertEqual(document.copiedText,
                       "Heading\nFirst bold link.\n• One\n• Two\nQuoted text")
        XCTAssertTrue(document.lines[1].runs.contains { $0.style.bold && $0.text == "bold" })
        XCTAssertEqual(document.lines[1].runs.compactMap(\.style.link), [URL(string: "https://example.com")!])
    }

    func testImageBridgeRetainsImageBlockAndCodeBoundary() {
        let source = """
        First paragraph.

        Second paragraph.

        ![image](https://example.com/a.png)

        ```swift
        print(1)
        ```

        Last paragraph.
        """
        let groups = ReaderSelectionGroup.group(Array(MarkdownSyntax.parse(source).children),
                                                 enableHTML: false, plugins: nil)
        XCTAssertEqual(groups.count, 3)
        guard case let .blockBridge(nodes) = groups[0],
              let bridge = ReaderBlockRangeDocument(nodes, enableHTML: false, plugins: nil) else {
            return XCTFail("Expected an image range with original image block")
        }
        XCTAssertEqual(bridge.segments.count, 2)
        XCTAssertFalse(bridge.segments[0].isImage)
        XCTAssertTrue(bridge.segments[1].isImage)
        XCTAssertEqual(bridge.copiedText(in: 0...1, enableHTML: false, plugins: nil),
                       "First paragraph.\nSecond paragraph.")
        for index in [1, 2] {
            if case .individual = groups[index] { } else { XCTFail("Expected individual block at \(index)") }
        }
    }

    func testImageRangeCopiesTextAroundImageWithoutAltOrOverlayPadding() {
        let source = "Before **bold**.\n\n![photo](https://example.com/photo.png)\n\nAfter [link](https://example.com)."
        let groups = ReaderSelectionGroup.group(Array(MarkdownSyntax.parse(source).children),
                                                 enableHTML: false, plugins: nil)
        XCTAssertEqual(groups.count, 1)
        guard case let .blockBridge(nodes) = groups[0],
              let bridge = ReaderBlockRangeDocument(nodes, enableHTML: false, plugins: nil) else {
            return XCTFail("Expected text-image-text bridge")
        }
        XCTAssertEqual(bridge.segments.map(\.isImage), [false, true, false])
        XCTAssertEqual(bridge.copiedText(in: 0...2, enableHTML: false, plugins: nil),
                       "Before bold.\nAfter link.")
        XCTAssertEqual(bridge.copiedText(in: 0...1, enableHTML: false, plugins: nil), "Before bold.")
        XCTAssertNil(bridge.copiedText(in: 1...1, enableHTML: false, plugins: nil))
        XCTAssertNil(bridge.copiedText(in: 0...3, enableHTML: false, plugins: nil))
    }

    func testImageBridgeCopiesCharacterEndpointsWithoutImageAlt() {
        let source = "Before 🐈 image.\n\n![hidden alt](https://example.com/photo.png)\n\nAfter 😀 image."
        let groups = ReaderSelectionGroup.group(Array(MarkdownSyntax.parse(source).children),
                                                 enableHTML: false, plugins: nil)
        guard groups.count == 1, case let .blockBridge(nodes) = groups[0],
              let bridge = ReaderBlockRangeDocument(nodes, enableHTML: false, plugins: nil) else {
            return XCTFail("Expected text-image-text bridge")
        }
        let first = "Before 🐈 image." as NSString
        let last = "After 😀 image." as NSString
        let start = first.range(of: "image.").location
        let end = last.range(of: "😀").location + last.range(of: "😀").length
        XCTAssertEqual(bridge.copiedText(in: 0...2, startUTF16: start, endUTF16: end,
                                         enableHTML: false, plugins: nil), "image.\nAfter 😀")
        XCTAssertEqual(bridge.copiedText(in: 0...2, enableHTML: false, plugins: nil),
                       "Before 🐈 image.\nAfter 😀 image.")
        XCTAssertNil(bridge.copiedText(in: 0...2, startUTF16: first.length + 1,
                                       enableHTML: false, plugins: nil))
        XCTAssertNil(bridge.copiedText(in: 0...2, startUTF16: 8,
                                       enableHTML: false, plugins: nil),
                     "A UTF-16 endpoint must not split a surrogate pair")
    }

    func testRuleAnchorDisablesCharacterOffsetButKeepsWholeBlockCopy() {
        let source = "Before.\n\n---\n\n![photo](https://example.com/photo.png)\n\nAfter."
        let groups = ReaderSelectionGroup.group(Array(MarkdownSyntax.parse(source).children),
                                                 enableHTML: false, plugins: nil)
        guard groups.count == 1, case let .blockBridge(nodes) = groups[0],
              let bridge = ReaderBlockRangeDocument(nodes, enableHTML: false, plugins: nil) else {
            return XCTFail("Expected rule-image bridge")
        }
        XCTAssertEqual(bridge.copiedText(in: 0...2, enableHTML: false, plugins: nil),
                       "Before.\nAfter.")
        let textDocument = ReaderSelectionDocument.compose(bridge.segments[0].nodes,
                                                           enableHTML: false, plugins: nil)!
        XCTAssertNotEqual(textDocument.selectionText, textDocument.copiedText)
        XCTAssertNil(bridge.copiedText(in: 0...2, startUTF16: 3,
                                       enableHTML: false, plugins: nil))
    }

    func testUnsafeImageSourceDoesNotBecomeSelectionBridge() {
        let source = "Before\n\n![bad](javascript:alert(1))\n\nAfter"
        let groups = ReaderSelectionGroup.group(Array(MarkdownSyntax.parse(source).children),
                                                 enableHTML: false, plugins: nil)
        XCTAssertFalse(groups.contains {
            if case .blockBridge = $0 { return true }
            return false
        })
    }

    func testThematicBreakStaysInCrossBlockSelectionAndCopiesAsBlankLine() {
        let source = "First paragraph.\n\n---\n\nLast paragraph."
        let groups = ReaderSelectionGroup.group(Array(MarkdownSyntax.parse(source).children),
                                                 enableHTML: false, plugins: nil)
        XCTAssertEqual(groups.count, 1)
        guard case let .selectable(nodes) = groups[0],
              let document = ReaderSelectionDocument.compose(nodes, enableHTML: false, plugins: nil) else {
            return XCTFail("Expected one range across the rule")
        }
        XCTAssertEqual(document.lines.map(\.kind), [.paragraph, .rule, .paragraph])
        XCTAssertEqual(document.copiedText, "First paragraph.\n\nLast paragraph.")
        XCTAssertEqual(document.lines[1].runs.map(\.text).joined(), ReaderSelectionDocument.ruleAnchor)
    }

    func testUnsafeLinkNeverBecomesActiveInSelectionDocument() {
        let source = "First [unsafe](javascript:alert(1)).\n\nSecond paragraph."
        let nodes = Array(MarkdownSyntax.parse(source).children)
        let document = ReaderSelectionDocument.compose(nodes, enableHTML: false, plugins: nil)!
        XCTAssertEqual(document.lines.count, 2)
        XCTAssertTrue(document.lines.flatMap(\.runs).allSatisfy { $0.style.link == nil })
    }

    func testQuoteIDsKeepParagraphsInOneDecorationAndSeparateAdjacentQuotes() {
        let source = """
        > First paragraph
        >
        > Second paragraph

        Ordinary paragraph

        > Another quote
        """
        let document = ReaderSelectionDocument.compose(Array(MarkdownSyntax.parse(source).children),
                                                       enableHTML: false, plugins: nil)!
        let quoteLines = document.lines.filter { $0.quoteDepth > 0 }
        XCTAssertEqual(quoteLines.count, 3)
        XCTAssertEqual(quoteLines[0].quoteIDs, quoteLines[1].quoteIDs)
        XCTAssertNotEqual(quoteLines[1].quoteIDs, quoteLines[2].quoteIDs)
    }

    func testNestedQuoteRetainsOuterAndInnerDecorationIDs() {
        let source = "> Outer\n> > Inner"
        let document = ReaderSelectionDocument.compose(Array(MarkdownSyntax.parse(source).children),
                                                       enableHTML: false, plugins: nil)!
        XCTAssertEqual(document.lines.count, 2)
        XCTAssertEqual(document.lines[0].quoteIDs.count, 1)
        XCTAssertEqual(document.lines[1].quoteIDs.count, 2)
        XCTAssertEqual(document.lines[0].quoteIDs[0], document.lines[1].quoteIDs[0])
    }
    func testTableBridgeCopiesVisibleCellsWithInlineMarksAcrossProse() {
        let source = """
        Before table.

        | Name | Value |
        | --- | --- |
        | **Alpha** | 42 |
        | Beta | `x` |

        After table.
        """
        let groups = ReaderSelectionGroup.group(Array(MarkdownSyntax.parse(source).children),
                                                 enableHTML: false, plugins: nil)
        XCTAssertEqual(groups.count, 1)
        guard case let .blockBridge(nodes) = groups[0],
              let bridge = ReaderBlockRangeDocument(nodes, enableHTML: false, plugins: nil) else {
            return XCTFail("Expected text-table-text bridge")
        }
        XCTAssertEqual(bridge.segments.count, 3)
        XCTAssertEqual(bridge.copiedText(in: 0...2, enableHTML: false, plugins: nil),
                       "Before table.\nName\tValue\nAlpha\t42\nBeta\tx\nAfter table.")
        XCTAssertEqual(bridge.copiedText(in: 1...2, enableHTML: false, plugins: nil),
                       "Name\tValue\nAlpha\t42\nBeta\tx\nAfter table.")
    }

    func testTableAndImageBridgeKeepsTableTextAndOmitsImageAlt() {
        let source = "Before\n\n| Name | Value |\n| --- | --- |\n| Alpha | 42 |\n\n![photo](https://example.com/photo.png)\n\nAfter"
        let groups = ReaderSelectionGroup.group(Array(MarkdownSyntax.parse(source).children),
                                                 enableHTML: false, plugins: nil)
        XCTAssertEqual(groups.count, 1)
        guard case let .blockBridge(nodes) = groups[0],
              let bridge = ReaderBlockRangeDocument(nodes, enableHTML: false, plugins: nil) else {
            return XCTFail("Expected table and image in one range")
        }
        XCTAssertEqual(bridge.segments.count, 4)
        XCTAssertEqual(bridge.copiedText(in: 0...3, enableHTML: false, plugins: nil),
                       "Before\nName\tValue\nAlpha\t42\nAfter")
    }

    func testAdjacentImagesStayIndependentWithoutCopyableText() {
        let source = "![one](https://example.com/one.png)\n\n![two](https://example.com/two.png)"
        let groups = ReaderSelectionGroup.group(Array(MarkdownSyntax.parse(source).children),
                                                 enableHTML: false, plugins: nil)
        XCTAssertEqual(groups.count, 2)
        XCTAssertTrue(groups.allSatisfy {
            if case .individual = $0 { return true }
            return false
        })
    }

    func testDisplayMathBridgeCopiesLatexBetweenStyledProse() {
        let groups = ReaderMathSelectionGroup.group(mathItems("Before **bold**.\n\n$$\nE=mc^2\n$$\n\nAfter."),
                                                    enableHTML: false, plugins: nil)
        XCTAssertEqual(groups.count, 1)
        guard case let .bridge(items) = groups[0],
              let document = ReaderBlockRangeDocument(items, enableHTML: false, plugins: nil) else {
            return XCTFail("Expected one prose-math-prose range")
        }
        XCTAssertEqual(document.segments.count, 3)
        XCTAssertEqual(document.segments[1].kind, .displayMath("E=mc^2"))
        XCTAssertEqual(document.copiedText(in: 0...2, enableHTML: false, plugins: nil),
                       "Before bold.\nE=mc^2\nAfter.")
        XCTAssertEqual(document.copiedText(in: 1...2, enableHTML: false, plugins: nil),
                       "E=mc^2\nAfter.")
    }

    func testDisplayMathBridgeIncludesTableAndSkipsImageAlt() {
        let source = "Before\n\n| Name | Value |\n| --- | --- |\n| Alpha | 42 |\n\n$$x+y$$\n\n![plot](https://example.com/p.png)\n\nAfter"
        let groups = ReaderMathSelectionGroup.group(mathItems(source), enableHTML: false, plugins: nil)
        XCTAssertEqual(groups.count, 1)
        guard case let .bridge(items) = groups[0],
              let document = ReaderBlockRangeDocument(items, enableHTML: false, plugins: nil) else {
            return XCTFail("Expected table-math-image range")
        }
        XCTAssertEqual(document.segments.count, 5)
        XCTAssertEqual(document.copiedText(in: 0...4, enableHTML: false, plugins: nil),
                       "Before\nName\tValue\nAlpha\t42\nx+y\nAfter")
    }

    func testFencedCodeRemainsBoundaryAfterDisplayMath() {
        let source = "Before\n\n$$x+y$$\n\n```swift\nprint(1)\n```\n\nAfter"
        let groups = ReaderMathSelectionGroup.group(mathItems(source), enableHTML: false, plugins: nil)
        XCTAssertEqual(groups.count, 3)
        guard case let .bridge(items) = groups[0],
              let document = ReaderBlockRangeDocument(items, enableHTML: false, plugins: nil),
              case let .legacy(.individual(node)) = groups[1], node is Markdown.CodeBlock else {
            return XCTFail("Code block should break the math range")
        }
        XCTAssertEqual(document.copiedText(in: 0...1, enableHTML: false, plugins: nil), "Before\nx+y")
    }

    func testBuiltinCodeJoinsProseTableAndMathRangeWithoutExtraNewline() {
        let source = "Before\n\n| Name | Value |\n| --- | --- |\n| Alpha | 42 |\n\n```swift\nlet answer = 42\n```\n\n$$x+y$$\n\nAfter"
        let groups = ReaderMathSelectionGroup.group(mathItems(source), enableHTML: false, plugins: nil,
                                                    allowCodeBlocks: true)
        XCTAssertEqual(groups.count, 1)
        guard case let .bridge(items) = groups[0],
              let document = ReaderBlockRangeDocument(items, enableHTML: false, plugins: nil) else {
            return XCTFail("Expected prose-table-code-math range")
        }
        XCTAssertEqual(document.segments.count, 5)
        guard case let .code(code) = document.segments[2].kind else {
            return XCTFail("Expected original code segment")
        }
        XCTAssertEqual(code, "let answer = 42\n")
        XCTAssertEqual(document.copiedText(in: 2...2, enableHTML: false, plugins: nil), code)
        XCTAssertEqual(document.copiedText(in: 0...4, enableHTML: false, plugins: nil),
                       "Before\nName\tValue\nAlpha\t42\nlet answer = 42\nx+y\nAfter")
    }

    func testCodeBoundaryCanBeKeptForCustomBuilderOrHiddenCopyButton() {
        let source = "Before\n\n```swift\nlet answer = 42\n```\n\nAfter"
        let nodes = Array(MarkdownSyntax.parse(source).children)
        let bridged = ReaderSelectionGroup.group(nodes, enableHTML: false, plugins: nil,
                                                 allowCodeBlocks: true)
        XCTAssertEqual(bridged.count, 1)
        guard case .blockBridge = bridged[0] else { return XCTFail("Expected default-code bridge") }

        let separate = ReaderSelectionGroup.group(nodes, enableHTML: false, plugins: nil,
                                                  allowCodeBlocks: false)
        XCTAssertEqual(separate.count, 3)
        guard case let .individual(code) = separate[1], code is Markdown.CodeBlock else {
            return XCTFail("Expected code to stay independent when host owns it")
        }
    }

    func testBuiltinCodeAndImageShareRangeWhileImageAltIsOmitted() {
        let source = "Before\n\n![Picture](https://example.com/picture.png)\n\n```swift\nlet answer = 42\n```\n\nAfter"
        let nodes = Array(MarkdownSyntax.parse(source).children)
        let groups = ReaderSelectionGroup.group(nodes, enableHTML: false, plugins: nil,
                                                allowCodeBlocks: true)
        XCTAssertEqual(groups.count, 1)
        guard case let .blockBridge(blocks) = groups[0],
              let document = ReaderBlockRangeDocument(blocks, enableHTML: false, plugins: nil) else {
            return XCTFail("Expected image and code in one range")
        }
        XCTAssertEqual(document.segments.count, 4)
        XCTAssertEqual(document.copiedText(in: 0...3, enableHTML: false, plugins: nil),
                       "Before\nlet answer = 42\nAfter")
    }

    func testStandaloneDisplayMathHasItsOwnCopyEndpoint() {
        let groups = ReaderMathSelectionGroup.group([.displayMath("a\\frac{1}{2}")],
                                                    enableHTML: false, plugins: nil)
        XCTAssertEqual(groups.count, 1)
        guard case let .math(latex) = groups[0] else { return XCTFail("Expected standalone math") }
        XCTAssertEqual(latex, "a\\frac{1}{2}")
    }

    private func mathItems(_ source: String) -> [ReaderBlockRangeDocument.Item] {
        MathSyntax.sections(source).flatMap { section in
            switch section {
            case let .markdown(markdown):
                return Array(MarkdownSyntax.parse(markdown).children).map(ReaderBlockRangeDocument.Item.markup)
            case let .block(latex): return [.displayMath(latex)]
            }
        }
    }

}
