import XCTest
@testable import SmoothMarkdown

final class ReaderSelectionDocumentTests: XCTestCase {
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
        guard case let .imageBridge(nodes) = groups[0],
              let bridge = ReaderImageRangeDocument(nodes, enableHTML: false, plugins: nil) else {
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
        guard case let .imageBridge(nodes) = groups[0],
              let bridge = ReaderImageRangeDocument(nodes, enableHTML: false, plugins: nil) else {
            return XCTFail("Expected text-image-text bridge")
        }
        XCTAssertEqual(bridge.segments.map(\.isImage), [false, true, false])
        XCTAssertEqual(bridge.copiedText(in: 0...2, enableHTML: false, plugins: nil),
                       "Before bold.\nAfter link.")
        XCTAssertEqual(bridge.copiedText(in: 0...1, enableHTML: false, plugins: nil), "Before bold.")
        XCTAssertNil(bridge.copiedText(in: 1...1, enableHTML: false, plugins: nil))
        XCTAssertNil(bridge.copiedText(in: 0...3, enableHTML: false, plugins: nil))
    }

    func testUnsafeImageSourceDoesNotBecomeSelectionBridge() {
        let source = "Before\n\n![bad](javascript:alert(1))\n\nAfter"
        let groups = ReaderSelectionGroup.group(Array(MarkdownSyntax.parse(source).children),
                                                 enableHTML: false, plugins: nil)
        XCTAssertFalse(groups.contains {
            if case .imageBridge = $0 { return true }
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
}
