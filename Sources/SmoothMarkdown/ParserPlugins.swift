import Foundation
import SwiftUI

public struct InlinePluginMatch: Equatable {
    public let consumed: Int
    public let text: String
    public let attributes: [String: String]

    public init(consumed: Int, text: String, attributes: [String: String] = [:]) {
        self.consumed = consumed
        self.text = text
        self.attributes = attributes
    }
}

public struct BlockPluginMatch: Equatable {
    public let linesConsumed: Int
    public let source: String
    public let content: String
    public let attributes: [String: String]

    public init(linesConsumed: Int, source: String, content: String, attributes: [String: String] = [:]) {
        self.linesConsumed = linesConsumed
        self.source = source
        self.content = content
        self.attributes = attributes
    }
}

public protocol ParserPlugin {
    var id: String { get }
    var name: String { get }
    var priority: Int { get }
}

public extension ParserPlugin {
    var priority: Int { 0 }
}

public protocol InlineParserPlugin: ParserPlugin {
    var triggerCharacter: Character { get }
    func canParse(_ text: String, at index: String.Index) -> Bool
    func parse(_ text: String, at index: String.Index) -> InlinePluginMatch?
    func render(_ match: InlinePluginMatch) -> AnyView
}

public extension InlineParserPlugin {
    func render(_ match: InlinePluginMatch) -> AnyView { AnyView(SwiftUI.Text(match.text)) }
}

public protocol BlockParserPlugin: ParserPlugin {
    func canParse(_ line: String, lines: [String], at index: Int) -> Bool
    func parse(_ lines: [String], at index: Int) -> BlockPluginMatch?
    func render(_ match: BlockPluginMatch) -> AnyView
}

public extension BlockParserPlugin {
    func render(_ match: BlockPluginMatch) -> AnyView { AnyView(SwiftUI.Text(match.source)) }
}

public enum ParserPluginRegistryError: Error, Equatable {
    case duplicateID(String)
    case unsupportedType(String)
}

/// An opt-in, ordered parser and renderer extension point. Create one registry per reader configuration.
public final class ParserPluginRegistry {
    public private(set) var blockPlugins: [any BlockParserPlugin] = []
    public private(set) var inlinePlugins: [any InlineParserPlugin] = []

    public init() {}

    public static func builtIns() -> ParserPluginRegistry {
        let result = ParserPluginRegistry()
        try! result.register(MentionPlugin())
        try! result.register(HashtagPlugin())
        try! result.register(EmojiPlugin())
        try! result.register(AdmonitionPlugin())
        try! result.register(ToolCallPlugin())
        try! result.register(ThinkingPlugin())
        try! result.register(ArtifactPlugin())
        return result
    }

    public func register(_ plugin: any BlockParserPlugin) throws {
        guard !blockPlugins.contains(where: { $0.id == plugin.id }) else { throw ParserPluginRegistryError.duplicateID(plugin.id) }
        blockPlugins.append(plugin)
        blockPlugins.sort { $0.priority > $1.priority }
    }

    public func register(_ plugin: any InlineParserPlugin) throws {
        guard !inlinePlugins.contains(where: { $0.id == plugin.id }) else { throw ParserPluginRegistryError.duplicateID(plugin.id) }
        inlinePlugins.append(plugin)
        inlinePlugins.sort { $0.priority > $1.priority }
    }

    public func register(_ plugin: any ParserPlugin) throws {
        if let block = plugin as? any BlockParserPlugin { try register(block) }
        else if let inline = plugin as? any InlineParserPlugin { try register(inline) }
        else { throw ParserPluginRegistryError.unsupportedType(plugin.id) }
    }

    public func registerAll(_ plugins: [any ParserPlugin]) throws {
        for plugin in plugins { try register(plugin) }
    }

    @discardableResult public func unregisterBlock(_ id: String) -> Bool {
        guard let index = blockPlugins.firstIndex(where: { $0.id == id }) else { return false }
        blockPlugins.remove(at: index)
        return true
    }

    @discardableResult public func unregisterInline(_ id: String) -> Bool {
        guard let index = inlinePlugins.firstIndex(where: { $0.id == id }) else { return false }
        inlinePlugins.remove(at: index)
        return true
    }

    public func clear() {
        blockPlugins.removeAll()
        inlinePlugins.removeAll()
    }

    public func copy() -> ParserPluginRegistry {
        let result = ParserPluginRegistry()
        result.blockPlugins = blockPlugins
        result.inlinePlugins = inlinePlugins
        return result
    }

