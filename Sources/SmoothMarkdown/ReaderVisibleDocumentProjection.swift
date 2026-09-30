import Foundation

/// Visible text and block anchors for the continuous TextKit reader host.
/// A projection alone does not make legacy SwiftUI sections globally selectable.
struct ReaderVisibleDocumentProjection {
    static let attachment = "\u{FFFC}"

    enum Kind: Equatable {
        case text, heading, image, code, table, displayMath
        case detailsSummary, footnote, plugin(String), rule, opaque
    }

    struct Atom {
        enum Kind: Equatable {
            case text, image(SafeHTML.ImageSpec), formula(String)
            case code(String, String?), table(String)
            case plugin(String, BlockPluginMatch)
            case opaque
        }
        let kind: Kind
        let text: String
        /// An attachment may copy a semantic value such as LaTeX.
        let copyText: String

        static func text(_ value: String) -> Self { .init(kind: .text, text: value, copyText: value) }
        static func image(_ spec: SafeHTML.ImageSpec) -> Self {
            .init(kind: .image(spec), text: ReaderVisibleDocumentProjection.attachment, copyText: "")
        }
        static func formula(_ latex: String) -> Self {
            .init(kind: .formula(latex), text: ReaderVisibleDocumentProjection.attachment, copyText: latex)
        }
        static func code(_ source: String, language: String?) -> Self {
            .init(kind: .code(source, language), text: ReaderVisibleDocumentProjection.attachment,
                  copyText: source)
        }
        static func table(_ source: String, copy: String) -> Self {
            .init(kind: .table(source), text: ReaderVisibleDocumentProjection.attachment,
                  copyText: copy)
        }
        static func plugin(_ id: String, match: BlockPluginMatch, copy: String) -> Self {
            .init(kind: .plugin(id, match), text: ReaderVisibleDocumentProjection.attachment,
                  copyText: copy)
        }
        static let attachment = Self(kind: .opaque, text: ReaderVisibleDocumentProjection.attachment, copyText: "")
    }

    struct Segment {
        let id: String
        let kind: Kind
        let range: NSRange
        let atoms: [Atom]

        var text: String { atoms.map(\.text).joined() }

        fileprivate func copiedText(in localRange: NSRange) -> String? {
            guard localRange.location >= 0, localRange.length >= 0,
                  NSMaxRange(localRange) <= range.length else { return nil }
            var copied = ""
            var cursor = 0
            for atom in atoms {
                let atomRange = NSRange(location: cursor, length: atom.text.utf16.count)
                let overlap = NSIntersectionRange(atomRange, localRange)
                if overlap.length > 0, !atom.copyText.isEmpty {
                    if atom.text != atom.copyText {
                        guard overlap == atomRange else { return nil }
                        copied += atom.copyText
                    } else {
                        let atomSelection = NSRange(location: overlap.location - cursor,
                                                    length: overlap.length)
                        guard ReaderVisibleDocumentProjection.validUTF16Range(atomSelection, in: atom.text),
                              let slice = Range(atomSelection, in: atom.text),
                              NSRange(slice, in: atom.text) == atomSelection
                        else { return nil }
                        copied += atom.text[slice]
                    }
                }
                cursor = NSMaxRange(atomRange)
            }
            return copied
        }
    }

    let segments: [Segment]
    let text: String

    /// `expansion` is a snapshot of the reader's disclosure state. A caller
    /// must rebuild after a details/thinking/tool card changes state.
    init(markdown: String, enableHTML: Bool = false, plugins: ParserPluginRegistry? = nil,
         builderRegistry: BuilderRegistry? = nil, expansion: [String: Bool] = [:],
         hostBuiltInPlugins: Bool = false, hostBuiltInArtifacts: Bool = false) {
        var builder = Builder(enableHTML: enableHTML, plugins: plugins,
                              builderRegistry: builderRegistry, expansion: expansion,
                              hostBuiltInPlugins: hostBuiltInPlugins,
                              hostBuiltInArtifacts: hostBuiltInArtifacts)
        builder.appendDetailsSections(markdown)
        segments = builder.segments
        text = segments.map(\.text).joined(separator: "\n")
    }

