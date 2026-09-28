import Markdown
import XCTest
@testable import SmoothMarkdown

final class DetailsSyntaxTests: XCTestCase {
    func testCollapsedAndOpenBlocksKeepSummaryAndBodyInOrder() {
        let sections = DetailsSyntax.sections("""
        before

        <details>
        <summary>Click **here**</summary>
        Hidden body
        </details>

        <details open>
        <summary>Already open</summary>
        Visible body
        </details>

        after
        """)
        let blocks = sections.compactMap { if case let .details(block) = $0 { return block }; return nil }
        XCTAssertEqual(blocks, [
            .init(summary: "Click **here**", content: "Hidden body", isOpen: false),
            .init(summary: "Already open", content: "Visible body", isOpen: true)
        ])
        XCTAssertEqual(blocks.count, 2)
        XCTAssertTrue(sections.first == .markdown("before\n"))
        XCTAssertTrue(sections.last == .markdown("\nafter"))
        let summary = MarkdownSyntax.parse(blocks[0].summary).child(at: 0)!
        XCTAssertTrue(Array(summary.children).contains { $0 is Strong })
    }

    func testMultiblockBodyUsesMarkdownParser() {
        let block = onlyBlock("""
        <details>
        <summary>Examples</summary>

        - First
        - Second

        ```swift
        print("Hello")
        ```
        </details>
        """)
        let children = Array(MarkdownSyntax.parse(block.content).children)
        XCTAssertTrue(children.contains { $0 is UnorderedList })
        XCTAssertTrue(children.contains { $0 is CodeBlock })
    }

    func testEmptyBodyAndMultilineSummary() {
        let empty = onlyBlock("<details>\n<summary>Empty</summary>\n</details>")
        XCTAssertEqual(empty.content, "")
        let multiline = onlyBlock("<details>\n<summary>First\ncontinued\n</summary>\nbody\n</details>")
        XCTAssertEqual(multiline.summary, "First continued")
        XCTAssertEqual(multiline.content, "body")
    }

    func testDetailsAreRecognizedWithoutHTMLAndFencedOrUnknownFormsStayLiteral() {
        let sections = DetailsSyntax.sections("""
        ```html
        <details>
        <summary>In code</summary>
        </details>
        ```
        <details class="x">
        <summary>Unsupported opener</summary>
        </details>
        """)
        XCTAssertFalse(sections.contains { if case .details = $0 { return true }; return false })
        XCTAssertEqual(DetailsSyntax.sections("<details>\n<summary>Default</summary>\nbody\n</details>").count, 1)
    }

    private func onlyBlock(_ source: String, file: StaticString = #filePath, line: UInt = #line) -> DetailsSyntax.Block {
        guard case let .details(block)? = DetailsSyntax.sections(source).first else {
            XCTFail("Expected details block", file: file, line: line)
            return .init(summary: "", content: "", isOpen: false)
        }
        return block
    }
}
