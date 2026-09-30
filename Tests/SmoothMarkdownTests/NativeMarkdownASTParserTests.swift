import XCTest
@testable import SmoothMarkdown

final class NativeMarkdownASTParserTests: XCTestCase {
    func testQuotedLazyContinuationAndListTightness() {
        let source = "> > 😀 foo\nbar\n\n- tight\n- item\n"
        let tree = NativeMarkdownASTParser().parse(source)
        XCTAssertEqual(tree.children.map(\.kind), [
            .blockQuote, .list(ordered: false),
        ])
        XCTAssertEqual(tree.children[0].children[0].kind, .blockQuote)
        XCTAssertEqual(tree.children[0].children[0].children[0].kind, .paragraph)
        XCTAssertEqual(tree.children[1].isTight, true)
        XCTAssertEqual(tree.children[1].children[0].children.map(\.kind), [.text])
        let loose = NativeMarkdownASTParser().parse("- loose\n\n  continuation\n").children[0]
        XCTAssertEqual(loose.isTight, false)
        XCTAssertEqual(loose.children[0].children.map(\.kind), [.paragraph, .paragraph])
        let text = source as NSString
        func check(_ node: NativeMarkdownNode) {
            XCTAssertEqual(text.substring(with: node.sourceRange), node.source)
            node.children.forEach(check)
        }
        check(tree)
    }

    func testCommonMarkBlockPrecedenceExamples() {
        // CommonMark 0.31.2: setext headings, thematic breaks, and fenced code blocks.
        let cases: [(String, [NativeMarkdownNode.Kind])] = [
            ("Foo\n---\n", [.heading(2)]),
            ("***\n", [.thematicBreak]),
            ("- - -\n", [.thematicBreak]),
            ("``` ruby\nputs 1\n```\n", [.fencedCode("ruby")]),
            ("    code\n", [.indentedCode]),
            ("# heading ###\n", [.heading(1)]),
        ]
        for (source, expected) in cases {
            let tree = NativeMarkdownASTParser().parse(source)
            XCTAssertEqual(tree.children.map(\.kind), expected, source)
        }
    }

    func testGFMTablesAndTaskItemsUseSourceRanges() {
        // GFM 0.29-gfm: table and task list extensions.
        let source = "😀 | B\n---|---\nx | y\n\n- [x] done\n- [ ] later\n"
        let tree = NativeMarkdownASTParser().parse(source)
        XCTAssertEqual(tree.children.map(\.kind), [.table, .list(ordered: false)])
        XCTAssertEqual(tree.children[0].children.count, 2)
        XCTAssertEqual(tree.children[1].children.map(\.kind),
                       [.listItem(checked: true), .listItem(checked: false)])
        let text = source as NSString
        func check(_ node: NativeMarkdownNode) {
            XCTAssertEqual(text.substring(with: node.sourceRange), node.source)
            node.children.forEach(check)
        }
        check(tree)
    }

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

    func testBacktickRunsMustMatchExactly() {
        let source = "`foo``bar``"
        let nodes = NativeMarkdownASTParser().parse(source).children[0].children
        XCTAssertEqual(nodes.map(\.kind), [.text, .inlineCode])
        XCTAssertEqual(nodes.map(\.source), ["`foo", "``bar``"])
        XCTAssertEqual(nodes[1].semanticText, "bar")
    }

    func testEmphasisRequiresCommonMarkFlanking() {
        let source = "a * foo bar* and a*\"foo\"* and foo_bar_baz and _foo_bar"
        let nodes = NativeMarkdownASTParser().parse(source).children[0].children
        XCTAssertEqual(nodes.map(\.kind), [.text])
        XCTAssertEqual(nodes[0].source, source)
        let valid = NativeMarkdownASTParser().parse("*italic* **bold** _also_")
            .children[0].children
        XCTAssertEqual(valid.map(\.kind), [.emphasis, .text, .strong, .text, .emphasis])
    }

    func testInlineLinkDestinationAndTitleGrammar() {
        let source = #"[ok](foo(and(bar)) "title") [space](<foo bar> 'label') [escaped](foo\)bar)"#
        let links = NativeMarkdownASTParser().parse(source).children[0].children
            .filter { if case .link = $0.kind { return true }; return false }
        XCTAssertEqual(links.map(\.kind), [.link("foo(and(bar))"), .link("foo bar"), .link("foo)bar")])
        XCTAssertEqual(links.map(\.title), ["title", "label", nil])

        for invalid in ["[link](/my uri)", "[link](foo\nbar)",
                        #"[link](<foo\>)"#, "[link](foo(and(bar))",
                        #"[link](/url "title "and" title")"#] {
            let nodes = NativeMarkdownASTParser().parse(invalid).children[0].children
            XCTAssertFalse(nodes.contains { if case .link = $0.kind { return true }; return false },
                           invalid)
        }
    }

    func testCRLFLineBreakKeepsUTF16SourceAndLinkSpacing() {
        let source = "a  \r\nb [link](url\r\n\"title\")"
        let tree = NativeMarkdownASTParser().parse(source)
        let nodes = tree.children[0].children
        XCTAssertTrue(nodes.contains { $0.kind == .hardBreak && $0.source == "  \r\n" })
        XCTAssertTrue(nodes.contains { $0.kind == .link("url") && $0.title == "title" })
        for node in nodes {
            XCTAssertEqual((source as NSString).substring(with: node.sourceRange), node.source)
        }
    }
}
