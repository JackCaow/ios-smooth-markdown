import Foundation

/// The first source-preserving semantic block types supported by the native editor.
public enum MarkdownSemanticBlock: Equatable {
    case paragraph(markdown: String)
    case heading(level: Int, markdown: String)
    case fencedCode(fence: String, info: String, code: String)
    case horizontalRule
    case raw
}

/// A block keeps its exact original source and the whitespace preceding it.
public struct MarkdownDocumentBlock: Equatable, Identifiable {
    public let id: String
    public let kind: MarkdownSemanticBlock
    public let source: String
    public let leadingTrivia: String

    public init(id: String, kind: MarkdownSemanticBlock, source: String, leadingTrivia: String = "") {
        self.id = id
        self.kind = kind
        self.source = source
        self.leadingTrivia = leadingTrivia
    }

    public var plainText: String {
        switch kind {
        case let .paragraph(markdown), let .heading(_, markdown): markdown
        case let .fencedCode(_, _, code): code
        case .horizontalRule: ""
        case .raw: source
        }
    }

    /// Replaces editable body content while retaining the original marker and line ending.
    /// Raw blocks and rules deliberately have no semantic body edit yet.
    public func replacingContent(_ content: String) -> MarkdownDocumentBlock? {
        let ending = source.hasSuffix("\r\n") ? "\r\n" : source.hasSuffix("\n") ? "\n" : ""
        switch kind {
        case .paragraph:
            return validated(.init(id: id, kind: .paragraph(markdown: content), source: content + ending, leadingTrivia: leadingTrivia))
        case let .heading(level, _):
            let pattern = try! NSRegularExpression(pattern: #"^([ \t]{0,3}#{1,6}[ \t]+)"#)
            let original = source as NSString
            let match = pattern.firstMatch(in: source, range: NSRange(location: 0, length: original.length))
            let prefix = match.map { original.substring(with: $0.range(at: 1)) } ?? String(repeating: "#", count: level) + " "
            return validated(.init(id: id, kind: .heading(level: level, markdown: content),
                                   source: prefix + content + ending, leadingTrivia: leadingTrivia))
        case let .fencedCode(fence, info, _):
            let lines = source.components(separatedBy: "\n")
            guard let opening = lines.first else { return nil }
            let newline = source.contains("\r\n") ? "\r\n" : "\n"
            let opener = opening.trimmingCharacters(in: .newlines) + newline
            let hasCloser = lines.dropFirst().contains { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.hasPrefix(fence) && trimmed.dropFirst(fence.count).trimmingCharacters(in: .whitespaces).isEmpty
            }
            let closer = hasCloser ? fence + ending : ""
            let rendered = opener + content + (content.hasSuffix(newline) || content.isEmpty ? "" : newline) + closer
            return validated(.init(id: id, kind: .fencedCode(fence: fence, info: info, code: content),
                                   source: rendered, leadingTrivia: leadingTrivia))
        case .horizontalRule, .raw: return nil
        }
    }

    private func validated(_ candidate: MarkdownDocumentBlock) -> MarkdownDocumentBlock? {
        let reparsed = MarkdownDocumentCodec().parse(candidate.source)
        guard reparsed.blocks.count == 1 else { return nil }
        switch (kind, reparsed.blocks[0].kind) {
        case (.paragraph, .paragraph), (.fencedCode, .fencedCode): return candidate
        case let (.heading(originalLevel, _), .heading(newLevel, _)) where originalLevel == newLevel: return candidate
        default: return nil
        }
    }
}

/// Immutable, source-preserving top-level document snapshot.
public struct MarkdownDocument: Equatable {
    public let blocks: [MarkdownDocumentBlock]
    public let trailingTrivia: String

    public init(blocks: [MarkdownDocumentBlock], trailingTrivia: String = "") {
        self.blocks = blocks
        self.trailingTrivia = trailingTrivia
    }

    public var isEmpty: Bool { blocks.allSatisfy { $0.plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
    public var plainText: String { blocks.map(\.plainText).joined(separator: "\n\n") }
    public func toMarkdown() -> String { blocks.map { $0.leadingTrivia + $0.source }.joined() + trailingTrivia }
    public func blockById(_ id: String) -> MarkdownDocumentBlock? { blocks.first { $0.id == id } }

    public func replacingBlock(_ replacement: MarkdownDocumentBlock) -> MarkdownDocument {
        guard let index = blocks.firstIndex(where: { $0.id == replacement.id }) else { return self }
        var next = blocks
        next[index] = replacement
        return .init(blocks: next, trailingTrivia: trailingTrivia)
    }

    public func movingBlock(_ id: String, to targetIndex: Int) -> MarkdownDocument {
        guard let index = blocks.firstIndex(where: { $0.id == id }), blocks.count > 1 else { return self }
        let target = min(max(0, targetIndex), blocks.count - 1)
        guard index != target else { return self }
        var next = blocks
        let block = next.remove(at: index)
        next.insert(block, at: target)
        let trivia = blocks.map(\.leadingTrivia)
        next = next.enumerated().map { position, item in
            .init(id: item.id, kind: item.kind, source: item.source, leadingTrivia: trivia[position])
        }
        return .init(blocks: next, trailingTrivia: trailingTrivia)
    }
}
