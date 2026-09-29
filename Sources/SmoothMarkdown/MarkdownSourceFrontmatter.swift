import Foundation

/// The leading YAML frontmatter envelope. Its body is editable without changing
/// the original BOM, delimiters, line endings, or following Markdown.
struct MarkdownSourceFrontmatter {
    let source: String
    let content: String
    let lineCount: Int
    private let opener: String
    private let separator: String
    private let closer: String

    static func parsePrefix(_ markdown: String) -> Self? {
        let components = markdown.components(separatedBy: "\n")
        guard components.count >= 2 else { return nil }
        let lines = components.enumerated().map { index, value in
            value + (index < components.count - 1 ? "\n" : "")
        }
        func lineText(_ line: String) -> String {
            // Swift treats CRLF as one Character, so dropping a Character or
            // testing only for LF does not reliably remove that terminator.
            return line.trimmingCharacters(in: .newlines)
        }
        let first = lineText(lines[0])
        let marker = first.hasPrefix("\u{FEFF}") ? String(first.dropFirst()) : first
        guard marker.hasPrefix("---"),
              marker.dropFirst(3).allSatisfy({ $0 == " " || $0 == "\t" }),
              (lines[0].hasSuffix("\n") || lines[0].hasSuffix("\r\n")) else { return nil }

        for closingIndex in 1..<lines.count {
            let candidate = lineText(lines[closingIndex])
            guard candidate.hasPrefix("---"),
                  candidate.dropFirst(3).allSatisfy({ $0 == " " || $0 == "\t" }) else { continue }
            let rawBody = lines[1..<closingIndex].joined()
            let separator = rawBody.hasSuffix("\r\n") ? "\r\n" : rawBody.hasSuffix("\n") ? "\n" : ""
            let content = separator.isEmpty ? rawBody : String(rawBody.dropLast(separator.count))
            return Self(source: lines[0...closingIndex].joined(), content: content,
                        lineCount: closingIndex + 1, opener: lines[0],
                        separator: separator, closer: lines[closingIndex])
        }
        return nil
    }

    func replacingContent(_ newContent: String) -> String? {
        // A delimiter inside the editable body would silently move the end of
        // frontmatter and reinterpret the rest of the document.
        let normalized = newContent.replacingOccurrences(of: "\r\n", with: "\n")
        guard !normalized.contains("\r") else { return nil }
        let lines = normalized.components(separatedBy: "\n")
        guard lines.allSatisfy({ line in
            !line.hasPrefix("---") || !line.dropFirst(3).allSatisfy({ $0 == " " || $0 == "\t" })
        }) else { return nil }
        let newline = opener.hasSuffix("\r\n") ? "\r\n" : "\n"
        let body = normalized.replacingOccurrences(of: "\n", with: newline)
        let boundary = body.isEmpty ? "" : (separator.isEmpty ? newline : separator)
        let candidate = opener + body + boundary + closer
        guard let parsed = Self.parsePrefix(candidate), parsed.source == candidate,
              parsed.content == body else { return nil }
        return candidate
    }
}
