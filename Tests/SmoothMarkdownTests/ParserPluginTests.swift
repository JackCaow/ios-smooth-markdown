import XCTest
@testable import SmoothMarkdown

final class ParserPluginTests: XCTestCase {
    func testRegistryOrderingDuplicatesAndLifecycle() throws {
        let registry = ParserPluginRegistry()
        try registry.register(EmojiPlugin())
        try registry.register(MentionPlugin())
        try registry.register(HashtagPlugin())
        try registry.register(AdmonitionPlugin())
        XCTAssertEqual(registry.inlinePlugins.map(\.id), ["mention", "hashtag", "emoji"])
        XCTAssertEqual(registry.blockPlugins.map(\.id), ["admonition"])
        XCTAssertEqual(registry.inlineTriggerCharacters, Set(["@", "#", ":"]))
        XCTAssertEqual(registry.getInlinePluginByTrigger("@")?.id, "mention")
        XCTAssertEqual(registry.findInlinePlugins("@john", at: "@john".startIndex).map(\.id), ["mention"])
        XCTAssertThrowsError(try registry.register(MentionPlugin())) { error in
            XCTAssertEqual(error as? ParserPluginRegistryError, .duplicateID("mention"))
        }
        let copy = registry.copy()
        XCTAssertTrue(registry.unregisterInline("mention"))
        XCTAssertFalse(registry.unregisterInline("missing"))
        XCTAssertEqual(copy.inlinePlugins.count, 3)
        registry.clear()
        XCTAssertTrue(registry.inlinePlugins.isEmpty)
        XCTAssertTrue(registry.blockPlugins.isEmpty)
    }

    func testMentionHashtagEmojiMatchesAndFallback() throws {
        let registry = ParserPluginRegistry.builtIns()
        let source = "Hey @john_doe-test :SMILE: check #flutter_dev and :unknown_emoji: @123"
        let paragraph = MarkdownSyntax.parse(source).child(at: 0)!
        let runs = InlineContent.runs(in: paragraph, enableHTML: false, plugins: registry)
        let matches = runs.compactMap { run -> (String, InlinePluginMatch)? in
            if case let .plugin(plugin, match) = run { return (plugin.id, match) }
            return nil
        }
        XCTAssertEqual(matches.map(\.0), ["mention", "emoji", "hashtag"])
        XCTAssertEqual(matches[0].1.attributes["username"], "john_doe-test")
        XCTAssertEqual(matches[1].1.attributes["shortcode"], "smile")
        XCTAssertEqual(matches[1].1.text, "😄")
        XCTAssertEqual(matches[2].1.attributes["tag"], "flutter_dev")
        let remainder = runs.compactMap { if case let .text(value, _, _, _) = $0 { return value }; return nil }.joined()
        XCTAssertTrue(remainder.contains(":unknown_emoji:"))
        XCTAssertTrue(remainder.contains("@123"))
        XCTAssertFalse(InlineContent.runs(in: paragraph, enableHTML: false).contains {
            if case .plugin = $0 { return true }; return false
        })
        let custom = EmojiPlugin(customEmojis: ["smile": "🎉", "custom": "🚀"])
        XCTAssertEqual(custom.parse(":SMILE:", at: ":SMILE:".startIndex)?.text, "🎉")
        XCTAssertEqual(custom.parse(":custom:", at: ":custom:".startIndex)?.text, "🚀")
    }

    func testPluginPriorityAndParseFailureFallsThrough() throws {
        let registry = ParserPluginRegistry()
        try registry.register(FailingAtPlugin())
        try registry.register(MentionPlugin())
        let text = "@john"
        let parts = PluginInlineSyntax.parts(in: text, registry: registry)
        XCTAssertEqual(parts.count, 1)
        if case let .plugin(plugin, match) = parts[0] {
            XCTAssertEqual(plugin.id, "mention")
            XCTAssertEqual(match.text, "@john")
        } else { XCTFail("Expected fallback plugin") }
    }

    func testAdmonitionAliasesCustomAndCodeFenceProtection() {
        let registry = ParserPluginRegistry.builtIns()
        let sections = PluginBlockSyntax.sections("Intro\n::: warning Important Notice\nPlease read carefully.\n:::\nOutro", registry: registry)
        XCTAssertEqual(sections.count, 3)
        if case let .plugin(plugin, match) = sections[1] {
            XCTAssertEqual(plugin.id, "admonition")
            XCTAssertEqual(match.attributes["type"], "warning")
            XCTAssertEqual(match.attributes["title"], "Important Notice")
            XCTAssertEqual(match.content, "Please read carefully.")
        } else { XCTFail("Expected admonition") }
        let alias = AdmonitionPlugin().parse(["::: info", "Line 1", "Line 2", ":::"], at: 0)
        XCTAssertEqual(alias?.attributes["type"], "note")
        XCTAssertEqual(alias?.content, "Line 1\nLine 2")
        let custom = AdmonitionPlugin().parse(["::: custom_type Custom Title", "Body"], at: 0)
        XCTAssertEqual(custom?.attributes["type"], "custom")
        XCTAssertEqual(custom?.attributes["customType"], "custom_type")
        XCTAssertEqual(custom?.linesConsumed, 2)
        XCTAssertEqual(PluginBlockSyntax.sections("```\n::: tip\ncode\n:::\n```", registry: registry).count, 1)
        XCTAssertEqual(PluginBlockSyntax.sections("::: tip\nBody\n:::", registry: nil).count, 1)
    }

    func testBlockPluginPriorityAndParseFailureFallback() throws {
        let registry = ParserPluginRegistry()
        try registry.register(FailingBlockPlugin())
        try registry.register(AdmonitionPlugin())
        let sections = PluginBlockSyntax.sections("::: note\nContent\n:::", registry: registry)
        XCTAssertEqual(sections.count, 1)
        if case let .plugin(plugin, match) = sections[0] {
            XCTAssertEqual(plugin.id, "admonition")
            XCTAssertEqual(match.content, "Content")
        } else { XCTFail("Expected fallback block plugin") }
    }
}

private struct FailingAtPlugin: InlineParserPlugin {
    let id = "fail"
    let name = "Failing test plugin"
    let priority = 99
    let triggerCharacter: Character = "@"
    func canParse(_ text: String, at index: String.Index) -> Bool { true }
    func parse(_ text: String, at index: String.Index) -> InlinePluginMatch? { nil }
}

private struct FailingBlockPlugin: BlockParserPlugin {
    let id = "failing-block"
    let name = "Failing block test plugin"
    let priority = 99
    func canParse(_ line: String, lines: [String], at index: Int) -> Bool { line.hasPrefix(":::") }
    func parse(_ lines: [String], at index: Int) -> BlockPluginMatch? { nil }
}
