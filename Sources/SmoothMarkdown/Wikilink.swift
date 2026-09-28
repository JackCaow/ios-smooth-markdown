import Foundation
import SwiftUI

/// Scratch-style `[[note title]]` parser used only when wikilinks are enabled.
public struct WikilinkPlugin: InlineParserPlugin {
    public let id = "wikilink"
    public let name = "Wikilink"
    public let priority = 100
    public let triggerCharacter: Character = "["
    public let onTapWikilink: ((String) -> Void)?

    public init(onTapWikilink: ((String) -> Void)? = nil) {
        self.onTapWikilink = onTapWikilink
    }

    public func canParse(_ text: String, at index: String.Index) -> Bool {
        guard index < text.endIndex, text[index] == "[" else { return false }
        let next = text.index(after: index)
        return next < text.endIndex && text[next] == "["
    }

    public func parse(_ text: String, at index: String.Index) -> InlinePluginMatch? {
        guard canParse(text, at: index) else { return nil }
        let targetStart = text.index(index, offsetBy: 2)
        guard targetStart < text.endIndex else { return nil }
        var end = targetStart
        while end < text.endIndex, text[end] != "]" { end = text.index(after: end) }
        guard end > targetStart, end < text.endIndex else { return nil }
        let secondClose = text.index(after: end)
        guard secondClose < text.endIndex, text[secondClose] == "]" else { return nil }
        let target = String(text[targetStart..<end])
        let after = text.index(after: secondClose)
        return InlinePluginMatch(consumed: text.distance(from: index, to: after),
                                 text: target, attributes: ["target": target])
    }

    public func render(_ match: InlinePluginMatch) -> AnyView {
        let title = match.attributes["target"] ?? match.text
        return AnyView(Button {
            onTapWikilink?(title)
        } label: {
            SwiftUI.Text(title)
                .foregroundStyle(Color.blue)
                .underline(true, pattern: .dash)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isLink)
        .accessibilityLabel(title)
        .accessibilityIdentifier("wikilink-\(title)"))
    }
}

/// UTF-16 trigger ranges match UITextView's selection coordinates.
enum WikilinkTrigger {
    struct Match: Equatable {
        let range: NSRange
        let query: String
    }

    static func match(in text: String, cursor: Int) -> Match? {
        let source = text as NSString
        guard cursor >= 0, cursor <= source.length,
              Range(NSRange(location: cursor, length: 0), in: text) != nil else { return nil }
        let prefix = source.substring(to: cursor) as NSString
        let open = prefix.range(of: "[[", options: .backwards)
        guard open.location != NSNotFound else { return nil }
        let latestClose = prefix.range(of: "]]", options: .backwards)
        guard latestClose.location == NSNotFound || open.location > latestClose.location else { return nil }
        if open.location > 0 {
            let previous = source.character(at: open.location - 1)
            guard previous == 0x20 || previous == 0x0A || previous == 0x0D else { return nil }
        }
        let query = source.substring(with: NSRange(location: NSMaxRange(open), length: cursor - NSMaxRange(open)))
        guard !query.contains("\n"), !query.contains("\r"), !query.contains("]"),
              !isInsideInlineCode(prefix: source.substring(to: open.location)) else { return nil }
        return Match(range: NSRange(location: open.location, length: cursor - open.location), query: query)
    }

    static func suggestions(_ candidates: [String], for query: String) -> [String] {
        Array(candidates.filter { $0.localizedCaseInsensitiveContains(query) }.prefix(10))
    }

    private static func isInsideInlineCode(prefix: String) -> Bool {
        let line = String(prefix.split(separator: "\n", omittingEmptySubsequences: false).last ?? "")
        var activeRun = 0
        let characters = Array(line)
        var index = 0
        while index < characters.count {
            if characters[index] == "`", index == 0 || characters[index - 1] != "\\" {
                var end = index + 1
                while end < characters.count, characters[end] == "`" { end += 1 }
                let count = end - index
                if activeRun == 0 { activeRun = count }
                else if activeRun == count { activeRun = 0 }
                index = end
            } else { index += 1 }
        }
        return activeRun != 0
    }
}