    /// Copies selected UTF-16 text without attachment glyphs, hidden content,
    /// Markdown delimiters, or extra separators around non-text blocks.
    func copiedText(in range: NSRange) -> String? {
        guard range.location != NSNotFound, range.location >= 0, range.length >= 0,
              NSMaxRange(range) <= text.utf16.count,
              Self.validUTF16Range(range, in: text),
              let selected = Range(range, in: text), NSRange(selected, in: text) == range else { return nil }
        var parts: [String] = []
        for segment in segments {
            let overlap = NSIntersectionRange(segment.range, range)
            guard overlap.length > 0 else { continue }
            guard let part = segment.copiedText(in: NSRange(location: overlap.location - segment.range.location,
                                                            length: overlap.length)) else { return nil }
            if !part.isEmpty { parts.append(part) }
        }
        return parts.reduce(into: "") { result, part in
            if !result.isEmpty && !result.hasSuffix("\n") && !part.hasPrefix("\n") { result += "\n" }
            result += part
        }
    }

    private static func validUTF16Range(_ range: NSRange, in text: String) -> Bool {
        let units = text as NSString
        guard range.location >= 0, range.length >= 0, NSMaxRange(range) <= units.length else { return false }
        func boundary(_ index: Int) -> Bool {
            guard index > 0 && index < units.length else { return true }
            let previous = units.character(at: index - 1)
            let next = units.character(at: index)
            return !(0xD800...0xDBFF).contains(previous) || !(0xDC00...0xDFFF).contains(next)
        }
        return boundary(range.location) && boundary(NSMaxRange(range))
    }

    private struct Builder {
        let enableHTML: Bool
        let plugins: ParserPluginRegistry?
        let builderRegistry: BuilderRegistry?
        let expansion: [String: Bool]
        let hostBuiltInPlugins: Bool
        let hostBuiltInArtifacts: Bool
        var segments: [Segment] = []
        private var occurrences: [String: Int] = [:]
        private var length = 0
        private var scope = "root"

        init(enableHTML: Bool, plugins: ParserPluginRegistry?, builderRegistry: BuilderRegistry?,
             expansion: [String: Bool], hostBuiltInPlugins: Bool,
             hostBuiltInArtifacts: Bool) {
            self.enableHTML = enableHTML
            self.plugins = plugins
            self.builderRegistry = builderRegistry
            self.expansion = expansion
            self.hostBuiltInPlugins = hostBuiltInPlugins
            self.hostBuiltInArtifacts = hostBuiltInArtifacts
        }

        mutating func appendDetailsSections(_ source: String) {
            for section in DetailsSyntax.sections(source) {
                switch section {
                case let .markdown(markdown): appendPluginSections(markdown)
                case let .details(details):
                    let identity = "details:" + details.summary + "\n" + details.content
                    if builderRegistry?.findBuilder(.details(summary: details.summary,
                                                             content: details.content,
                                                             isOpen: details.isOpen)) != nil {
                        append(.opaque, [.attachment], identity: identity)
                        continue
                    }
                    let disclosureID = nextID(kind: "details", identity: identity)
                    let summaryNode = MarkdownSyntax.parse(details.summary, enableHTML: enableHTML).child(at: 0)
                    append(.detailsSummary, summaryNode.map(inlineAtoms) ?? [.text("Details")], id: disclosureID)
                    if expansion[disclosureID] ?? details.isOpen {
                        let previousScope = scope
                        scope = disclosureID
                        appendPluginSections(details.content)
                        scope = previousScope
                    }
                }
            }
        }

        private mutating func appendPluginSections(_ source: String) {
            for section in PluginBlockSyntax.sections(source, registry: plugins) {
                switch section {
                case let .markdown(markdown): appendFootnoteSections(markdown)
                case let .plugin(plugin, match): appendPlugin(plugin, match)
                }
            }
        }

