import Foundation

/// Inline source edits supported by paragraph and ATX heading rows in Blocks mode.
public enum MarkdownInlineMark: Equatable {
    case bold
    case italic
    case strikethrough
    case code
    case link(destination: String)
}

struct MarkdownInlineMarkEdit: Equatable {
    let markdown: String
    /// UTF-16 selection within the edited block body.
    let selection: NSRange
}

enum MarkdownInlineMarkEditor {
    /// Range commands operate on raw Markdown source. Refuse existing inline
    /// syntax instead of wrapping its markers as if they were visible text.
    /// An escaped table pipe is the one source escape handled by this editor.
    static func isSimpleRangeSource(_ source: String) -> Bool {
        let characters = Array(source)
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character == "\\" {
                guard index + 1 < characters.count, characters[index + 1] == "|" else { return false }
                index += 2
                continue
            }
            if "\r\n*~_`[]<>".contains(character) { return false }
            index += 1
        }
        return true
    }

    static func apply(_ mark: MarkdownInlineMark, to markdown: String, selection: NSRange) -> MarkdownInlineMarkEdit? {
        let source = markdown as NSString
        guard selection.location != NSNotFound, selection.location >= 0, selection.length > 0,
              NSMaxRange(selection) <= source.length,
              let swiftRange = Range(selection, in: markdown),
              NSRange(swiftRange, in: markdown) == selection,
              isScalarBoundary(selection.location, in: source),
              isScalarBoundary(NSMaxRange(selection), in: source) else { return nil }
        let selected = source.substring(with: selection)

        let prefix: String
        let suffix: String
        switch mark {
        case .bold: prefix = "**"; suffix = "**"
        case .italic: prefix = "*"; suffix = "*"
        case .strikethrough: prefix = "~~"; suffix = "~~"
        case .code:
            let delimiter = String(repeating: "`", count: longestBacktickRun(in: selected) + 1)
            let padding = selected.contains("`") ? " " : ""
            prefix = delimiter + padding
            suffix = padding + delimiter
        case let .link(destination):
            guard !selected.contains("["), !selected.contains("]"),
                  let url = URL(string: destination), MarkdownSyntax.isSafeLink(url),
                  !destination.contains(where: { $0.isWhitespace || $0 == "<" || $0 == ">" }) else { return nil }
            let escaped = url.absoluteString.replacingOccurrences(of: "(", with: "%28")
                .replacingOccurrences(of: ")", with: "%29")
            prefix = "["
            suffix = "](" + escaped + ")"
        }

        // Selecting the entire content of a simple existing mark toggles it off.
        if case .link = mark { /* Link always inserts a destination. */ }
        else if selection.location >= (prefix as NSString).length,
                NSMaxRange(selection) + (suffix as NSString).length <= source.length {
            let before = source.substring(with: NSRange(location: selection.location - (prefix as NSString).length,
                                                        length: (prefix as NSString).length))
            let after = source.substring(with: NSRange(location: NSMaxRange(selection),
                                                       length: (suffix as NSString).length))
            if before == prefix, after == suffix {
                let full = NSRange(location: selection.location - (prefix as NSString).length,
                                   length: (prefix as NSString).length + selection.length + (suffix as NSString).length)
                return .init(markdown: source.replacingCharacters(in: full, with: selected),
                             selection: NSRange(location: full.location, length: selection.length))
            }
        }

        let replacement = prefix + selected + suffix
        return .init(markdown: source.replacingCharacters(in: selection, with: replacement),
                     selection: NSRange(location: selection.location + (prefix as NSString).length,
                                        length: selection.length))
    }

    private static func longestBacktickRun(in source: String) -> Int {
        var longest = 0
        var current = 0
        for character in source {
            if character == "`" { current += 1; longest = max(longest, current) }
            else { current = 0 }
        }
        return longest
    }

    private static func isScalarBoundary(_ offset: Int, in source: NSString) -> Bool {
        guard offset > 0, offset < source.length else { return true }
        let previous = source.character(at: offset - 1)
        let next = source.character(at: offset)
        return !(0xD800...0xDBFF).contains(previous) || !(0xDC00...0xDFFF).contains(next)
    }
}
