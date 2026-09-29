import XCTest
@testable import SmoothMarkdown

final class AIBlockPluginTests: XCTestCase {
    func testThinkingAliasesCollapseAndUnclosedBlock() {
        let plugin = ThinkingPlugin()
        for (open, close) in [("<thinking>", "</thinking>"), ("<think>", "</think>"),
                              ("<|thinking|>", "<|/thinking|>")] {
            let match = plugin.parse([open, "  first line", "second line  ", close, "After"], at: 0)
            XCTAssertEqual(match?.linesConsumed, 4)
            XCTAssertEqual(match?.content, "first line\nsecond line")
            XCTAssertEqual(match?.attributes["isCollapsed"], "true")
        }
        let partial = plugin.parse(["<thinking>", "reasoning"], at: 0)
        XCTAssertEqual(partial?.linesConsumed, 2)
        XCTAssertEqual(partial?.content, "reasoning")
    }

    func testArtifactAttributesMimeAliasesAndContent() {
        let plugin = ArtifactPlugin()
        let match = plugin.parse([
            "<artifact identifier=\"demo\" type='application/vnd.ant.code' lang='swift' title=\"Example\">",
            "print(1)", "", "print(2)", "</artifact>", "After",
        ], at: 0)!
        XCTAssertEqual(match.linesConsumed, 5)
        let block = ArtifactPlugin.block(match)
        XCTAssertEqual(block.identifier, "demo")
        XCTAssertEqual(block.type, .code)
        XCTAssertEqual(block.title, "Example")
        XCTAssertEqual(block.language, "swift")
        XCTAssertEqual(block.content, "print(1)\n\nprint(2)")

        let custom = plugin.parse(["<artifact id='x' type='chart'>", "data"], at: 0)!
        XCTAssertEqual(ArtifactPlugin.block(custom).customType, "chart")
        XCTAssertEqual(custom.linesConsumed, 2)
        let unnamed = plugin.parse(["<artifact type='text/markdown'>", "# Title", "</artifact>"], at: 0)!
        XCTAssertEqual(ArtifactPlugin.block(unnamed).identifier, "unnamed")
        XCTAssertEqual(ArtifactPlugin.block(unnamed).type, .document)
    }

    func testToolCallNameInputPendingAndMissingFields() {
        let plugin = ToolCallPlugin()
        let match = plugin.parse([
            "<tool_use>", "<tool_name>search</tool_name>", "<tool_id>call-1</tool_id>",
            "<input>", "  {\"query\":\"swift\"}", "</input>", "</tool_use>",
        ], at: 0)!
        XCTAssertEqual(match.linesConsumed, 7)
        let block = ToolCallPlugin.block(match)
        XCTAssertEqual(block.toolName, "search")
        XCTAssertEqual(block.toolId, "call-1")
        XCTAssertEqual(block.parameters, "{\"query\":\"swift\"}")
        XCTAssertEqual(block.status, .pending)
        XCTAssertNil(block.result)

        let partial = plugin.parse(["<tool_use>", "unknown"], at: 0)!
        XCTAssertEqual(ToolCallPlugin.block(partial).toolName, "unknown")
        XCTAssertNil(ToolCallPlugin.block(partial).parameters)
    }

    func testBuiltInsAreOptInAndFencesProtectSyntax() {
        let registry = ParserPluginRegistry.builtIns()
        XCTAssertEqual(registry.blockPlugins.map(\.id), ["tool_call", "thinking", "artifact", "admonition", "mermaid"])
        let source = "Intro\n<think>\nprivate\n</think>\nOutro"
        XCTAssertEqual(PluginBlockSyntax.sections(source, registry: nil).count, 1)
        let sections = PluginBlockSyntax.sections(source, registry: registry)
        XCTAssertEqual(sections.count, 3)
        if case let .plugin(plugin, match) = sections[1] {
            XCTAssertEqual(plugin.id, "thinking")
            XCTAssertEqual(match.content, "private")
        } else { XCTFail("Expected thinking plugin") }
        XCTAssertEqual(PluginBlockSyntax.sections("```xml\n<thinking>\nprivate\n</thinking>\n```", registry: registry).count, 1)
        XCTAssertEqual(PluginBlockSyntax.sections("~~~\n<artifact id='x'>\ndata\n</artifact>\n~~~", registry: registry).count, 1)
    }
}