        private mutating func appendFootnoteSections(_ source: String) {
            for section in FootnoteSyntax.sections(source) {
                switch section {
                case let .markdown(markdown): appendMathSections(markdown)
                case let .definition(definition):
                    if builderRegistry?.findBuilder(.footnoteDefinition(label: definition.label,
                                                                        content: definition.content)) != nil {
                        append(.opaque, [.attachment], identity: definition.label + ":" + definition.content)
                        continue
                    }
                    let content = MarkdownSyntax.parse(definition.content, enableHTML: enableHTML)
                    let atoms = [Atom.text("[\(definition.label)]: ")] +
                        (content.child(at: 0).map(inlineAtoms) ?? [])
                    append(.footnote, atoms, identity: definition.label + ":" + definition.content)
                }
            }
        }

        private mutating func appendMathSections(_ source: String) {
            for section in MathSyntax.sections(source) {
                switch section {
                case let .markdown(markdown):
                    for node in MarkdownSyntax.parse(markdown, enableHTML: enableHTML).children {
                        appendMarkup(node)
                    }
                case let .block(latex):
                    let extensionNode = MarkdownExtensionNode.blockMath(latex)
                    if builderRegistry?.findBuilder(extensionNode) != nil {
                        append(.opaque, [.attachment], identity: extensionNode.source)
                    } else { append(.displayMath, [.formula(latex)], identity: latex) }
                }
            }
        }

        private mutating func appendMarkup(_ node: Markup) {
            if builderRegistry?.findBuilder(node) != nil {
                append(.opaque, [.attachment], identity: node.format())
            } else if let heading = node as? Heading {
                let atoms = inlineAtoms(heading)
                append(.heading, atoms, identity: identity(for: atoms))
            } else if let paragraph = node as? Paragraph {
                let atoms = inlineAtoms(paragraph)
                let standaloneImage: Bool = if atoms.count == 1, case .image = atoms[0].kind { true } else { false }
                append(standaloneImage ? .image : .text, atoms, identity: identity(for: atoms))
            } else if let code = node as? CodeBlock {
                append(.code, [.code(code.code, language: code.language)], identity: code.format())
            } else if let table = node as? Markdown.Table {
                if let copy = ReaderBlockRangeDocument.tableText(table, enableHTML: enableHTML, plugins: plugins) {
                    append(.table, [.table(table.format(), copy: copy)], identity: table.format())
                } else { append(.opaque, [.attachment], identity: table.format()) }
            } else if node is ThematicBreak {
                append(.rule, [.attachment], identity: node.format())
            } else if let html = node as? HTMLBlock {
                appendHTML(html.rawHTML)
            } else if let document = ReaderSelectionDocument.compose([node], enableHTML: enableHTML, plugins: plugins) {
                append(.text, [.text(document.copiedText)], identity: node.format())
            } else if let atoms = fallbackAtoms(node) {
                append(.text, atoms, identity: identity(for: atoms))
            } else {
                append(.opaque, [.attachment], identity: node.format())
            }
        }

        /// Handles the list/quote cases that the old native prose renderer
        /// rejects when an inline image, formula, or plugin is present.
        private func fallbackAtoms(_ node: Markup) -> [Atom]? {
            if node is Paragraph || node is Heading { return inlineAtoms(node) }
            if let code = node as? CodeBlock { return [.text(code.code)] }
            if node is ThematicBreak { return [.attachment] }
            if let ordered = node as? OrderedList {
                return listAtoms(ordered, start: Int(ordered.startIndex))
            }
            if let unordered = node as? UnorderedList { return listAtoms(unordered, start: nil) }
            if node is BlockQuote || node is ListItem {
                var result: [Atom] = []
                for child in node.children {
                    guard let part = fallbackAtoms(child) else { return nil }
                    if !result.isEmpty && !result.last!.text.hasSuffix("\n") { result.append(.text("\n")) }
                    result += part
                }
                return result
            }
            return nil
        }

        private func listAtoms(_ list: Markup, start: Int?) -> [Atom]? {
            var result: [Atom] = []
            for (index, child) in list.children.enumerated() {
                guard let item = child as? ListItem,
                      let content = fallbackAtoms(item) else { return nil }
                if !result.isEmpty && !result.last!.text.hasSuffix("\n") { result.append(.text("\n")) }
                let marker: String
                if let checkbox = item.checkbox { marker = checkbox == .checked ? "☑ " : "☐ " }
                else if let start { marker = "\(start + index). " }
                else { marker = "• " }
                result.append(.text(marker))
                result += content
            }
            return result
        }

