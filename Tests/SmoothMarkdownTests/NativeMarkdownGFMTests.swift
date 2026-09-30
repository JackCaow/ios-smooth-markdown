import Foundation
import XCTest
@testable import SmoothMarkdown

final class NativeMarkdownGFMTests: XCTestCase {
    func testOfficialTaskListSemanticsAndSourceRanges() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "gfm-tasklist", withExtension: "json"))
        let examples = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: String]])
        XCTAssertEqual(examples.count, 2)
        for (index, example) in examples.enumerated() {
            let source = try XCTUnwrap(example["markdown"])
            let tree = NativeMarkdownASTParser().parse(source)
            XCTAssertEqual(NativeMarkdownHTMLTestRenderer.render(tree), example["html"],
                           "GFM task list example \(index + 1)")
            func check(_ node: NativeMarkdownNode) {
                XCTAssertEqual((source as NSString).substring(with: node.sourceRange), node.source)
                node.children.forEach(check)
            }
            check(tree)
        }
    }

    func testOfficialInlineExtensionSemantics() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "gfm-inline", withExtension: "json"))
        let examples = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: String]])
        XCTAssertEqual(examples.count, 13)
        for (index, example) in examples.enumerated() {
            let tree = NativeMarkdownASTParser().parse(try XCTUnwrap(example["markdown"]))
            XCTAssertEqual(NativeMarkdownHTMLTestRenderer.render(tree), example["html"], "GFM inline example \(index + 1)")
        }
    }

    func testOfficialDisallowedHTMLSemantics() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "gfm-tagfilter", withExtension: "json"))
        let examples = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: String]])
        XCTAssertEqual(examples.count, 1)
        for example in examples {
            let tree = NativeMarkdownASTParser().parse(try XCTUnwrap(example["markdown"]))
            XCTAssertEqual(NativeMarkdownHTMLTestRenderer.render(tree), example["html"])
        }
        XCTAssertEqual(NativeMarkdownHTMLTagFilter.filter("<TITLE>x</TITLE><titlex>ok</titlex><textarea/ >"),
                       "&lt;TITLE>x&lt;/TITLE><titlex>ok</titlex><textarea/ >")
    }

    // Official GFM examples, CC BY-SA 4.0. Source: github/cmark-gfm
    // test/spec.txt at 27d942c8b0a62d192f616e5bf3578f4b6a89e180.
    // Specification: https://github.github.com/gfm/#tables-extension-
    func testOfficialTableSemanticsAndSourceRanges() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "gfm-tables", withExtension: "json"))
        let examples = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: String]])
        XCTAssertEqual(examples.count, 8)
        for (index, example) in examples.enumerated() {
            let source = try XCTUnwrap(example["markdown"])
            let expected = try XCTUnwrap(example["html"])
            let tree = NativeMarkdownASTParser().parse(source)
            XCTAssertEqual(NativeMarkdownHTMLTestRenderer.render(tree), expected, "GFM table example \(index + 1)")
            func check(_ node: NativeMarkdownNode) {
                XCTAssertEqual((source as NSString).substring(with: node.sourceRange), node.source)
                node.children.forEach(check)
            }
            check(tree)
        }
    }
}
