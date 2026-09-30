import Foundation
import XCTest
@testable import SmoothMarkdown

/// Runs against the pinned official CommonMark examples when COMMONMARK_SPEC_JSON is set.
/// Checks source ranges, block structure, and rendered HTML against official examples.
final class NativeMarkdownOfficialSpecTests: XCTestCase {
    func testOfficialFirstVisibleBlockKindAcrossExamples() throws {
        var count = 0
        for example in try examples() {
            let html = example["html"] as! String
            let expected: NativeMarkdownNode.Kind?
            if html.hasPrefix("<p>") { expected = .paragraph }
            else if html.hasPrefix("<h1>") { expected = .heading(1) }
            else if html.hasPrefix("<h2>") { expected = .heading(2) }
            else if html.hasPrefix("<h3>") { expected = .heading(3) }
            else if html.hasPrefix("<h4>") { expected = .heading(4) }
            else if html.hasPrefix("<h5>") { expected = .heading(5) }
            else if html.hasPrefix("<h6>") { expected = .heading(6) }
            else if html.hasPrefix("<ul>") { expected = .list(ordered: false) }
            else if html.hasPrefix("<ol>") { expected = .list(ordered: true) }
            else if html.hasPrefix("<blockquote>") { expected = .blockQuote }
            else if html.hasPrefix("<hr ") { expected = .thematicBreak }
            else { continue }
            count += 1
            let actual = NativeMarkdownASTParser(enableGFM: false).parse(example["markdown"] as! String).children.first(where: { if case .referenceDefinition = $0.kind { return false }; return true })?.kind
            XCTAssertEqual(actual, expected, "CommonMark example \(example["example"] as! Int)")
        }
        XCTAssertEqual(count, 554)
    }

