import SwiftUI
#if canImport(SmoothMarkdownCore)
@_spi(ReaderInternals) import SmoothMarkdownCore
#endif

/// Syntax highlighting for code blocks and source/diff viewers. Language detection and
/// lexing run in the shared Rust core (smooth-rust-core); this type only styles tokens.
public enum CodeSyntaxHighlighter {
    /// Maps a fence tag, file extension or file name (`kt`, `tsx`, `Dockerfile`, …) to the
    /// highlighter's language name; nil when unsupported.
    public static func normalizedLanguage(_ language: String?) -> String? {
        guard let tag = fenceTag(language) else { return nil }
        return RustCodeHighlighter.normalizedLanguage(tag)
    }

    /// Highlights `code` with the code-block palette. Unsupported languages stay plain.
    public static func attributed(_ code: String, language: String?, dark: Bool, enabled: Bool, colors: MarkdownSyntaxColors? = nil) -> AttributedString {
        guard enabled, let tag = fenceTag(language), let tokens = RustCodeHighlighter.tokens(code, language: tag), !tokens.isEmpty else {
            return AttributedString(code)
        }
        let palette = colors ?? (dark ? MarkdownSyntaxColors.dark() : MarkdownSyntaxColors.light())
        return nativeAttributed(code, tokens: tokens, palette: palette)
    }

    /// Highlights a whole file once and returns its display lines (tabs expanded to `tabWidth`
    /// spaces), so multi-line comments and strings keep their colors on every line.
    public static func highlightedLines(_ code: String, language: String?, dark: Bool, colors: MarkdownSyntaxColors? = nil, tabWidth: Int = 4) -> [AttributedString] {
        let palette = colors ?? (dark ? MarkdownSyntaxColors.dark() : MarkdownSyntaxColors.light())
        if let tag = fenceTag(language), let lines = RustCodeHighlighter.lines(code, language: tag, tabWidth: tabWidth) {
            return lines.map { nativeAttributed($0.text, tokens: $0.tokens, palette: palette) }
        }
        let trimmed = code.hasSuffix("\n") ? String(code.dropLast()) : code
        return trimmed.components(separatedBy: "\n").map { AttributedString($0) }
    }

    /// Display rows of a unified diff: hunk headers, highlighted code rows with line numbers and
    /// word-level changes, and notes. Git metadata lines are omitted.
    public static func diffRows(_ patch: String, language: String?, dark: Bool, colors: MarkdownSyntaxColors? = nil, tabWidth: Int = 4) -> [CodeDiffRow] {
        let palette = colors ?? (dark ? MarkdownSyntaxColors.dark() : MarkdownSyntaxColors.light())
        guard let rows = RustCodeHighlighter.diff(patch, language: fenceTag(language) ?? "", tabWidth: tabWidth) else { return [] }
        return rows.enumerated().map { index, row in
            let text = nativeAttributed(row.line.text, tokens: row.line.tokens, palette: palette)
            var changed: Range<AttributedString.Index>?
            if let range = row.changed, let lower = attributedIndex(text, row.line.text, range.lowerBound),
               let upper = attributedIndex(text, row.line.text, range.upperBound), lower < upper {
                changed = lower..<upper
            }
            return CodeDiffRow(id: index, kind: CodeDiffRow.Kind(rawValue: row.kind) ?? .note, lineNumber: row.number, text: text, changed: changed)
        }
    }

    private static func attributedIndex(_ text: AttributedString, _ plain: String, _ utf16Offset: Int) -> AttributedString.Index? {
        let utf16 = plain.utf16
        guard let index = utf16.index(utf16.startIndex, offsetBy: utf16Offset, limitedBy: utf16.endIndex),
              let stringIndex = String.Index(index, within: plain) else { return nil }
        return AttributedString.Index(stringIndex, within: text)
    }

    /// Text and core kind of each token, for tests and diagnostics.
    static func tokens(_ code: String, language: String?) -> [(text: String, kind: UInt8)] {
        guard let tag = fenceTag(language), let tokens = RustCodeHighlighter.tokens(code, language: tag) else { return [] }
        let utf16 = Array(code.utf16)
        return tokens.map { (String(decoding: utf16[$0.start..<($0.start + $0.length)], as: UTF16.self), $0.kind) }
    }

