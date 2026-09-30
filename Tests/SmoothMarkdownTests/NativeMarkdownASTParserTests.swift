import XCTest
@testable import SmoothMarkdown

final class NativeMarkdownASTParserTests: XCTestCase {
    func testSourcePreservingBlocksAndUTF16Ranges() {
        let source = "😀 intro\n\n## Bold **name**\n\n```swift\nlet x = 1\n```\n"
        let tree = NativeMarkdownASTParser().parse(source)
        XCTAssertEqual(tree.kind, .document)
        XCTAssertEqual(tree.source, source)
        XCTAssertEqual(tree.children.count, 3)
        XCTAssertEqual(tree.children.map(\.kind), [.paragraph, .heading(2), .fencedCode("swift")])
        for block in tree.children {
            XCTAssertEqual((source as NSString).substring(with: block.sourceRange), block.source)
        }
        let heading = tree.children[1]
        XCTAssertEqual(heading.children.map(\.kind), [.text, .strong])
        XCTAssertEqual(heading.children[1].children.map(\.kind), [.text])
        XCTAssertEqual((source as NSString).substring(with: heading.children[1].sourceRange), "**name**")
    }

    func testInlineMarkupKeepsEscapesAndNestedSource() {
        let source = "A [**bold** link](https://example.com), ![icon](icon.svg), `*raw*` and \\*literal*"
        let tree = NativeMarkdownASTParser().parse(source)
        let children = tree.children[0].children
        XCTAssertEqual(children.map(\.kind), [
            .text, .link("https://example.com"), .text, .image("icon.svg"),
            .text, .inlineCode, .text,
        ])
        XCTAssertEqual(children[1].children.map(\.kind), [.strong, .text])
        XCTAssertEqual(children[5].source, "`*raw*`")
        XCTAssertEqual(children.last?.source, " and \\*literal*")
    }

    func testListAndTableHaveOwnedStructuralNodes() {
        let source = "- [x] done\n- [ ] next\n\n| A | B |\n|---|---|\n| 1 | 2 |\n"
        let tree = NativeMarkdownASTParser().parse(source)
        XCTAssertEqual(tree.children.count, 2)
        XCTAssertEqual(tree.children[0].kind, .list(ordered: false))
        XCTAssertEqual(tree.children[0].children.map(\.kind), [.listItem(checked: true), .listItem(checked: false)])
        XCTAssertEqual(tree.children[1].kind, .table)
        XCTAssertEqual(tree.children[1].children.count, 2)
        XCTAssertEqual(tree.children[1].children[0].children.map(\.kind), [.tableCell, .tableCell])
        for row in tree.children[1].children {
            XCTAssertEqual((source as NSString).substring(with: row.sourceRange), row.source)
            for cell in row.children {
                XCTAssertEqual((source as NSString).substring(with: cell.sourceRange), cell.source)
            }
        }
    }

