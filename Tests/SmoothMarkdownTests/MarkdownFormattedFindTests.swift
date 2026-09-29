import XCTest
@testable import SmoothMarkdown

final class MarkdownFormattedFindTests: XCTestCase {
    func testVisibleProseSkipsLinkDestinationAndFormattingMarkers() {
        let source = "# **Target** [site](https://target.example)\n\nVisible target"
        let document = MarkdownDocumentCodec().parse(source)
        let matches = MarkdownFormattedFind.matches(in: document, query: "target")
        XCTAssertEqual(matches, [
            .init(blockID: "block-0", field: .prose, range: NSRange(location: 0, length: 6)),
            .init(blockID: "block-1", field: .prose, range: NSRange(location: 8, length: 6)),
        ])
        XCTAssertTrue(MarkdownFormattedFind.matches(in: document, query: "https").isEmpty)
        XCTAssertTrue(MarkdownFormattedFind.matches(in: document, query: "**").isEmpty)
    }

    func testListAndQuoteRowsUseDisplayedFieldCoordinates() {
        let source = "- Alpha\n- Beta target\n\n> Quote target\n\n```swift\ntarget\n```"
        let matches = MarkdownFormattedFind.matches(in: MarkdownDocumentCodec().parse(source), query: "target")
        XCTAssertEqual(matches, [
            .init(blockID: "block-0", field: .listItem(1), range: NSRange(location: 5, length: 6)),
            .init(blockID: "block-1", field: .quoteLine(0), range: NSRange(location: 6, length: 6)),
        ])
    }

    func testFindIsCaseInsensitiveNonOverlappingAndBounded() {
        let source = Array(repeating: "alpha", count: 503).joined(separator: " ")
        let matches = MarkdownFormattedFind.matches(in: MarkdownDocumentCodec().parse(source), query: "ALPHA")
        XCTAssertEqual(matches.count, 500)
        XCTAssertEqual(matches[0].range.location, 0)
        XCTAssertEqual(matches[1].range.location, 6)
        XCTAssertTrue(MarkdownFormattedFind.matches(in: MarkdownDocumentCodec().parse("aaaa"), query: "aa").map(\.range.location) == [0, 2])
    }

    func testListContinuationsFollowDisplayedOrderWithoutChangingSource() {
        let source = "- Parent\n  target continuation\n  - Child\n\n  target trailing\n- target next"
        let document = MarkdownDocumentCodec().parse(source)
        let matches = MarkdownFormattedFind.matches(in: document, query: "target")
        XCTAssertEqual(matches, [
            .init(blockID: "block-0", field: .listContinuation(item: 0, line: 0),
                  range: NSRange(location: 0, length: 6)),
            .init(blockID: "block-0", field: .listTrailing(item: 0, line: 0),
                  range: NSRange(location: 0, length: 6)),
            .init(blockID: "block-0", field: .listItem(2), range: NSRange(location: 0, length: 6)),
        ])
        XCTAssertEqual(document.toMarkdown(), source)
    }

    func testTableMatchesUseDisplayedCellCoordinatesAndIgnoreAlignmentRow() {
        let source = "| target head | Pipe \\| target |\n| :--- | ---: |\n| body target | target |"
        let document = MarkdownDocumentCodec().parse(source)
        XCTAssertEqual(MarkdownFormattedFind.matches(in: document, query: "target"), [
            .init(blockID: "block-0", field: .tableCell(row: 0, column: 0),
                  range: NSRange(location: 0, length: 6)),
            .init(blockID: "block-0", field: .tableCell(row: 0, column: 1),
                  range: NSRange(location: 7, length: 6)),
            .init(blockID: "block-0", field: .tableCell(row: 1, column: 0),
                  range: NSRange(location: 5, length: 6)),
            .init(blockID: "block-0", field: .tableCell(row: 1, column: 1),
                  range: NSRange(location: 0, length: 6)),
        ])
        XCTAssertTrue(MarkdownFormattedFind.matches(in: document, query: ":---").isEmpty)
        XCTAssertEqual(document.toMarkdown(), source)
    }

    func testDisplayedRawTextExcludesTrimmedTriviaAndFrontmatter() {
        let source = "---\ntitle: Hidden target\n---\n\n$$\ntarget raw\n$$\n"
        let document = MarkdownDocumentCodec().parse(source)
        XCTAssertEqual(MarkdownFormattedFind.matches(in: document, query: "target"), [
            .init(blockID: "block-1", field: .rawText, range: NSRange(location: 3, length: 6)),
        ])
        XCTAssertEqual(document.toMarkdown(), source)
    }

    func testHostRenderedBlockDoesNotClaimUnverifiedVisibleText() {
        let document = MarkdownDocumentCodec().parse("Custom target\n\nOrdinary target")
        let matches = MarkdownFormattedFind.matches(in: document, query: "target",
                                                    isCustomBlockRendered: { $0.id == "block-0" })
        XCTAssertEqual(matches, [
            .init(blockID: "block-1", field: .prose, range: NSRange(location: 9, length: 6)),
        ])
    }

    func testNavigationFixtureHasOneHitPerVisibleSurface() {
        let source = "- Parent\n  target continuation\n- target next\n\n| target header | Other |\n| --- | --- |\n| target body | x |\n\n$$\ntarget raw\n$$"
        let fields = MarkdownFormattedFind.matches(in: MarkdownDocumentCodec().parse(source), query: "target")
            .map(\.field)
        XCTAssertEqual(fields, [
            .listContinuation(item: 0, line: 0), .listItem(1),
            .tableCell(row: 0, column: 0), .tableCell(row: 1, column: 0), .rawText,
        ])
    }
}