    /// The first word of a fence info string (`kotlin title=x` → `kotlin`).
    private static func fenceTag(_ language: String?) -> String? {
        language?.split(whereSeparator: { $0.isWhitespace || $0 == "," || $0 == "{" }).first.map(String.init)
    }
}

/// One display row of a unified diff (see ``CodeSyntaxHighlighter/diffRows(_:language:dark:colors:tabWidth:)``).
public struct CodeDiffRow: Identifiable {
    public enum Kind: UInt8 { case hunk = 0, context = 1, added = 2, removed = 3, note = 4 }
    public let id: Int
    public let kind: Kind
    /// New-file line for context and added rows, old-file line for removed rows.
    public let lineNumber: Int?
    /// Display text: syntax highlighted, without the `+`/`-` prefix, tabs expanded.
    public let text: AttributedString
    /// The differing middle of a paired removed/added line, for word-level emphasis.
    public let changed: Range<AttributedString.Index>?
}

extension CodeSyntaxHighlighter {
    /// Applies native token kinds (the Rust `Kind` enum) with the palette.
    static func nativeAttributed(_ code: String, tokens: [RustCodeToken], palette: MarkdownSyntaxColors) -> AttributedString {
        var result = AttributedString(code)
        let utf16 = code.utf16
        for token in tokens {
            guard token.start >= 0, token.length > 0, token.start + token.length <= utf16.count,
                  let lowerUTF16 = utf16.index(utf16.startIndex, offsetBy: token.start, limitedBy: utf16.endIndex),
                  let upperUTF16 = utf16.index(lowerUTF16, offsetBy: token.length, limitedBy: utf16.endIndex),
                  let lowerString = String.Index(lowerUTF16, within: code), let upperString = String.Index(upperUTF16, within: code),
                  let lower = AttributedString.Index(lowerString, within: result), let upper = AttributedString.Index(upperString, within: result)
            else { continue }
            let style = nativeStyle(token.kind, palette: palette)
            if let color = style.color { result[lower..<upper].foregroundColor = color }
            if let intent = style.intent { result[lower..<upper].inlinePresentationIntent = intent }
        }
        return result
    }

    static func nativeStyle(_ kind: UInt8, palette p: MarkdownSyntaxColors) -> (color: Color?, intent: InlinePresentationIntent?) {
        switch kind {
        case 16, 17, 18, 19, 20, 25, 50: return (p.keyword, nil)                       // keywords, preproc, self/this
        case 37, 39, 40, 44, 52: return (p.string, nil)                                 // strings, regex, literals, URIs
        case 38: return (p.escape ?? p.number, nil)                                     // escapes
        case 32: return (p.escape ?? p.keyword, nil)                                    // interpolation delimiters
        case 3: return (p.comment, nil)
        case 4: return (p.comment, .emphasized)                                         // doc comments
        case 42: return (p.comment, nil)                                                // doctype
        case 23: return (p.number, nil)
        case 2, 6: return (p.literal, nil)                                              // booleans, null
        case 5: return (p.constant ?? p.literal, nil)
        case 46, 47, 7, 43, 22, 34, 35: return (p.type ?? p.keyword, nil)               // types, constructors, components, namespaces, selectors
        case 13, 14, 15: return (p.function, kind == 14 ? .stronglyEmphasized : nil)    // calls, definitions, methods
        case 26, 27, 21: return (p.property, nil)                                       // properties, keys, labels
        case 1: return (p.attribute ?? p.type ?? p.keyword, nil)                        // annotations, attributes
        case 41, 33: return (p.tag ?? p.keyword, nil)                                   // tags, element selectors
        case 36: return (p.keyword, nil)                                                // pseudo selectors
        case 24: return (p.operator, nil)
        case 28, 29, 30, 31: return (p.punctuation, nil)
        case 49: return (p.parameter, nil)
        case 45, 12: return (p.keyword, .stronglyEmphasized)                            // headings, strong
        case 11: return (nil, .emphasized)
        case 8: return (p.diffRemove ?? p.keyword, nil)
        case 9: return (p.diffAdd ?? p.string, nil)
        default: return (nil, nil)                                                      // variables, embedded, plain
        }
    }
}
