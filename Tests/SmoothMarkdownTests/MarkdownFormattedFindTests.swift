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
}