    func testOfficialBlockKinds() throws {
        // CommonMark 0.31.2 examples across precedence, headings, code, quotes and lists.
        let expected: [Int: [NativeMarkdownNode.Kind]] = [
            43: [.thematicBreak, .thematicBreak, .thematicBreak],
            44: [.paragraph], 45: [.paragraph],
            62: [.heading(1), .heading(2), .heading(3), .heading(4), .heading(5), .heading(6)],
            63: [.paragraph], 64: [.paragraph, .paragraph],
            80: [.heading(1), .heading(2)],
            107: [.indentedCode], 119: [.fencedCode("")], 120: [.fencedCode("")],
            228: [.blockQuote], 231: [.indentedCode],
            301: [.list(ordered: false), .list(ordered: false)],
            302: [.list(ordered: true), .list(ordered: true)],
        ]
        for example in try examples() {
            guard let number = example["example"] as? Int, let kinds = expected[number],
                  let source = example["markdown"] as? String else { continue }
            XCTAssertEqual(NativeMarkdownASTParser(enableGFM: false).parse(source).children.map(\.kind), kinds,
                           "CommonMark example \(number)")
        }
    }

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
            let tree = NativeMarkdownASTParser(enableGFM: false).parse(source)
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
            let paragraph = try XCTUnwrap(NativeMarkdownASTParser(enableGFM: false).parse(source).children.first)
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
            let paragraph = try XCTUnwrap(NativeMarkdownASTParser(enableGFM: false).parse(source).children.first)
            XCTAssertEqual(paragraph.kind, .paragraph, "Example \(number)")
            let code = try XCTUnwrap(paragraph.children.first(where: { $0.kind == .inlineCode }))
            XCTAssertEqual(code.semanticText, expected, "Example \(number)")
        }
    }

    func testOfficialUnmatchedEmphasisRemainsLiteral() throws {
        let selected: Set<Int> = [351, 352, 358, 359, 363, 366, 367, 371,
                                  379, 380, 383, 384, 385, 391, 397, 398, 400, 401]
        for example in try examples() {
            guard let number = example["example"] as? Int, selected.contains(number) else { continue }
            let source = try XCTUnwrap(example["markdown"] as? String)
            let html = try XCTUnwrap(example["html"] as? String)
            XCTAssertTrue(html.hasPrefix("<p>") && html.hasSuffix("</p>\n"))
            let expected = NativeMarkdownTextDecoder.decode(String(html.dropFirst(3).dropLast(5)))
            let tree = NativeMarkdownASTParser(enableGFM: false).parse(source)
            XCTAssertEqual(tree.children.map(\.kind), [.paragraph], "Example \(number)")
            let actual = tree.children[0].children.map { node -> String in
                if let semanticText = node.semanticText { return semanticText }
                if node.kind == .softBreak { return "\n" }
                return ""
            }.joined()
            XCTAssertEqual(actual, expected, "Example \(number)")
        }
    }

    func testOfficialInlineLinkBoundaries() throws {
        let valid: [Int: (String, String?)] = [
            482: ("/uri", "title"), 483: ("/uri", nil), 484: ("./target.md", nil),
            485: ("", nil), 486: ("", nil), 487: ("", nil),
        ]
        let invalid: Set<Int> = [488, 490, 493, 497, 508]
        for example in try examples() {
            guard let number = example["example"] as? Int,
                  valid[number] != nil || invalid.contains(number) else { continue }
            let source = try XCTUnwrap(example["markdown"] as? String)
            let paragraph = try XCTUnwrap(NativeMarkdownASTParser(enableGFM: false).parse(source).children.first)
            XCTAssertEqual(paragraph.kind, .paragraph, "Example \(number)")
            let links = paragraph.children.filter { if case .link = $0.kind { return true }; return false }
            if let expected = valid[number] {
                let link = try XCTUnwrap(links.first, "Example \(number)")
                XCTAssertEqual(link.kind, .link(expected.0), "Example \(number)")
                XCTAssertEqual(link.title, expected.1, "Example \(number)")
            } else {
                XCTAssertTrue(links.isEmpty, "Example \(number)")
                let html = try XCTUnwrap(example["html"] as? String)
                let expected = NativeMarkdownTextDecoder.decode(String(html.dropFirst(3).dropLast(5)))
                let actual = paragraph.children.map { node -> String in
                    if let semanticText = node.semanticText { return semanticText }
                    if node.kind == .softBreak { return "\n" }
                    return ""
                }.joined()
                XCTAssertEqual(actual, expected, "Example \(number)")
            }
        }
    }

    func testOfficialNestedLinkLabelsAndLinkPrecedence() throws {
        let selected: Set<Int> = [512, 515, 517, 518, 520]
        for example in try examples() {
            guard let number = example["example"] as? Int, selected.contains(number) else { continue }
            let source = try XCTUnwrap(example["markdown"] as? String)
            let paragraph = try XCTUnwrap(NativeMarkdownASTParser(enableGFM: false).parse(source).children.first)
            let links = paragraph.children.filter { if case .link = $0.kind { return true }; return false }
            let images = paragraph.children.filter { if case .image = $0.kind { return true }; return false }
            switch number {
            case 512, 515, 517:
                XCTAssertEqual(links.map(\.kind), [.link("/uri")], "Example \(number)")
            case 518:
                XCTAssertEqual(links.map(\.kind), [.link("/uri")], "Example \(number)")
                XCTAssertEqual(links.first?.source, "[bar](/uri)")
            case 520:
                XCTAssertEqual(images.map(\.kind), [.image("uri3")], "Example \(number)")
            default: break
            }
        }
    }

    func testOfficialReferenceLinksKeepTitlesAndFirstDefinition() throws {
        let expected: [Int: (NativeMarkdownNode.Kind, String?)] = [
            539: (.link("/url"), "title"),
            540: (.link("/url"), nil),
            544: (.link("/url1"), nil),
            549: (.link("/uri"), nil),
            550: (.link("/uri"), nil),
            553: (.link("/url"), "title"),
            572: (.image("/url"), "title"),
            584: (.image("/url"), "title"),
        ]
        for example in try examples() {
            guard let number = example["example"] as? Int, let value = expected[number] else { continue }
            let source = try XCTUnwrap(example["markdown"] as? String)
            let paragraph = try XCTUnwrap(NativeMarkdownASTParser(enableGFM: false).parse(source).children.first(where: {
                $0.kind == .paragraph
            }))
            let node = try XCTUnwrap(paragraph.children.first(where: { $0.kind == value.0 }),
                                     "Example \(number)")
            XCTAssertEqual(node.title, value.1, "Example \(number)")
        }
    }

    func testOfficialEmphasisSemantics() throws {
        func escape(_ value: String) -> String {
            value.replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
                .replacingOccurrences(of: "\"", with: "&quot;")
        }
        func render(_ node: NativeMarkdownNode) -> String {
            let content = node.children.map(render).joined()
            switch node.kind {
            case .text, .inlineCode:
                let value = escape(node.semanticText ?? node.source)
                return node.kind == .inlineCode ? "<code>" + value + "</code>" : value
            case .paragraph: return "<p>" + content + "</p>\n"
            case .strong: return "<strong>" + content + "</strong>"
            case .emphasis: return "<em>" + content + "</em>"
            case .softBreak: return "\n"
            case .hardBreak: return "<br />\n"
            case .inlineHTML: return node.source
            case let .link(destination): return "<a href=\"" + escape(destination) + "\">" + content + "</a>"
            case .document: return content
            default: return "UNSUPPORTED(\(node.kind))"
            }
        }
        let selected = try examples().filter { ($0["section"] as? String) == "Emphasis and strong emphasis" }
        XCTAssertEqual(selected.count, 132)
        for example in selected {
            let number = try XCTUnwrap(example["example"] as? Int)
            let source = try XCTUnwrap(example["markdown"] as? String)
            let expected = try XCTUnwrap(example["html"] as? String)
            XCTAssertEqual(render(NativeMarkdownASTParser(enableGFM: false).parse(source)), expected, "Example \(number)")
        }
    }

    func testOfficialLinkAndImageSemantics() throws {
        let selected = try examples().filter { ["Links", "Images"].contains($0["section"] as? String ?? "") }
        XCTAssertEqual(selected.count, 112)
        for example in selected {
            let number = try XCTUnwrap(example["example"] as? Int)
            let source = try XCTUnwrap(example["markdown"] as? String)
            let expected = try XCTUnwrap(example["html"] as? String)
            XCTAssertEqual(NativeMarkdownHTMLTestRenderer.render(NativeMarkdownASTParser(enableGFM: false).parse(source)),
                           expected, "Example \(number)")
        }
    }

    func testOfficialAutolinkHTMLBreakAndCodeSpanSemantics() throws {
        let sections = ["Autolinks", "Raw HTML", "Hard line breaks", "Soft line breaks", "Code spans"]
        let selected = try examples().filter { sections.contains($0["section"] as? String ?? "") }
        XCTAssertEqual(selected.count, 78)
        for example in selected {
            let number = try XCTUnwrap(example["example"] as? Int)
            let source = try XCTUnwrap(example["markdown"] as? String)
            let expected = try XCTUnwrap(example["html"] as? String)
            XCTAssertEqual(NativeMarkdownHTMLTestRenderer.render(NativeMarkdownASTParser(enableGFM: false).parse(source)),
                           expected, "Example \(number)")
        }
    }

    func testOfficialCodeHTMLAndEscapingSemantics() throws {
        let sections = ["Backslash escapes", "Entity and numeric character references", "Fenced code blocks", "Indented code blocks", "HTML blocks"]
        let selected = try examples().filter { sections.contains($0["section"] as? String ?? "") }
        XCTAssertEqual(selected.count, 115)
        for example in selected {
            let number = try XCTUnwrap(example["example"] as? Int)
            let source = try XCTUnwrap(example["markdown"] as? String)
            let expected = try XCTUnwrap(example["html"] as? String)
            XCTAssertEqual(NativeMarkdownHTMLTestRenderer.render(NativeMarkdownASTParser(enableGFM: false).parse(source)),
                           expected, "Example \(number)")
        }
    }

    func testOfficialRemainingBlockSemantics() throws {
        let sections = ["Tabs", "Precedence", "Thematic breaks", "ATX headings", "Setext headings", "Link reference definitions", "Paragraphs", "Blank lines", "Inlines", "Textual content"]
        let selected = try examples().filter { sections.contains($0["section"] as? String ?? "") }
        XCTAssertEqual(selected.count, 116)
        for example in selected {
            let number = try XCTUnwrap(example["example"] as? Int)
            let source = try XCTUnwrap(example["markdown"] as? String)
            let expected = try XCTUnwrap(example["html"] as? String)
            XCTAssertEqual(NativeMarkdownHTMLTestRenderer.render(NativeMarkdownASTParser(enableGFM: false).parse(source)),
                           expected, "Example \(number)")
        }
    }
}