    func testFixtureNodesRetainExactSourceSlices() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "FlutterREADME", withExtension: "md"))
        let source = try String(contentsOf: url, encoding: .utf8)
        let tree = NativeMarkdownASTParser().parse(source)
        let text = source as NSString
        func check(_ node: NativeMarkdownNode) {
            XCTAssertGreaterThanOrEqual(node.sourceRange.location, 0)
            XCTAssertLessThanOrEqual(NSMaxRange(node.sourceRange), text.length)
            XCTAssertEqual(text.substring(with: node.sourceRange), node.source)
            node.children.forEach(check)
        }
        check(tree)
    }

    func testNativeExtensionNodes() {
        let source = "Text $x^2$ and[^note].\n\n[^note]: details\n\n$$\nx + y\n$$\n"
        let tree = NativeMarkdownASTParser().parse(source)
        XCTAssertEqual(tree.children[0].children.map(\.kind), [
            .text, .inlineMath, .text, .footnoteReference("note"), .text,
        ])
        XCTAssertEqual(tree.children[1].kind, .footnoteDefinition("note"))
        XCTAssertEqual(tree.children[2].kind, .blockMath)
    }

    func testReferenceLinksResolveForwardDefinitionsAndKeepSourceRanges() {
        let source = "😀 [one][  TARGET ] and ![icon][target] and [TARGET].\n\n[target]: https://example.com/icon.svg\n"
        let tree = NativeMarkdownASTParser().parse(source)
        let children = tree.children[0].children
        XCTAssertEqual(children.map(\.kind), [
            .text, .link("https://example.com/icon.svg"), .text,
            .image("https://example.com/icon.svg"), .text,
            .link("https://example.com/icon.svg"), .text,
        ])
        XCTAssertEqual(tree.children[1].kind,
                       .referenceDefinition("target", "https://example.com/icon.svg"))
        for child in children {
            XCTAssertEqual((source as NSString).substring(with: child.sourceRange), child.source)
        }
    }

    func testReferenceDefinitionInsideFenceDoesNotResolve() {
        let source = "[missing]\n\n```md\n[missing]: https://example.com\n```\n"
        let tree = NativeMarkdownASTParser().parse(source)
        XCTAssertEqual(tree.children[0].children.map(\.kind), [.text])
    }

    func testLineBreaksAutolinksAndInlineHTML() {
        let source = "a\nb  \nc\\\nd <https://example.com> <dev@example.com> <kbd>x</kbd>"
        let tree = NativeMarkdownASTParser().parse(source)
        let nodes = tree.children[0].children
        XCTAssertEqual(nodes.map(\.kind), [
            .text, .softBreak, .text, .hardBreak, .text, .hardBreak, .text,
            .link("https://example.com"), .text, .link("mailto:dev@example.com"),
            .text, .inlineHTML, .text, .inlineHTML,
        ])
        for node in nodes {
            XCTAssertEqual((source as NSString).substring(with: node.sourceRange), node.source)
        }
    }

    func testSetextHeadingsAndIndentedCode() {
        let source = "Title\n=====\n\nOther\n---\n\n    code()\n    more\n"
        let tree = NativeMarkdownASTParser().parse(source)
        XCTAssertEqual(tree.children.map(\.kind), [.heading(1), .heading(2), .indentedCode])
        XCTAssertEqual(tree.children[0].children.map(\.source), ["Title"])
        XCTAssertEqual(tree.children[1].children.map(\.source), ["Other"])
        for child in tree.children {
            XCTAssertEqual((source as NSString).substring(with: child.sourceRange), child.source)
        }
    }

    func testNestedListsRetainHierarchyAndExactSource() throws {
        let source = "- parent\n  - child\n    1. grandchild\n  - sibling\n- root\n"
        let tree = NativeMarkdownASTParser().parse(source)
        let list = tree.children[0]
        XCTAssertEqual(list.kind, .list(ordered: false))
        XCTAssertEqual(list.children.count, 2)
        let nested = try XCTUnwrap(list.children[0].children.last)
        XCTAssertEqual(nested.kind, .list(ordered: false))
        XCTAssertEqual(nested.children.count, 2)
        XCTAssertEqual(nested.children[0].children.last?.kind, .list(ordered: true))
        func check(_ node: NativeMarkdownNode) {
            XCTAssertEqual((source as NSString).substring(with: node.sourceRange), node.source)
            node.children.forEach(check)
        }
        check(tree)
    }

    func testATXClosingSequenceAndGFMInlineBoundaries() {
        let source = "# Heading ###\n\nA ~short~ and ~~long~~, not ~~~triple~~~ or foo_bar_baz. " +
            "www.example.com, https://example.com/path(test)."
        let tree = NativeMarkdownASTParser().parse(source)
        XCTAssertEqual(tree.children[0].kind, .heading(1))
        XCTAssertEqual(tree.children[0].children.map(\.source), ["Heading"])
        let inlines = tree.children[1].children
        XCTAssertEqual(inlines.filter { $0.kind == .strikethrough }.map(\.source),
                       ["~short~", "~~long~~"])
        XCTAssertTrue(inlines.contains { $0.kind == .link("http://www.example.com") })
        XCTAssertTrue(inlines.contains { $0.kind == .link("https://example.com/path(test)") })
        XCTAssertTrue(inlines.contains { $0.source.contains("foo_bar_baz") && $0.kind == .text })
        for node in inlines {
            XCTAssertEqual((source as NSString).substring(with: node.sourceRange), node.source)
        }
    }

    func testIncompleteBareLinksStayText() {
        let source = "www. http:// foo_bar_baz ~~~no~~~"
        let nodes = NativeMarkdownASTParser().parse(source).children[0].children
        XCTAssertEqual(nodes.map(\.kind), [.text])
        XCTAssertEqual(nodes[0].source, source)
    }
}