        private mutating func appendHTML(_ source: String) {
            if enableHTML, let spec = SafeHTML.imageTag(source) {
                append(.image, [.image(spec)], identity: source)
            } else if enableHTML, let alt = SafeHTML.imageAlt(source) {
                append(.text, [.text(alt)], identity: source)
            } else if enableHTML, let block = SafeHTML.parseBlock(source) {
                switch block {
                case .rule: append(.rule, [.attachment], identity: source)
                case let .container(_, content, _, trailing):
                    appendMathSections(content)
                    if !trailing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        appendMathSections(trailing)
                    }
                }
            } else { append(.text, [.text(source)], identity: source) }
        }

        private func inlineAtoms(_ node: Markup) -> [Atom] {
            var atoms: [Atom] = []
            for run in InlineContent.runs(in: node, enableHTML: enableHTML, plugins: plugins,
                                          hasCustomBuilder: { builderRegistry?.findBuilder($0) != nil }) {
                switch run {
                case let .text(value, _, _, _): atoms.append(.text(value))
                case let .image(spec): atoms.append(.image(spec))
                case .custom: atoms.append(.attachment)
                case let .math(latex):
                    atoms.append(builderRegistry?.findBuilder(.inlineMath(latex)) == nil
                                 ? .formula(latex) : .attachment)
                case let .footnote(label):
                    atoms.append(builderRegistry?.findBuilder(.footnoteReference(label)) == nil
                                 ? .text("[\(label)]") : .attachment)
                case let .plugin(plugin, match):
                    let node = MarkdownPluginNode(plugin: plugin, match: match)
                    if builderRegistry?.findBuilder(node) != nil { atoms.append(.attachment) }
                    else if plugin is MentionPlugin || plugin is HashtagPlugin || plugin is EmojiPlugin {
                        atoms.append(.text(match.text))
                    } else { atoms.append(.attachment) }
                }
            }
            return atoms.isEmpty ? [.text("")] : atoms
        }

        private mutating func appendPlugin(_ plugin: any BlockParserPlugin, _ match: BlockPluginMatch) {
            let node = MarkdownPluginNode(plugin: plugin, match: match)
            if builderRegistry?.findBuilder(node) != nil {
                append(.opaque, [.attachment], identity: match.source)
                return
            }
            let kind = Kind.plugin(plugin.id)
            if hostBuiltInPlugins,
               plugin is AdmonitionPlugin || plugin is MermaidPlugin ||
               (hostBuiltInArtifacts && plugin is ArtifactPlugin) {
                let copy: String
                if plugin is AdmonitionPlugin {
                    let type = match.attributes["type"] ?? "custom"
                    let title = match.attributes["title"].flatMap { $0.isEmpty ? nil : $0 } ?? type.capitalized
                    copy = match.content.isEmpty ? title : title + "\n" + match.content
                } else if plugin is ArtifactPlugin {
                    let block = ArtifactPlugin.block(match)
                    let label: String = switch block.type {
                    case .code: block.language?.uppercased() ?? "CODE"
                    case .document: "DOCUMENT"
                    case .html: "HTML"
                    case .svg: "SVG"
                    case .component: "COMPONENT"
                    case .mermaid: "DIAGRAM"
                    case .custom: block.customType?.uppercased() ?? "ARTIFACT"
                    }
                    copy = ([block.title, label, block.content].compactMap { $0 }).joined(separator: "\n")
                } else {
                    copy = MermaidParser.parse(match.content) == nil
                        ? "Unsupported Mermaid diagram\n" + match.content : ""
                }
                append(kind, [.plugin(plugin.id, match: match, copy: copy)], identity: match.source)
                return
            }
            if plugin is AdmonitionPlugin {
                let type = match.attributes["type"] ?? "custom"
                let title = match.attributes["title"].flatMap { $0.isEmpty ? nil : $0 } ?? type.capitalized
                append(kind, [.text(match.content.isEmpty ? title : title + "\n" + match.content)],
                       identity: match.source)
            } else if let thinking = plugin as? ThinkingPlugin {
                let id = nextID(kind: "plugin:" + plugin.id, identity: match.source)
                let expanded = expansion[id] ?? false
                let label = expanded ? thinking.expandedHeaderText : thinking.headerText
                append(kind, [.text(label)], id: id)
                if expanded { append(kind, [.text(match.content)], identity: id + ":content") }
            } else if plugin is ArtifactPlugin {
                let block = ArtifactPlugin.block(match)
                let label: String = switch block.type {
                case .code: block.language?.uppercased() ?? "CODE"
                case .document: "DOCUMENT"
                case .html: "HTML"
                case .svg: "SVG"
                case .component: "COMPONENT"
                case .mermaid: "DIAGRAM"
                case .custom: block.customType?.uppercased() ?? "ARTIFACT"
                }
                let content = ([block.title, label, block.content].compactMap { $0 }).joined(separator: "\n")
                append(kind, [.text(content)], identity: match.source)
            } else if plugin is ToolCallPlugin {
                let id = nextID(kind: "plugin:" + plugin.id, identity: match.source)
                let name = match.attributes["toolName"] ?? "unknown"
                let toolID = match.attributes["toolId"].flatMap { $0.isEmpty ? nil : $0 }
                let status = (match.attributes["status"] ?? "pending").capitalized
                append(kind, [.text(([name, toolID.map { "ID: " + $0 }, status].compactMap { $0 }).joined(separator: "\n"))], id: id)
                if expansion[id] == true, let parameters = match.attributes["parameters"],
                   match.attributes["hasParameters"] == "true" {
                    append(kind, [.text("Parameters\n" + parameters)], identity: id + ":parameters")
                }
            } else if plugin is MermaidPlugin {
                // A diagram is visual content, like an image. Its source is
                // available through the block's own controls, not range Copy.
                let atoms: [Atom] = MermaidParser.parse(match.content) == nil
                    ? [.text("Unsupported Mermaid diagram\n" + match.content)] : [.attachment]
                append(kind, atoms, identity: match.source)
            } else {
                // Third-party plugin views have no selectable-text contract.
                append(.opaque, [.attachment], identity: match.source)
            }
        }

