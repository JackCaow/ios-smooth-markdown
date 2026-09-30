import Foundation
import XCTest
@testable import SmoothMarkdown

/// Runs against the pinned official CommonMark examples when COMMONMARK_SPEC_JSON is set.
/// This checks source preservation, not rendered HTML equivalence.
final class NativeMarkdownOfficialSpecTests: XCTestCase {
    private func examples() throws -> [[String: Any]] {
        guard let path = ProcessInfo.processInfo.environment["COMMONMARK_SPEC_JSON"] else {
            throw XCTSkip("Set COMMONMARK_SPEC_JSON to the CommonMark 0.31.2 spec.json path")
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let examples = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        XCTAssertEqual(examples.count, 652)
        return examples
    }

    func testOfficialExamplesPreserveEveryNodeRange() throws {
        for example in try examples() {
            let source = try XCTUnwrap(example["markdown"] as? String)
            let number = try XCTUnwrap(example["example"] as? Int)
            let tree = NativeMarkdownASTParser().parse(source)
            let text = source as NSString
            func check(_ node: NativeMarkdownNode) {
                XCTAssertGreaterThanOrEqual(node.sourceRange.location, 0, "Example \(number)")
                XCTAssertLessThanOrEqual(NSMaxRange(node.sourceRange), text.length, "Example \(number)")
                if NSMaxRange(node.sourceRange) <= text.length {
                    XCTAssertEqual(text.substring(with: node.sourceRange), node.source,
                                   "Example \(number)")
                }
                node.children.forEach(check)
            }
            check(tree)
        }
    }

    func testOfficialEntityParagraphSemantics() throws {
        let selected: Set<Int> = [25, 26, 27, 28, 29, 30, 39, 40]
        for example in try examples() {
            guard let number = example["example"] as? Int, selected.contains(number) else { continue }
            let source = try XCTUnwrap(example["markdown"] as? String)
            let html = try XCTUnwrap(example["html"] as? String)
            XCTAssertTrue(html.hasPrefix("<p>") && html.hasSuffix("</p>\n"))
            let expectedHTMLText = String(html.dropFirst(3).dropLast(5))
            let expected = NativeMarkdownTextDecoder.decode(expectedHTMLText)
            let paragraph = try XCTUnwrap(NativeMarkdownASTParser().parse(source).children.first)
            XCTAssertEqual(paragraph.kind, .paragraph, "Example \(number)")
            let actual = paragraph.children.map { node -> String in
                if let semanticText = node.semanticText { return semanticText }
                if node.kind == .softBreak { return "\n" }
                return ""
            }.joined()
            XCTAssertEqual(actual, expected, "Example \(number)")
        }
    }

    func testOfficialSingleCodeSpanSemantics() throws {
        let selected: Set<Int> = [328, 329, 330, 331, 332, 333, 335, 336, 337, 339, 340]
        for example in try examples() {
            guard let number = example["example"] as? Int, selected.contains(number) else { continue }
            let source = try XCTUnwrap(example["markdown"] as? String)
            let html = try XCTUnwrap(example["html"] as? String)
            XCTAssertTrue(html.hasPrefix("<p><code>") && html.hasSuffix("</code></p>\n"))
            let expectedHTMLText = String(html.dropFirst(9).dropLast(12))
            let expected = NativeMarkdownTextDecoder.decode(expectedHTMLText)
            let paragraph = try XCTUnwrap(NativeMarkdownASTParser().parse(source).children.first)
            XCTAssertEqual(paragraph.kind, .paragraph, "Example \(number)")
            let code = try XCTUnwrap(paragraph.children.first(where: { $0.kind == .inlineCode }))
            XCTAssertEqual(code.semanticText, expected, "Example \(number)")
        }
    }
}
