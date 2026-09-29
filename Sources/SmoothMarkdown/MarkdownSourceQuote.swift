import Foundation

/// Exact physical lines of a simple blockquote. A lazy continuation or a
/// structured child cannot be mapped to an editable text field safely.
public struct MarkdownSourceQuote: Equatable {
    public struct Line: Equatable {
        public let prefix: String
        public let content: String
        public let ending: String
        public let sourceOffset: Int

        public var bodyOffset: Int { sourceOffset + (prefix as NSString).length }
    }

    public let lines: [Line]

    public init?(source: String) {
        guard !source.isEmpty else { return nil }
        let ns = source as NSString
        var result: [Line] = []
        var offset = 0
        while offset < ns.length {
            let search = NSRange(location: offset, length: ns.length - offset)
            let newline = ns.range(of: "\n", range: search)
            let end = newline.location == NSNotFound ? ns.length : newline.location
            let hasCR = end > offset && ns.substring(with: NSRange(location: end - 1, length: 1)) == "\r"
            let bodyEnd = hasCR ? end - 1 : end
            let raw = ns.substring(with: NSRange(location: offset, length: bodyEnd - offset))
            let chars = Array(raw)
            var index = 0
            while index < min(3, chars.count), chars[index] == " " { index += 1 }
            var depth = 0
            while index < chars.count, chars[index] == ">" {
                depth += 1
                index += 1
                if index < chars.count, chars[index] == " " || chars[index] == "\t" { index += 1 }
            }
            guard depth > 0 else { return nil }
            // A text field must not silently treat nested block syntax as prose.
            let prefix = String(chars[..<index])
            let content = String(chars[index...])
            let trimmed = content.trimmingCharacters(in: .whitespaces)
            guard !Self.isStructuredBody(trimmed) else { return nil }
            let ending = newline.location == NSNotFound ? "" : (hasCR ? "\r\n" : "\n")
            result.append(.init(prefix: prefix, content: content, ending: ending, sourceOffset: offset))
            offset = newline.location == NSNotFound ? ns.length : newline.location + 1
        }
        guard !result.isEmpty else { return nil }
        lines = result
    }

    public func toMarkdown() -> String {
        lines.map { $0.prefix + $0.content + $0.ending }.joined()
    }

    private static func isStructuredBody(_ text: String) -> Bool {
        if text.hasPrefix("# ") || text.hasPrefix("## ") || text.hasPrefix("### ") ||
            text.hasPrefix("#### ") || text.hasPrefix("##### ") || text.hasPrefix("###### ") ||
            text.hasPrefix("```") || text.hasPrefix("~~~") || text.hasPrefix("- ") ||
            text.hasPrefix("* ") || text.hasPrefix("+ ") || text.hasPrefix("|") ||
            text.hasPrefix("<") || text.hasPrefix("![") { return true }
        return text.range(of: #"^(?:\d+[.)]\s|(?:[-*_]\s*){3,}$)"#,
                          options: .regularExpression) != nil
    }
}
