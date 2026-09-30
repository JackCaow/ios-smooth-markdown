import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public struct ThinkingBlock: Equatable {
    public let content: String
    public let isCollapsed: Bool
}

public enum ArtifactType: String, Equatable {
    case code, document, html, svg, component, mermaid, custom
}

public struct ArtifactBlock: Equatable {
    public let identifier: String
    public let type: ArtifactType
    public let customType: String?
    public let content: String
    public let title: String?
    public let language: String?
}

public enum ToolCallStatus: String, Equatable {
    case running, completed, failed, cancelled, pending
}

public struct ToolCallBlock: Equatable {
    public let toolName: String
    public let toolId: String?
    public let parameters: String?
    public let result: String?
    public let status: ToolCallStatus
    public let errorMessage: String?
}

/// Opt-in parser for `<thinking>`, `<think>`, and `<|thinking|>` blocks.
public struct ThinkingPlugin: BlockParserPlugin {
    public let id = "thinking"
    public let name = "Thinking Plugin"
    public let priority = 20
    public let headerText: String
    public let expandedHeaderText: String

    public init(headerText: String = "Thinking...", expandedHeaderText: String = "Thinking") {
        self.headerText = headerText
        self.expandedHeaderText = expandedHeaderText
    }

    public func canParse(_ line: String, lines: [String], at index: Int) -> Bool {
        Self.start(line) != nil
    }

    public func parse(_ lines: [String], at index: Int) -> BlockPluginMatch? {
        guard lines.indices.contains(index), let syntax = Self.start(lines[index]) else { return nil }
        let closing = syntax == "xml" ? #"^</(thinking|think)>\s*$"# : #"^<\|/(thinking|think)\|>\s*$"#
        let collected = AIBlockSyntax.collect(lines, at: index) { AIBlockSyntax.matches($0, pattern: closing) }
        return BlockPluginMatch(linesConsumed: collected.consumed, source: collected.source,
                                content: collected.content.trimmingCharacters(in: .whitespacesAndNewlines),
                                attributes: ["isCollapsed": "true"])
    }

    public func render(_ match: BlockPluginMatch) -> AnyView {
        AnyView(ThinkingCard(block: ThinkingBlock(content: match.content, isCollapsed: true),
                             headerText: headerText, expandedHeaderText: expandedHeaderText))
    }