        private mutating func append(_ kind: Kind, _ atoms: [Atom], identity: String, id: String? = nil) {
            let resolvedID = id ?? nextID(kind: String(describing: kind), identity: identity)
            append(kind, atoms, id: resolvedID)
        }

        private func identity(for atoms: [Atom]) -> String {
            atoms.map { atom in
                switch atom.kind {
                case .text, .opaque: return atom.text + "\u{0}" + atom.copyText
                case let .formula(latex): return "formula\u{0}" + latex
                case let .code(source, language): return "code\u{0}" + source + "\u{0}" + (language ?? "")
                case let .table(source): return "table\u{0}" + source
                case let .plugin(id, match): return "plugin\u{0}" + id + "\u{0}" + match.source
                case let .image(spec):
                    return "image\u{0}" + spec.source + "\u{0}" + spec.alt + "\u{0}" +
                        (spec.title ?? "") + "\u{0}" + (spec.width.map { String($0) } ?? "") + "\u{0}" +
                        (spec.height.map { String($0) } ?? "")
                }
            }.joined(separator: "\u{1}")
        }

        private mutating func append(_ kind: Kind, _ atoms: [Atom], id: String) {
            let contentLength = atoms.reduce(0) { $0 + $1.text.utf16.count }
            guard contentLength > 0 else { return }
            if !segments.isEmpty { length += 1 }
            segments.append(.init(id: id, kind: kind,
                                  range: NSRange(location: length, length: contentLength), atoms: atoms))
            length += contentLength
        }

        private mutating func nextID(kind: String, identity: String) -> String {
            // Deterministic FNV-1a: Swift's Hasher is randomized per process.
            var hash: UInt64 = 0xcbf29ce484222325
            for byte in (kind + "\u{0}" + identity).utf8 {
                hash = (hash ^ UInt64(byte)) &* 0x100000001b3
            }
            let prefix = scope + "/" + kind + ":" + String(hash, radix: 16)
            let occurrence = occurrences[prefix, default: 0]
            occurrences[prefix] = occurrence + 1
            return prefix + ":" + String(occurrence)
        }
    }
}
