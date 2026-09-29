#if os(iOS)
import SwiftUI
import XCTest
@testable import SmoothMarkdown

@MainActor
final class MarkdownEditorParserPluginTests: XCTestCase {
    func testOptInCustomBlockRetainsExactSourceAndUTF16Range() throws {
        let registry = ParserPluginRegistry()
        try registry.register(CustomContainerPlugin())
        let source = "Intro 😀\r\n:::custom id=42\r\nbody 😀\r\n:::\r\nAfter"
        let controller = MarkdownEditorController(text: source, plugins: registry)
        XCTAssertTrue(registry.unregisterBlock("custom-container"))

        let document = controller.semanticDocument
        XCTAssertEqual(document.toMarkdown(), source)
        XCTAssertEqual(document.blocks.count, 3)
        guard case let .plugin(id, match) = document.blocks[1].kind else {
            return XCTFail("Expected custom plugin block")
        }
        XCTAssertEqual(id, "custom-container")
        XCTAssertEqual(match.attributes["info"], "id=42")
        XCTAssertEqual(match.content, "body 😀")
        XCTAssertEqual(match.source, ":::custom id=42\r\nbody 😀\r\n:::\r\n")
        XCTAssertEqual(document.blocks[1].plainText, "body 😀")
        let range = try XCTUnwrap(document.sourceRange(of: "block-1"))
        XCTAssertEqual(range.location, ("Intro 😀\r\n" as NSString).length)
        XCTAssertEqual((source as NSString).substring(with: range), match.source)

        let editor = SmoothMarkdownEditor(controller: controller,
            customBlockBuilder: { context in
                if case let .plugin(pluginID, _) = context.blockKind, pluginID == "custom-container" {
                    return AnyView(Button(context.plainText, action: context.edit))
                }
                return nil
            },
            customBlockEditorBuilder: { context in
                AnyView(Button("Finish", action: context.finishEditing))
            })
        _ = editor
    }

    func testPluginIsIsolatedFromDefaultMarkdownAndFencedCode() throws {
        let registry = ParserPluginRegistry()
        try registry.register(CustomContainerPlugin())
        let source = "```md\n:::custom\ninside fence\n:::\n```\n\n:::custom\noutside\n:::\n"
        let defaultDocument = MarkdownDocumentCodec().parse(source)
        XCTAssertFalse(defaultDocument.blocks.contains {
            if case .plugin = $0.kind { return true }
            return false
        })
        let document = MarkdownDocumentCodec(plugins: registry).parse(source)
        XCTAssertEqual(document.blocks.count, 2)
        XCTAssertEqual(document.toMarkdown(), source)
        guard case .fencedCode = document.blocks[0].kind,
              case .plugin = document.blocks[1].kind else {
            return XCTFail("Expected fence and separately parsed plugin block")
        }
        XCTAssertEqual(MarkdownDocumentCodec(plugins: registry).parse(":::other\nbody\n:::").blocks.count, 1)
    }

    func testFailedAndInvalidPluginsFallThrough() throws {
        let registry = ParserPluginRegistry()
        try registry.register(InvalidContainerPlugin())
        try registry.register(CustomContainerPlugin())
        let document = MarkdownDocumentCodec(plugins: registry).parse(":::custom\nbody\n:::")
        XCTAssertEqual(document.blocks.count, 1)
        guard case let .plugin(id, _) = document.blocks[0].kind else {
            return XCTFail("Expected fallback plugin")
        }
        XCTAssertEqual(id, "custom-container")
    }

    func testPluginStartsAfterTableWithoutBlankLine() throws {
        let registry = ParserPluginRegistry()
        try registry.register(CustomContainerPlugin())
        let source = "| A |\n| --- |\n| one |\n:::custom\nbody\n:::\n"
        let document = MarkdownDocumentCodec(plugins: registry).parse(source)
        XCTAssertEqual(document.toMarkdown(), source)
        XCTAssertEqual(document.blocks.count, 2)
        guard case .table = document.blocks[0].kind,
              case .plugin = document.blocks[1].kind else {
            return XCTFail("Expected table and separate plugin block")
        }
    }

    func testCustomReplacementKeepsNeighborsAndUndo() throws {
        let registry = ParserPluginRegistry()
        try registry.register(CustomContainerPlugin())
        let original = "Before\n:::custom id=42\nold\n:::\nAfter"
        let controller = MarkdownEditorController(text: original, plugins: registry)
        XCTAssertFalse(controller.replaceCustomBlockMarkdown(id: "block-1", expectedText: original,
                                                             with: ":::custom id=42\nnew\n:::\n# extra\n"))
        XCTAssertEqual(controller.text, original)
        XCTAssertTrue(controller.replaceCustomBlockMarkdown(id: "block-1", expectedText: original,
                                                            with: ":::custom id=42\nnew\n:::\n"))
        XCTAssertEqual(controller.text, "Before\n:::custom id=42\nnew\n:::\nAfter")
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, original)
    }
}

private struct CustomContainerPlugin: BlockParserPlugin {
    let id = "custom-container"
    let name = "Custom Container"
    let priority = 10

    func canParse(_ line: String, lines: [String], at index: Int) -> Bool {
        line == ":::custom" || line.hasPrefix(":::custom ")
    }

    func parse(_ lines: [String], at index: Int) -> BlockPluginMatch? {
        guard lines.indices.contains(index), index + 1 < lines.count,
              canParse(lines[index], lines: lines, at: index),
              let close = lines[(index + 1)...].firstIndex(of: ":::") else { return nil }
        let content = lines[(index + 1)..<close].joined(separator: "\n")
        let info = String(lines[index].dropFirst(":::custom".count)).trimmingCharacters(in: .whitespaces)
        return BlockPluginMatch(linesConsumed: close - index + 1,
                                source: lines[index...close].joined(separator: "\n"), content: content,
                                attributes: ["info": info])
    }
}

private struct InvalidContainerPlugin: BlockParserPlugin {
    let id = "invalid-container"
    let name = "Invalid Container"
    let priority = 100

    func canParse(_ line: String, lines: [String], at index: Int) -> Bool { line.hasPrefix(":::custom") }
    func parse(_ lines: [String], at index: Int) -> BlockPluginMatch? {
        BlockPluginMatch(linesConsumed: lines.count + 1, source: "", content: "")
    }
}
#endif
