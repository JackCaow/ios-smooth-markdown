import Foundation
import XCTest
@testable import SmoothMarkdown

/// Compares the complete container/block hierarchy with the official CommonMark HTML.
final class NativeMarkdownOfficialBlockStructureTests: XCTestCase {
    private struct Shape: Equatable, CustomStringConvertible {
        let name: String
        let children: [Shape]
        var description: String {
            children.isEmpty ? name : "\(name)(\(children.map(\.description).joined(separator: ",")))"
        }
    }

    private func nativeShapes(_ nodes: [NativeMarkdownNode]) -> [Shape] {
        nodes.compactMap { node in
            let name: String
            switch node.kind {
            case .paragraph: name = "p"
            case .heading(let level): name = "h\(level)"
            case .fencedCode, .indentedCode: name = "pre"
            case .thematicBreak: name = "hr"
            case .blockQuote: name = "blockquote"
            case .list(let ordered): name = ordered ? "ol" : "ul"
            case .listItem: name = "li"
            case .htmlBlock, .raw: return nil
            default: return nil
            }
            return Shape(name: name, children: nativeShapes(node.children))
        }
    }

    private func htmlShapes(_ html: String) throws -> [Shape] {
        let pattern = #"</?(?:blockquote|ul|ol|li|p|h[1-6]|pre|hr)(?:\s[^>]*)?>"#
        let expression = try NSRegularExpression(pattern: pattern)
        let source = html as NSString
        let tags = expression.matches(in: html, range: NSRange(location: 0, length: source.length))
            .map { source.substring(with: $0.range) }
        var position = 0
        func parse(until closing: String? = nil) -> [Shape] {
            var nodes: [Shape] = []
            while position < tags.count {
                let tag = tags[position]
                position += 1
                let close = tag.hasPrefix("</")
                let name = tag.dropFirst(close ? 2 : 1).prefix { $0.isLetter || $0.isNumber }
                if close {
                    if String(name) == closing { break }
                    continue
                }
                let children = name == "hr" ? [] : parse(until: String(name))
                nodes.append(Shape(name: String(name), children: children))
            }
            return nodes
        }
        return parse()
    }

    func testOfficialQuoteAndListBlockHierarchy() throws {
        guard let path = ProcessInfo.processInfo.environment["COMMONMARK_SPEC_JSON"] else {
            throw XCTSkip("Set COMMONMARK_SPEC_JSON to CommonMark 0.31.2 spec.json")
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let examples = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        let selected = examples.filter {
            ["Block quotes", "List items", "Lists"].contains($0["section"] as? String ?? "")
        }
        XCTAssertEqual(selected.count, 99)
        for example in selected {
            let number = try XCTUnwrap(example["example"] as? Int)
            let markdown = try XCTUnwrap(example["markdown"] as? String)
            let html = try XCTUnwrap(example["html"] as? String)
            XCTAssertEqual(nativeShapes(NativeMarkdownASTParser().parse(markdown).children),
                           try htmlShapes(html), "CommonMark example \(number)")
        }
    }
}
