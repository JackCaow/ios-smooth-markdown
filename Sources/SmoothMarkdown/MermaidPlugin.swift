import Foundation
import SwiftUI

/// Opt-in native rendering of supported fenced `mermaid` diagrams.
public struct MermaidPlugin: BlockParserPlugin {
    public let id = "mermaid"
    public let name = "Mermaid Diagram Plugin"
    public let priority = 10
    public let onNodeTap: ((String) -> Void)?

    public init(onNodeTap: ((String) -> Void)? = nil) {
        self.onNodeTap = onNodeTap
    }

    public func canParse(_ line: String, lines: [String], at index: Int) -> Bool {
        opener(line) != nil
    }

    public func parse(_ lines: [String], at index: Int) -> BlockPluginMatch? {
        guard lines.indices.contains(index), let opening = opener(lines[index]) else { return nil }
        var content: [String] = []
        var cursor = index + 1
        while cursor < lines.count {
            if isCloser(lines[cursor], marker: opening.marker, count: opening.count) {
                cursor += 1
                break
            }
            content.append(lines[cursor])
            cursor += 1
        }
        guard !content.isEmpty else { return nil }
        let code = content.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return nil }
        let info = opening.info
        let theme = MermaidTheme.fromFenceInfo(info)
        return .init(linesConsumed: cursor - index, source: lines[index..<cursor].joined(separator: "\n"),
                     content: code, attributes: ["fence": String(repeating: opening.marker, count: opening.count),
                                                 "info": info, "theme": theme?.rawValue ?? ""])
    }

    public func render(_ match: BlockPluginMatch) -> AnyView {
        if let diagram = MermaidParser.parse(match.content) {
            return AnyView(MarkdownMermaidFence(diagram: diagram, theme: theme(for: match), onNodeTap: onNodeTap))
        }
        return AnyView(UnsupportedMermaidFence(content: match.content))
    }

    func theme(for match: BlockPluginMatch) -> MermaidTheme? {
        match.attributes["theme"].flatMap(MermaidTheme.init(rawValue:))
    }

    private func opener(_ line: String) -> (marker: String, count: Int, info: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let marker = trimmed.first, marker == "`" || marker == "~" else { return nil }
        let count = trimmed.prefix(while: { $0 == marker }).count
        guard count >= 3 else { return nil }
        let info = String(trimmed.dropFirst(count)).trimmingCharacters(in: .whitespaces)
        guard info == "mermaid" || info.hasPrefix("mermaid ") else { return nil }
        return (String(marker), count, info)
    }

    private func isCloser(_ line: String, marker: String, count: Int) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let run = trimmed.prefix(while: { String($0) == marker }).count
        return run >= count && trimmed.dropFirst(run).trimmingCharacters(in: .whitespaces).isEmpty
    }
}

private struct MarkdownMermaidFence: View {
    let diagram: MermaidDiagram
    let theme: MermaidTheme?
    let onNodeTap: ((String) -> Void)?
    @Environment(\.markdownDesignTokens) private var tokens
    var body: some View {
        MermaidDiagramView(diagram: diagram, theme: theme, onNodeTap: onNodeTap, style: tokens.mermaid)
            .frame(maxHeight: tokens.mermaid.maxHeight)
            .padding(tokens.mermaid.outerPadding)
    }
}

private struct UnsupportedMermaidFence: View {
    let content: String
    @Environment(\.markdownStrings) private var strings
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SwiftUI.Text(strings["Unsupported Mermaid diagram"]).font(.caption).foregroundColor(.secondary)
            SwiftUI.Text(content).font(.system(.body, design: .monospaced)).textSelection(.enabled)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
    }
}
