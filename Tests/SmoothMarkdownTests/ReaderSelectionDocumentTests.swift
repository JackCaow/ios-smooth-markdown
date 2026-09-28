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

    func testImageAndCodeRemainSeparateInteractiveBlocks() {
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
        XCTAssertEqual(groups.count, 4)
        if case let .selectable(nodes) = groups[0] { XCTAssertEqual(nodes.count, 2) }
        else { XCTFail("Expected combined paragraphs") }
        for index in [1, 2, 3] {
            if case .individual = groups[index] { } else { XCTFail("Expected individual block at \(index)") }
        }
    }

    func testUnsafeLinkNeverBecomesActiveInSelectionDocument() {
        let source = "First [unsafe](javascript:alert(1)).\n\nSecond paragraph."
        let nodes = Array(MarkdownSyntax.parse(source).children)
        let document = ReaderSelectionDocument.compose(nodes, enableHTML: false, plugins: nil)!
        XCTAssertEqual(document.lines.count, 2)
        XCTAssertTrue(document.lines.flatMap(\.runs).allSatisfy { $0.style.link == nil })
    }
}