    public var inlineTriggerCharacters: Set<Character> { Set(inlinePlugins.map(\.triggerCharacter)) }
    public func isInlineTrigger(_ character: Character) -> Bool { inlineTriggerCharacters.contains(character) }
    public func getBlockPlugin(_ id: String) -> (any BlockParserPlugin)? { blockPlugins.first { $0.id == id } }
    public func getInlinePlugin(_ id: String) -> (any InlineParserPlugin)? { inlinePlugins.first { $0.id == id } }
    public func getInlinePluginByTrigger(_ character: Character) -> (any InlineParserPlugin)? {
        inlinePlugins.first { $0.triggerCharacter == character }
    }
    public func findBlockPlugins(_ line: String, lines: [String], at index: Int) -> [any BlockParserPlugin] {
        blockPlugins.filter { $0.canParse(line, lines: lines, at: index) }
    }
    public func findInlinePlugins(_ text: String, at index: String.Index) -> [any InlineParserPlugin] {
        guard index < text.endIndex else { return [] }
        return inlinePlugins.filter { $0.triggerCharacter == text[index] && $0.canParse(text, at: index) }
    }
}

enum PluginInlineSyntax {
    enum Part {
        case text(String)
        case plugin(any InlineParserPlugin, InlinePluginMatch)
    }

    static func parts(in text: String, registry: ParserPluginRegistry?) -> [Part] {
        guard let registry, !registry.inlinePlugins.isEmpty else { return [.text(text)] }
        var result: [Part] = []
        var ordinary = ""
        var index = text.startIndex
        while index < text.endIndex {
            var accepted: (any InlineParserPlugin, InlinePluginMatch)?
            for plugin in registry.findInlinePlugins(text, at: index) {
                guard let match = plugin.parse(text, at: index), match.consumed > 0,
                      text.distance(from: index, to: text.endIndex) >= match.consumed else { continue }
                accepted = (plugin, match)
                break
            }
            if let (plugin, match) = accepted {
                if !ordinary.isEmpty { result.append(.text(ordinary)); ordinary = "" }
                result.append(.plugin(plugin, match))
                index = text.index(index, offsetBy: match.consumed)
            } else {
                ordinary.append(text[index])
                index = text.index(after: index)
            }
        }
        if !ordinary.isEmpty { result.append(.text(ordinary)) }
        return result
    }
}

enum PluginBlockSyntax {
    enum Section {
        case markdown(String)
        case plugin(any BlockParserPlugin, BlockPluginMatch)
    }

    static func sections(_ source: String, registry: ParserPluginRegistry?) -> [Section] {
        guard let registry, !registry.blockPlugins.isEmpty else { return [.markdown(source)] }
        let lines = source.components(separatedBy: "\n")
        var result: [Section] = []
        var ordinary: [String] = []
        var fence: Character?
        var fenceLength = 0
        var index = 0
        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let marker = fence {
                ordinary.append(line)
                if let run = fenceRun(trimmed), run.0 == marker, run.1 >= fenceLength,
                   trimmed.dropFirst(run.1).trimmingCharacters(in: .whitespaces).isEmpty { fence = nil }
                index += 1
                continue
            }
            if let run = fenceRun(trimmed), run.1 >= 3 {
                fence = run.0
                fenceLength = run.1
                ordinary.append(line)
                index += 1
                continue
            }
            var accepted: (any BlockParserPlugin, BlockPluginMatch)?
            for plugin in registry.findBlockPlugins(line, lines: lines, at: index) {
                guard let match = plugin.parse(lines, at: index), match.linesConsumed > 0,
                      match.linesConsumed <= lines.count - index else { continue }
                accepted = (plugin, match)
                break
            }
            if let (plugin, match) = accepted {
                if !ordinary.isEmpty { result.append(.markdown(ordinary.joined(separator: "\n"))); ordinary.removeAll() }
                result.append(.plugin(plugin, match))
                index += match.linesConsumed
            } else {
                ordinary.append(line)
                index += 1
            }
        }
        if !ordinary.isEmpty { result.append(.markdown(ordinary.joined(separator: "\n"))) }
        return result
    }

    private static func fenceRun(_ line: String) -> (Character, Int)? {
        guard let first = line.first, first == "`" || first == "~" else { return nil }
        let count = line.prefix(while: { $0 == first }).count
        return count >= 3 ? (first, count) : nil
    }
}
