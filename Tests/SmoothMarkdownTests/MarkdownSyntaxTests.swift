import Foundation
import XCTest
@testable import SmoothMarkdown

final class MarkdownSyntaxTests: XCTestCase {
    func testGfmTableAndTaskList() {
        let document = MarkdownSyntax.parse("""
        | Name | Value |
        | ---- | ----- |
        | one  | two   |

        - [x] done
        - [ ] todo
        """)

        XCTAssertTrue(document.child(at: 0) is Markdown.Table)
        guard let list = document.child(at: 1) as? UnorderedList,
              let checked = list.child(at: 0) as? Markdown.ListItem,
              let unchecked = list.child(at: 1) as? Markdown.ListItem else {
            XCTFail("Expected task list")
            return
        }
        XCTAssertEqual(checked.checkbox, .checked)
        XCTAssertEqual(unchecked.checkbox, .unchecked)
    }

    func testLinkAndImageSchemes() {
        XCTAssertTrue(MarkdownSyntax.isSafeLink(URL(string: "https://example.com")!))
        XCTAssertFalse(MarkdownSyntax.isSafeLink(URL(string: "javascript:alert(1)")!))
        XCTAssertFalse(MarkdownSyntax.isSafeImage(URL(string: "file:///etc/passwd")!))
        XCTAssertTrue(MarkdownSyntax.isSafeImage(URL(string: "https://example.com/a.png")!))
    }

    func testFootnoteReferenceRemainsLiteralTextForDedicatedParser() {
        let paragraph = MarkdownSyntax.parse("Text[^one] and[^2] end").child(at: 0)!
        XCTAssertEqual((paragraph.child(at: 0) as? Markdown.Text)?.string, "Text[^one] and[^2] end")
    }
}
