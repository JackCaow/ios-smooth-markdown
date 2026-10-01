import Foundation
#if canImport(SmoothMarkdownCore)
@_spi(ReaderInternals) import SmoothMarkdownCore
#endif
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
public final class ParserPluginRegistry: ObservableObject {
    /// Advances after an effective mutation. UI-bound registries must be mutated on the main thread.
    @Published public private(set) var revision: UInt64 = 0
    private func changed() { revision &+= 1 }
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
        try! result.register(MermaidPlugin())
        return result
    }

    public func register(_ plugin: any BlockParserPlugin) throws {
        guard !blockPlugins.contains(where: { $0.id == plugin.id }) else { throw ParserPluginRegistryError.duplicateID(plugin.id) }
        blockPlugins.append(plugin)
        blockPlugins.sort { $0.priority > $1.priority }
        changed()
    }

    public func register(_ plugin: any InlineParserPlugin) throws {
        guard !inlinePlugins.contains(where: { $0.id == plugin.id }) else { throw ParserPluginRegistryError.duplicateID(plugin.id) }
        inlinePlugins.append(plugin)
        inlinePlugins.sort { $0.priority > $1.priority }
        changed()
    }

    public func register(_ plugin: any ParserPlugin) throws {
        if let block = plugin as? any BlockParserPlugin { try register(block) }
        else if let inline = plugin as? any InlineParserPlugin { try register(inline) }
        else { throw ParserPluginRegistryError.unsupportedType(plugin.id) }
    }

    /// Atomically installs a batch. A duplicate or unsupported plugin leaves this registry unchanged.
    public func registerAll(_ plugins: [any ParserPlugin]) throws {
        guard !plugins.isEmpty else { return }
        let candidate = copy()
        for plugin in plugins { try candidate.register(plugin) }
        blockPlugins = candidate.blockPlugins
        inlinePlugins = candidate.inlinePlugins
        changed()
    }

    @discardableResult public func unregisterBlock(_ id: String) -> Bool {
        guard let index = blockPlugins.firstIndex(where: { $0.id == id }) else { return false }
        blockPlugins.remove(at: index)
        changed()
        return true
    }

    @discardableResult public func unregisterInline(_ id: String) -> Bool {
        guard let index = inlinePlugins.firstIndex(where: { $0.id == id }) else { return false }
        inlinePlugins.remove(at: index)
        changed()
        return true
    }

    public func clear() {
        guard !blockPlugins.isEmpty || !inlinePlugins.isEmpty else { return }
        changed()
        blockPlugins.removeAll()
        inlinePlugins.removeAll()
    }

    public func copy() -> ParserPluginRegistry {
        let result = ParserPluginRegistry()
        result.blockPlugins = blockPlugins
        result.inlinePlugins = inlinePlugins
        result.revision = revision
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
        case parsed(Document)
        case plugin(any BlockParserPlugin, BlockPluginMatch)
    }

    static func sections(_ source: String, registry: ParserPluginRegistry?, enableHTML: Bool = false, useCache: Bool = true) -> [Section] {
        let document = useCache ? MarkdownParseCache.shared.parseShared(source, plugins: registry, enableHTML: enableHTML)
            : PluginSharedSyntax.document(source, registry: registry, enableHTML: enableHTML)
        if let document {
            var sections: [Section] = []; var ordinary: [Markup] = []
            func flush() {
                if !ordinary.isEmpty { sections.append(.parsed(Document(ordinary))); ordinary = [] }
            }
            for node in document.children {
                if let custom = node as? SharedBlockPluginMarkup {
                    flush(); sections.append(.plugin(custom.plugin, custom.match))
                } else { ordinary.append(node) }
            }
            flush(); return sections
        }
        guard !NativeMarkdownExtensionProjection.isAvailable else {
            // A rejected or over-limit FFI request must remain visible. Preserve
            // raw spelling rather than silently dropping the document.
            let paragraph = Paragraph([Markdown.Text(source)])
            paragraph.sourcePluginsResolved = true
            return [.parsed(Document([paragraph], source: source))]
        }
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
                if let run = fenceRun(trimmed), run.1 >= 3 {
                    fence = run.0
                    fenceLength = run.1
                }
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

/// A single shared scan owns grammar and reference resolution. Plugin objects and
/// arbitrary payloads stay native; only match spans and opaque IDs cross the ABI.
enum PluginSharedSyntax {
    enum Payload {
        case block(any BlockParserPlugin, BlockPluginMatch)
        case inline(any InlineParserPlugin, InlinePluginMatch)
    }
    struct Result {
        let tree: NativeMarkdownNode
        let custom: [NSRange: UInt32]
        let payloads: [UInt32: Payload]
        func payload(for node: NativeMarkdownNode) -> Payload? {
            guard node.kind == .raw else { return nil }
            return custom[node.sourceRange].flatMap { payloads[$0] }
        }
        func blockMatch(_ match: BlockPluginMatch, node: NativeMarkdownNode) -> BlockPluginMatch {
            .init(linesConsumed: match.linesConsumed, source: node.source, content: match.content, attributes: match.attributes)
        }
        func resolve(_ node: NativeMarkdownNode) -> Markup? {
            switch payload(for: node) {
            case let .block(plugin, match): return SharedBlockPluginMarkup(plugin: plugin, match: blockMatch(match, node: node), source: node.source)
            case let .inline(plugin, match): return SharedInlinePluginMarkup(plugin: plugin, match: match, source: node.source)
            case nil: return nil
            }
        }
    }
    static func document(_ source: String, registry: ParserPluginRegistry?, enableHTML: Bool) -> Document? {
        guard let parsed = parse(source, registry: registry) else { return nil }
        let adapter = NativeMarkdownMarkupAdapter(source: source, resolveCustom: parsed.resolve,
            projectFootnote: { content in inlineContent(content, registry: registry, references: parsed.tree, enableHTML: enableHTML) })
        let document = Document(adapter.convert(parsed.tree).children, source: source)
        document.sourcePluginsResolved = true
        return enableHTML ? HTMLCodeLiteralSyntax.restore(document, source: source) : document
    }
    private static func inlineContent(_ source: String, registry: ParserPluginRegistry?, references: NativeMarkdownNode, enableHTML: Bool) -> Markup? {
        guard let result = parse(source, registry: registry, inlineReferences: references) else { return nil }
        let adapter = NativeMarkdownMarkupAdapter(source: source, resolveCustom: result.resolve)
        let paragraph = Paragraph(adapter.convert(result.tree).children, source: source)
        paragraph.sourcePluginsResolved = true
        let document = Document([paragraph], source: source)
        return (enableHTML ? HTMLCodeLiteralSyntax.restore(document, source: source) : document).children.first
    }
    private struct Candidate: Hashable {
        let absolute: Int; let index: Int; let remaining: Int; let spelling: String; let block: Bool
        func hash(into hasher: inout Hasher) {
            // Positions distribute candidates without hashing the entire paragraph
            // at every trigger. Synthesized equality still checks exact context.
            hasher.combine(absolute); hasher.combine(index)
            hasher.combine(remaining); hasher.combine(block)
        }
    }
    static func parse(_ source: String, registry: ParserPluginRegistry?, includeInline: Bool = true, inlineReferences: NativeMarkdownNode? = nil) -> Result? {
        let registry = registry?.copy() ?? ParserPluginRegistry()
        var next: UInt32 = 0
        var payloads: [UInt32: Payload] = [:]
        var matches: [Candidate: NativeMarkdownHookMatch] = [:]
        func identifier(_ payload: Payload) -> UInt32? {
            guard next < UInt32.max else { return nil }
            next += 1; payloads[next] = payload; return next
        }
        let inline: ((String, Int, Int) -> NativeMarkdownHookMatch?)? = includeInline && !registry.inlinePlugins.isEmpty ? { text, offset, absolute in
            guard offset >= 0, offset < text.utf16.count else { return nil }
            let index = String.Index(utf16Offset: offset, in: text)
            guard index.samePosition(in: text) != nil else { return nil }
            let candidates = registry.findInlinePlugins(text, at: index)
            guard !candidates.isEmpty else { return nil }
            let key = Candidate(absolute: absolute, index: offset, remaining: text.utf16.count - offset, spelling: text, block: false)
            if let match = matches[key] { return match }
            for plugin in candidates {
                guard let match = plugin.parse(text, at: index), match.consumed > 0,
                      let end = text.index(index, offsetBy: match.consumed, limitedBy: text.endIndex),
                      let id = identifier(.inline(plugin, match)) else { continue }
                let consumed = text[index..<end].utf16.count
                let result = NativeMarkdownHookMatch(consumed: consumed, id: id); matches[key] = result; return result
            }
            return nil
        } : nil
        let block: (([String], Int, Int) -> NativeMarkdownHookMatch?)? = registry.blockPlugins.isEmpty ? nil : { lines, index, absolute in
            guard lines.indices.contains(index) else { return nil }
            let candidates = registry.findBlockPlugins(lines[index], lines: lines, at: index)
            guard !candidates.isEmpty else { return nil }
            let key = Candidate(absolute: absolute, index: index, remaining: lines.count - index, spelling: lines[index], block: true)
            if let match = matches[key] { return match }
            for plugin in candidates {
                guard let match = plugin.parse(lines, at: index), match.linesConsumed > 0,
                      match.linesConsumed <= lines.count - index, let id = identifier(.block(plugin, match)) else { continue }
                let result = NativeMarkdownHookMatch(consumed: match.linesConsumed, id: id); matches[key] = result; return result
            }
            return nil
        }
        let parsed: NativeMarkdownHookedDocument?
        if let inlineReferences {
            parsed = NativeMarkdownExtensionProjection.parseInlineWithHooks(source, references: inlineReferences, inline: inline)
        } else { parsed = NativeMarkdownExtensionProjection.parseWithHooks(source, inline: inline, block: block) }
        guard let result = parsed else { return nil }
        return Result(tree: result.tree, custom: Dictionary(result.customNodes.map { ($0.range, $0.id) }, uniquingKeysWith: { first, _ in first }), payloads: payloads)
    }
}

final class SharedInlinePluginMarkup: Markup {
    let plugin: any InlineParserPlugin
    let match: InlinePluginMatch
    init(plugin: any InlineParserPlugin, match: InlinePluginMatch, source: String) {
        self.plugin = plugin; self.match = match; super.init(source: source)
    }
}
final class SharedBlockPluginMarkup: Markup {
    let plugin: any BlockParserPlugin
    let match: BlockPluginMatch
    init(plugin: any BlockParserPlugin, match: BlockPluginMatch, source: String) {
        self.plugin = plugin; self.match = match; super.init(source: source)
    }
}
final class SharedBlockMathMarkup: Markup {
    let latex: String
    init(latex: String, source: String) { self.latex = latex; super.init(source: source) }
}
final class SharedFootnoteMarkup: Markup {
    let definition: FootnoteSyntax.Definition
    init(definition: FootnoteSyntax.Definition, children: [Markup], source: String) {
        self.definition = definition; super.init(children, source: source)
    }
}
