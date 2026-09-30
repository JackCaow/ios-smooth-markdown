import Foundation
import XCTest
@testable import SmoothMarkdown

final class NativeMarkdownMarkupTests: XCTestCase {
    func testUTF8ColumnsAndPersistentChildReplacement() throws {
        let source = "😀 **é**\n"
        let document = MarkdownSyntax.parse(source)
        let paragraph = try XCTUnwrap(document.child(at: 0) as? Paragraph)
        let strong = try XCTUnwrap(paragraph.child(at: 1) as? Strong)
        XCTAssertEqual(strong.range?.lowerBound, SourceLocation(line: 1, column: 6))
        XCTAssertEqual(strong.range?.upperBound, SourceLocation(line: 1, column: 12))
        let changed = paragraph.withUncheckedChildren([Markdown.Text("replacement")])
        XCTAssertTrue(changed is Paragraph)
        XCTAssertEqual((paragraph.child(at: 0) as? Markdown.Text)?.string, "😀 ")
        XCTAssertEqual((changed.child(at: 0) as? Markdown.Text)?.string, "replacement")
    }

    func testTableHeadAndTightListParagraphShape() throws {
        let table = try XCTUnwrap(MarkdownSyntax.parse("a|b\n-|-\nc|d\n").child(at: 0) as? Markdown.Table)
        XCTAssertEqual(table.head.children.count, 2)
        XCTAssertTrue(table.head.child(at: 0) is Markdown.Table.Cell)
        XCTAssertEqual(table.body.children.count, 1)

        let list = try XCTUnwrap(MarkdownSyntax.parse("0. zero\n   - nested\n\n    suffix\n").child(at: 0) as? OrderedList)
        XCTAssertEqual(list.startIndex, 0)
        let item = try XCTUnwrap(list.child(at: 0) as? Markdown.ListItem)
        XCTAssertTrue(item.child(at: 0) is Paragraph)
        XCTAssertTrue(item.child(at: 1) is UnorderedList)
        XCTAssertTrue(item.child(at: 2) is Paragraph)
    }
}