    private static func start(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if AIBlockSyntax.matches(trimmed, pattern: #"^<(thinking|think)>\s*$"#) { return "xml" }
        if AIBlockSyntax.matches(trimmed, pattern: #"^<\|(thinking|think)\|>\s*$"#) { return "markdown" }
        return nil
    }
}

/// Opt-in parser for Claude-style `<artifact ...>` blocks.
public struct ArtifactPlugin: BlockParserPlugin {
    public let id = "artifact"
    public let name = "Artifact Plugin"
    public let priority = 20
    public let showCopyButton: Bool
    public let onArtifactTap: ((ArtifactBlock) -> Void)?

    public init(showCopyButton: Bool = true, onArtifactTap: ((ArtifactBlock) -> Void)? = nil) {
        self.showCopyButton = showCopyButton
        self.onArtifactTap = onArtifactTap
    }

    public func canParse(_ line: String, lines: [String], at index: Int) -> Bool {
        AIBlockSyntax.capture(line.trimmingCharacters(in: .whitespaces), pattern: #"^<artifact\s+(.+?)>\s*$"#) != nil
    }

    public func parse(_ lines: [String], at index: Int) -> BlockPluginMatch? {
        guard lines.indices.contains(index), let raw = AIBlockSyntax.capture(
            lines[index].trimmingCharacters(in: .whitespaces), pattern: #"^<artifact\s+(.+?)>\s*$"#)?.first else { return nil }
        let parsed = AIBlockSyntax.attributes(raw)
        let identifier = parsed["identifier"] ?? parsed["id"] ?? "unnamed"
        let typeName = (parsed["type"] ?? "custom").lowercased()
        let type = Self.type(typeName)
        let collected = AIBlockSyntax.collect(lines, at: index) {
            AIBlockSyntax.matches($0, pattern: #"^</artifact>\s*$"#)
        }
        return BlockPluginMatch(linesConsumed: collected.consumed, source: collected.source,
                                content: collected.content,
                                attributes: ["identifier": identifier, "type": type.rawValue,
                                             "customType": type == .custom ? typeName : "",
                                             "title": parsed["title"] ?? "",
                                             "language": parsed["language"] ?? parsed["lang"] ?? ""])
    }

    public func render(_ match: BlockPluginMatch) -> AnyView {
        AnyView(ArtifactCard(block: Self.block(match), showCopyButton: showCopyButton, onTap: onArtifactTap))
    }

    public static func block(_ match: BlockPluginMatch) -> ArtifactBlock {
        ArtifactBlock(identifier: match.attributes["identifier"] ?? "unnamed",
                      type: ArtifactType(rawValue: match.attributes["type"] ?? "") ?? .custom,
                      customType: match.attributes["customType"].flatMap { $0.isEmpty ? nil : $0 },
                      content: match.content,
                      title: match.attributes["title"].flatMap { $0.isEmpty ? nil : $0 },
                      language: match.attributes["language"].flatMap { $0.isEmpty ? nil : $0 })
    }

    private static func type(_ value: String) -> ArtifactType {
        switch value {
        case "code", "application/vnd.ant.code": .code
        case "document", "text/markdown", "text/plain": .document
        case "html", "text/html": .html
        case "svg", "image/svg+xml": .svg
        case "component", "application/vnd.ant.react": .component
        case "mermaid": .mermaid
        default: .custom
        }
    }
}

/// Opt-in parser for `<tool_use>` blocks. Source syntax starts in pending status.
public struct ToolCallPlugin: BlockParserPlugin {
    public let id = "tool_call"
    public let name = "Tool Call Plugin"
    public let priority = 25
    public let showParameters: Bool
    public let showResult: Bool
    public let onToolCallTap: ((ToolCallBlock) -> Void)?

    public init(showParameters: Bool = true, showResult: Bool = true,
                onToolCallTap: ((ToolCallBlock) -> Void)? = nil) {
        self.showParameters = showParameters
        self.showResult = showResult
        self.onToolCallTap = onToolCallTap
    }

    public func canParse(_ line: String, lines: [String], at index: Int) -> Bool {
        AIBlockSyntax.matches(line.trimmingCharacters(in: .whitespaces), pattern: #"^<tool_use>\s*$"#)
    }

    public func parse(_ lines: [String], at index: Int) -> BlockPluginMatch? {
        guard lines.indices.contains(index), canParse(lines[index], lines: lines, at: index) else { return nil }
        let collected = AIBlockSyntax.collect(lines, at: index) {
            AIBlockSyntax.matches($0, pattern: #"^</tool_use>\s*$"#)
        }
        let name = AIBlockSyntax.capture(collected.content, pattern: #"<tool_name>([^<]+)</tool_name>"#)?.first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown"
        let toolId = AIBlockSyntax.capture(collected.content, pattern: #"<tool_id>([^<]+)</tool_id>"#)?.first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // Flutter's parser intentionally recognizes lowercase input tags only.
        let input = collected.content.range(of: "<input>").flatMap { start -> String? in
            guard let end = collected.content.range(of: "</input>", range: start.upperBound..<collected.content.endIndex) else { return nil }
            return String(collected.content[start.upperBound..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return BlockPluginMatch(linesConsumed: collected.consumed, source: collected.source,
                                content: collected.content,
                                attributes: ["toolName": name, "toolId": toolId,
                                             "parameters": input ?? "", "hasParameters": input == nil ? "false" : "true",
                                             "status": ToolCallStatus.pending.rawValue])
    }

    public func render(_ match: BlockPluginMatch) -> AnyView {
        AnyView(ToolCallCard(block: Self.block(match), showParameters: showParameters,
                             showResult: showResult, onTap: onToolCallTap))
    }

    public static func block(_ match: BlockPluginMatch) -> ToolCallBlock {
        ToolCallBlock(toolName: match.attributes["toolName"] ?? "unknown",
                      toolId: match.attributes["toolId"].flatMap { $0.isEmpty ? nil : $0 },
                      parameters: match.attributes["hasParameters"] == "true" ? match.attributes["parameters"] : nil,
                      result: nil, status: .pending, errorMessage: nil)
    }
}

private enum AIBlockSyntax {
    static func matches(_ text: String, pattern: String) -> Bool { capture(text, pattern: pattern) != nil }

    static func capture(_ text: String, pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let full = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: full) else { return nil }
        return (1..<match.numberOfRanges).map { index in
            Range(match.range(at: index), in: text).map { String(text[$0]) } ?? ""
        }
    }

    static func collect(_ lines: [String], at start: Int, until isClosing: (String) -> Bool)
        -> (consumed: Int, source: String, content: String) {
        var end = start + 1
        while end < lines.count && !isClosing(lines[end].trimmingCharacters(in: .whitespaces)) { end += 1 }
        let consumed = end - start + (end < lines.count ? 1 : 0)
        return (consumed, lines[start..<(start + consumed)].joined(separator: "\n"),
                lines[(start + 1)..<end].joined(separator: "\n"))
    }

    static func attributes(_ raw: String) -> [String: String] {
        guard let regex = try? NSRegularExpression(pattern: #"(\w+)=["']([^"']*)["']"#) else { return [:] }
        let range = NSRange(raw.startIndex..<raw.endIndex, in: raw)
        var result: [String: String] = [:]
        for match in regex.matches(in: raw, range: range) {
            guard let name = Range(match.range(at: 1), in: raw), let value = Range(match.range(at: 2), in: raw) else { continue }
            result[String(raw[name]).lowercased()] = String(raw[value])
        }
        return result
    }
}

private struct ThinkingCard: View {
    @Environment(\.markdownStrings) private var strings
    @Environment(\.markdownDesignTokens) private var designTokens
    private var tokens: MarkdownPluginPanelTokens { designTokens.plugins.thinking }
    let block: ThinkingBlock
    let headerText: String
    let expandedHeaderText: String
    @State private var expanded = false

    init(block: ThinkingBlock, headerText: String, expandedHeaderText: String) {
        self.block = block
        self.headerText = headerText
        self.expandedHeaderText = expandedHeaderText
        _expanded = State(initialValue: !block.isCollapsed)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { expanded.toggle() } label: {
                HStack(spacing: tokens.iconSpacing) {
                    Image(systemName: "sparkle.magnifyingglass").font(tokens.iconFont).foregroundColor(tokens.accentColor)
                    Text(expanded ? (expandedHeaderText == "Thinking" ? strings.thinking : expandedHeaderText) : (headerText == "Thinking..." ? strings.thinkingInProgress : headerText)).font(tokens.titleFont ?? .subheadline.weight(.medium)).foregroundColor(tokens.titleColor)
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down").font(tokens.iconFont).foregroundColor(tokens.accentColor)
                }
                .padding(tokens.headerPadding)
                .background(tokens.headerBackgroundColor ?? .clear)
                .frame(minHeight: tokens.minimumControlSize)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("thinking-card-toggle")
            .accessibilityValue(expanded ? strings.expanded : strings.collapsed)
            if expanded {
                Rectangle().fill(tokens.borderColor ?? Color.secondary.opacity(0.35)).frame(height: tokens.dividerThickness)
                Text(block.content).font(tokens.contentFont ?? .body).foregroundColor(tokens.contentColor).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(tokens.contentPadding)
            }
        }
        .background(tokens.backgroundColor ?? Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: tokens.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: tokens.cornerRadius).stroke(tokens.borderColor ?? Color.secondary.opacity(0.35), lineWidth: tokens.borderWidth))
        .padding(tokens.outerPadding)
    }
}

private struct ArtifactCard: View {
    @Environment(\.markdownStrings) private var strings
    @Environment(\.markdownDesignTokens) private var designTokens
    private var tokens: MarkdownPluginPanelTokens { designTokens.plugins.artifact }
    let block: ArtifactBlock
    let showCopyButton: Bool
    let onTap: ((ArtifactBlock) -> Void)?
    @State private var copied = false
    @State private var resetTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: tokens.iconSpacing) {
                Image(systemName: icon).font(tokens.iconFont).foregroundColor(tokens.accentColor ?? .accentColor)
                VStack(alignment: .leading, spacing: tokens.metadataSpacing) {
                    if let title = block.title { Text(title).font(tokens.titleFont ?? .subheadline.weight(.medium)).foregroundColor(tokens.titleColor) }
                    Text(typeLabel).font(tokens.metadataFont ?? .caption2.weight(.semibold)).foregroundColor(tokens.metadataColor ?? tokens.accentColor ?? .accentColor)
                }
                Spacer()
                if showCopyButton {
                    Button { copy() } label: {
                        Label(copied ? strings.copied : strings.copy, systemImage: copied ? "checkmark" : "doc.on.doc")
                            .frame(minWidth: tokens.minimumControlSize, minHeight: tokens.minimumControlSize)
                    }
                        .buttonStyle(.plain).font(tokens.statusFont ?? .caption)
                        .accessibilityLabel(copied ? strings.copied : strings.copyArtifact)
                }
            }
            .padding(tokens.headerPadding)
            .background(tokens.headerBackgroundColor ?? Color.secondary.opacity(0.08))
            Rectangle().fill(tokens.borderColor ?? Color.secondary.opacity(0.35)).frame(height: tokens.dividerThickness)
            ScrollView {
                Text(block.content).font(tokens.contentFont ?? .system(.body, design: .monospaced)).foregroundColor(tokens.contentColor)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(tokens.contentPadding)
            }
            .frame(maxHeight: tokens.maximumContentHeight)
            .contentShape(Rectangle())
            .onTapGesture { onTap?(block) }
        }
        .background(tokens.backgroundColor ?? .clear)
        .overlay(RoundedRectangle(cornerRadius: tokens.cornerRadius).stroke(tokens.borderColor ?? Color.secondary.opacity(0.35), lineWidth: tokens.borderWidth))
        .clipShape(RoundedRectangle(cornerRadius: tokens.cornerRadius))
        .padding(tokens.outerPadding)
        .onDisappear { resetTask?.cancel() }
    }

    private var icon: String {
        switch block.type {
        case .code: "chevron.left.forwardslash.chevron.right"
        case .document: "doc.text"
        case .html: "chevron.left.forwardslash.chevron.right"
        case .svg: "photo"
        case .component: "square.stack"
        case .mermaid: "point.3.connected.trianglepath.dotted"
        case .custom: "puzzlepiece"
        }
    }

    private var typeLabel: String {
        switch block.type {
        case .code: block.language?.uppercased() ?? strings.code
        case .document: strings.document
        case .html: "HTML"
        case .svg: "SVG"
        case .component: strings.component
        case .mermaid: strings.diagram
        case .custom: block.customType?.uppercased() ?? strings.artifact
        }
    }

    private func copy() {
        #if canImport(UIKit)
        UIPasteboard.general.string = block.content
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(block.content, forType: .string)
        #endif
        copied = true
        resetTask?.cancel()
        resetTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(min(tokens.copyFeedbackSeconds, 86_400) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            copied = false
        }
    }
}

private struct ToolCallCard: View {
    @Environment(\.markdownStrings) private var strings
    @Environment(\.markdownDesignTokens) private var designTokens
    private var tokens: MarkdownPluginPanelTokens { designTokens.plugins.toolCall }
    let block: ToolCallBlock
    let showParameters: Bool
    let showResult: Bool
    let onTap: ((ToolCallBlock) -> Void)?
    @State private var expanded = false

    var body: some View {
        let hasDetails = (showParameters && block.parameters != nil) || (showResult && block.result != nil)
            || block.errorMessage != nil
        VStack(alignment: .leading, spacing: 0) {
            Button {
                if hasDetails { expanded.toggle() }
                onTap?(block)
            } label: {
                HStack(spacing: tokens.iconSpacing) {
                    Circle().fill(statusColor).frame(width: tokens.statusIndicatorSize, height: tokens.statusIndicatorSize)
                    Image(systemName: "wrench.and.screwdriver").font(tokens.iconFont).foregroundColor(tokens.accentColor ?? tokens.metadataColor ?? .secondary)
                    VStack(alignment: .leading, spacing: tokens.metadataSpacing) {
                        Text(block.toolName).font(tokens.titleFont ?? .system(.subheadline, design: .monospaced)).foregroundColor(tokens.titleColor)
                        if let id = block.toolId { Text("\(strings.identifier): \(id)").font(tokens.metadataFont ?? .caption2).foregroundColor(tokens.metadataColor ?? .secondary).padding(tokens.metadataPadding) }
                    }
                    Spacer()
                    Text(statusLabel).font(tokens.statusFont ?? .caption.weight(.medium)).foregroundColor(statusColor)
                    if hasDetails { Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.caption) }
                }
                .padding(tokens.headerPadding)
                .background(tokens.headerBackgroundColor ?? .clear)
                .frame(minHeight: tokens.minimumControlSize)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(expanded ? strings.expanded : strings.collapsed)
            if expanded {
                Rectangle().fill(tokens.borderColor ?? Color.secondary.opacity(0.25)).frame(height: tokens.dividerThickness)
                if showParameters, let parameters = block.parameters { section(strings.parameters, parameters) }
                if showResult, let result = block.result { section(strings.result, result) }
                if let error = block.errorMessage { section(strings.error, error) }
            }
        }
        .background(tokens.backgroundColor ?? Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: tokens.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: tokens.cornerRadius).stroke(tokens.borderColor ?? Color.secondary.opacity(0.25), lineWidth: tokens.borderWidth))
        .padding(tokens.outerPadding)
    }

    private func section(_ heading: String, _ content: String) -> some View {
        VStack(alignment: .leading, spacing: tokens.sectionSpacing) {
            Text(heading).font(tokens.metadataFont ?? .caption.weight(.semibold)).foregroundColor(tokens.metadataColor ?? .secondary)
            Text(content).font(tokens.contentFont ?? .system(.body, design: .monospaced)).foregroundColor(tokens.contentColor).textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(tokens.contentPadding)
    }

    private var statusLabel: String {
        switch block.status {
        case .running: strings.running
        case .completed: strings.completed
        case .failed: strings.failed
        case .cancelled: strings.cancelled
        case .pending: strings.pending
        }
    }
    private var statusColor: Color {
        if let color = tokens.statusColors[block.status] { return color }
        return tokens.accentColor ?? .accentColor

    }
}
