import Foundation
import SwiftUI

/// Opt-in `==text==` highlighting. Register with the reader's parser registry.
public struct HighlightPlugin: InlineParserPlugin {
    public let id = "highlight"
    public let name = "Highlight Plugin"
    public let priority = 10
    public let triggerCharacter: Character = "="
    public init() {}
    public func canParse(_ text: String, at index: String.Index) -> Bool { index < text.endIndex && text[index...].hasPrefix("==") }
    public func parse(_ text: String, at index: String.Index) -> InlinePluginMatch? {
        InlineFormattingDelimiter.match(text, at: index, marker: "==", allowSpaces: true)
    }
    public func render(_ match: InlinePluginMatch) -> AnyView {
        AnyView(InlineFormattingFallbackText(text: match.text, highlighted: true))
    }
}

/// Opt-in `^text^` superscript. Whitespace and code remain ordinary Markdown.
public struct SuperscriptPlugin: InlineParserPlugin {
    public let id = "superscript"
    public let name = "Superscript Plugin"
    public let priority = 10
    public let triggerCharacter: Character = "^"
    public init() {}
    public func canParse(_ text: String, at index: String.Index) -> Bool { index < text.endIndex && text[index] == "^" }
    public func parse(_ text: String, at index: String.Index) -> InlinePluginMatch? {
        InlineFormattingDelimiter.match(text, at: index, marker: "^", allowSpaces: false)
    }
    public func render(_ match: InlinePluginMatch) -> AnyView {
        AnyView(InlineFormattingFallbackText(text: match.text, script: .sup))
    }
}

/// Opt-in numeric, word-internal subscripts such as `H~2~O`.
/// Other single-tilde and double-tilde spans retain their GFM meaning.
public struct SubscriptPlugin: InlineParserPlugin {
    public let id = "subscript"
    public let name = "Subscript Plugin"
    public let priority = 10
    public let triggerCharacter: Character = "~"
    public init() {}
    public func canParse(_ text: String, at index: String.Index) -> Bool { index < text.endIndex && text[index] == "~" }
    public func parse(_ text: String, at index: String.Index) -> InlinePluginMatch? {
        guard index > text.startIndex, word(text[text.index(before: index)]),
              let match = InlineFormattingDelimiter.match(text, at: index, marker: "~", allowSpaces: false),
              match.text.allSatisfy({ $0.isNumber }) else { return nil }
        let end = text.index(index, offsetBy: match.consumed)
        guard end < text.endIndex, word(text[end]) else { return nil }
        return match
    }
    public func render(_ match: InlinePluginMatch) -> AnyView {
        AnyView(InlineFormattingFallbackText(text: match.text, script: .sub))
    }
    private func word(_ character: Character) -> Bool { character.isLetter || character.isNumber }
}

private struct InlineFormattingFallbackText: View {
    let text: String
    var highlighted = false
    var script: MarkdownHTMLScript?
    @ScaledMetric(relativeTo: .body) private var bodySize = MarkdownHTMLScript.bodyPointSize

    var body: some View {
        let sheet = MarkdownStyleSheet.default()
        let style = sheet.resolvedHTMLStyle(sheet.resolvedInlineStyle(bold: false,
            italic: false, strike: false, link: false, code: false, script: script),
            underline: false, highlight: highlighted)
        var attributed = AttributedString(text)
        if let color = style.backgroundColor { attributed.backgroundColor = color }
        var rendered = Text(attributed)
        let scale = bodySize / MarkdownHTMLScript.bodyPointSize
        if let size = style.fontSize { rendered = rendered.font(.system(size: size * scale)) }
        if let color = style.textColor { rendered = rendered.foregroundColor(color) }
        if let script { rendered = rendered.baselineOffset(script.baselineOffset(scale: scale)) }
        return rendered
    }
}

private enum InlineFormattingDelimiter {
    static func match(_ text: String, at index: String.Index, marker: String, allowSpaces: Bool) -> InlinePluginMatch? {
        guard index < text.endIndex, text[index...].hasPrefix(marker) else { return nil }
        let delimiter = marker.first!
        if index > text.startIndex, text[text.index(before: index)] == delimiter { return nil }
        let start = text.index(index, offsetBy: marker.count)
        guard start < text.endIndex, text[start] != delimiter, !text[start].isWhitespace else { return nil }
        var cursor = start
        var escaped = false
        while cursor < text.endIndex {
            let character = text[cursor]
            if character == "\n" || character == "\r" || character == "`" { return nil }
            if !escaped, text[cursor...].hasPrefix(marker) {
                let end = text.index(cursor, offsetBy: marker.count)
                guard cursor > start, !text[text.index(before: cursor)].isWhitespace,
                      end == text.endIndex || text[end] != delimiter else { return nil }
                let payload = String(text[start..<cursor])
                if !allowSpaces, payload.contains(where: { $0.isWhitespace }) { return nil }
                return .init(consumed: text.distance(from: index, to: end),
                             text: NativeMarkdownTextDecoder.decode(payload))
            }
            if escaped { escaped = false }
            else if character == "\\" { escaped = true }
            cursor = text.index(after: cursor)
        }
        return nil
    }
}

extension InlineContent.Style {
    mutating func apply(_ plugin: any InlineParserPlugin) -> Bool {
        if plugin is HighlightPlugin { highlighted = true }
        else if plugin is SuperscriptPlugin { script = .sup }
        else if plugin is SubscriptPlugin { script = .sub }
        else { return false }
        return true
    }
}
