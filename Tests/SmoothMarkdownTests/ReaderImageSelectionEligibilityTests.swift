import XCTest
@testable import SmoothMarkdown

final class ReaderImageSelectionEligibilityTests: XCTestCase {
    func testFlutterLinksImagesShapeAcceptsHeadingsAndTrailingRemoteImages() {
        let markdown = """
        # Links

        Check out [Flutter](https://flutter.dev).

        # Images

        ![Flutter Logo](https://flutter.dev/logo.png)

        ![Broken image](https://example.com/nonexistent.png)
        """
        let nodes = Array(MarkdownSyntax.parse(markdown).children)
        let document = ReaderBlockRangeDocument(nodes, enableHTML: false, plugins: nil)
        XCTAssertNotNil(document)
        let specs = document.flatMap {
            ReaderImageSelectionEligibility.imageSpecs(for: $0, enableHTML: false, plugins: nil)
        }
        XCTAssertEqual(specs?.map(\.alt), ["Flutter Logo", "Broken image"])
    }

    func testImageAtLeadingEdgeRemainsEligible() {
        let markdown = """
        ![Mark](https://example.com/mark.svg)

        After the image.
        """
        let nodes = Array(MarkdownSyntax.parse(markdown).children)
        let document = ReaderBlockRangeDocument(nodes, enableHTML: false, plugins: nil)
        let specs = document.flatMap {
            ReaderImageSelectionEligibility.imageSpecs(for: $0, enableHTML: false, plugins: nil)
        }
        XCTAssertEqual(specs?.first?.source, "https://example.com/mark.svg")
    }

    func testListAdjacentToImageKeepsExplicitBlockRange() {
        let markdown = """
        - A list item

        ![Image](https://example.com/image.png)

        After.
        """
        let nodes = Array(MarkdownSyntax.parse(markdown).children)
        let document = ReaderBlockRangeDocument(nodes, enableHTML: false, plugins: nil)
        XCTAssertNotNil(document)
        XCTAssertNil(document.flatMap {
            ReaderImageSelectionEligibility.imageSpecs(for: $0, enableHTML: false, plugins: nil)
        })
    }
}
