import SwiftUI

enum CodeSyntaxHighlighter {
    enum Kind: Equatable {
        case plain, keyword, string, comment, number, literal, type, function, property, `operator`, punctuation, diffAdd, diffRemove
    }

    struct Token: Equatable {
        let text: String
        let kind: Kind
    }

    fileprivate static let keywordSets: [String: Set<String>] = [
        "swift": ["actor", "as", "async", "await", "break", "case", "catch", "class", "continue", "default", "defer", "do", "else", "enum", "extension", "for", "func", "guard", "if", "import", "in", "init", "let", "private", "protocol", "public", "return", "self", "static", "struct", "switch", "throw", "throws", "try", "var", "where", "while"],
        "kotlin": ["as", "break", "by", "catch", "class", "companion", "continue", "data", "do", "else", "enum", "false", "for", "fun", "if", "import", "in", "interface", "is", "null", "object", "package", "private", "public", "return", "sealed", "suspend", "this", "throw", "true", "try", "val", "var", "when", "while"],
        "java": ["abstract", "boolean", "break", "case", "catch", "class", "continue", "default", "do", "else", "enum", "extends", "final", "for", "if", "implements", "import", "instanceof", "int", "interface", "new", "private", "protected", "public", "return", "static", "super", "switch", "this", "throw", "throws", "try", "void", "while"],
        "dart": ["abstract", "as", "async", "await", "break", "case", "catch", "class", "const", "continue", "default", "do", "else", "enum", "extends", "final", "for", "if", "import", "in", "late", "mixin", "new", "required", "return", "static", "super", "switch", "this", "throw", "try", "var", "void", "while", "with", "yield"],
        "javascript": ["async", "await", "break", "case", "catch", "class", "const", "continue", "default", "delete", "do", "else", "export", "extends", "finally", "for", "function", "if", "import", "in", "instanceof", "let", "new", "return", "switch", "this", "throw", "try", "typeof", "var", "void", "while", "yield"],
        "typescript": ["as", "async", "await", "break", "case", "catch", "class", "const", "continue", "default", "do", "else", "enum", "export", "extends", "finally", "for", "function", "if", "implements", "import", "in", "interface", "let", "new", "private", "public", "readonly", "return", "static", "switch", "this", "throw", "try", "type", "typeof", "var", "void", "while"],
        "python": ["and", "as", "assert", "async", "await", "break", "class", "continue", "def", "del", "elif", "else", "except", "finally", "for", "from", "global", "if", "import", "in", "is", "lambda", "nonlocal", "not", "or", "pass", "raise", "return", "try", "while", "with", "yield"],
        "json": [],
        "shell": ["case", "do", "done", "elif", "else", "esac", "export", "fi", "for", "function", "if", "in", "local", "return", "then", "while"],
    ]
    fileprivate static let literals: Set<String> = ["true", "false", "null", "nil", "None", "True", "False", "undefined"]

    static func normalizedLanguage(_ language: String?) -> String? {
        guard let raw = language?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace || $0 == "," })
            .first
            .map(String.init),
              !raw.isEmpty
        else {
            return nil
        }
        switch raw {
        case "js", "jsx", "javascript", "node": return "javascript"
        case "ts", "tsx", "typescript": return "typescript"
        case "kt", "kts", "kotlin": return "kotlin"
        case "java": return "java"
        case "c", "h": return "c"
        case "cc", "cpp", "c++", "cxx", "hpp", "hh", "hxx": return "cpp"
        case "cs", "c#", "csharp": return "csharp"
        case "go", "golang": return "go"
        case "rs", "rust": return "rust"
        case "php", "php3", "php4", "php5", "phtml": return "php"
        case "rb", "ruby": return "ruby"
        case "dart": return "dart"
        case "scala", "sc": return "scala"
        case "sql", "mysql", "pgsql", "postgres", "postgresql", "sqlite": return "sql"
        case "lua": return "lua"
        case "r": return "r"
        case "m", "mm", "objc", "objective-c", "objectivec": return "objectivec"
        case "swift": return "swift"
        case "py", "python", "python3": return "python"
        case "sh", "bash", "zsh", "shell", "shellscript", "powershell", "ps1": return "shell"
        case "json", "jsonc": return "json"
        case "yaml", "yml": return "yaml"
        case "diff", "patch": return "diff"
        case "html", "xml", "svg", "vue": return "markup"
        case "css", "scss", "sass": return "css"
        case "md", "markdown": return "markdown"
        case "text", "txt", "plain", "plaintext": return "plain"
        default: return raw
        }
    }

    static func tokenize(_ code: String, language: String?) -> [Token] {
        guard let language = normalizedLanguage(language) else { return [.init(text: code, kind: .plain)] }
        let spans = language == "diff" ? highlightDiff(code) : (genericLanguages.contains(language) ? highlightGeneric(code, language: language) : [])
        let chars = Array(code)
        var result: [Token] = []; var cursor = 0
        for span in spans {
            if cursor < span.start { result.append(.init(text: String(chars[cursor..<span.start]), kind: .plain)) }
            let text = String(chars[span.start..<span.end])
            result.append(.init(text: text, kind: span.kind == .keyword && literals.contains(text) ? .literal : span.kind))
            cursor = span.end
        }
        if cursor < chars.count { result.append(.init(text: String(chars[cursor...]), kind: .plain)) }
        return result.isEmpty ? [.init(text: code, kind: .plain)] : result
    }

    static func attributed(_ code: String, language: String?, dark: Bool, enabled: Bool, colors: MarkdownSyntaxColors? = nil) -> AttributedString {
        guard enabled else { return AttributedString(code) }
        let palette = colors ?? (dark ? MarkdownSyntaxColors.dark() : MarkdownSyntaxColors.light())
        var result = AttributedString()
        for token in tokenize(code, language: language) {
            var fragment = AttributedString(token.text)
            switch token.kind {
            case .plain: break
            case .keyword: fragment.foregroundColor = palette.keyword
            case .string: fragment.foregroundColor = palette.string
            case .comment: fragment.foregroundColor = palette.comment
            case .number: fragment.foregroundColor = palette.number
            case .literal: fragment.foregroundColor = palette.literal
            case .type: fragment.foregroundColor = palette.type
            case .function: fragment.foregroundColor = palette.function
            case .property: fragment.foregroundColor = palette.property ?? (token.text.hasPrefix("\"") || token.text.hasPrefix("'") ? palette.string : nil)
            case .operator: fragment.foregroundColor = palette.operator
            case .punctuation: fragment.foregroundColor = palette.punctuation
            case .diffAdd: fragment.foregroundColor = palette.diffAdd ?? palette.string
            case .diffRemove: fragment.foregroundColor = palette.diffRemove ?? palette.keyword
            }
            result += fragment
        }
        return result
    }
}

private struct CodeSyntaxHighlightSpan {
    let start: Int
    let end: Int
    let kind: CodeSyntaxHighlighter.Kind
}

private func highlightDiff(_ code: String) -> [CodeSyntaxHighlightSpan] {
    let chars = Array(code)
    var spans: [CodeSyntaxHighlightSpan] = []
    var lineStart = 0
    while lineStart < chars.count {
        var lineEnd = lineStart
        while lineEnd < chars.count && chars[lineEnd] != "\n" {
            lineEnd += 1
        }
        if lineEnd > lineStart {
            if starts(with: "+", chars: chars, at: lineStart), !starts(with: "+++", chars: chars, at: lineStart) {
                spans.append(CodeSyntaxHighlightSpan(start: lineStart, end: lineEnd, kind: .diffAdd))
            } else if starts(with: "-", chars: chars, at: lineStart), !starts(with: "---", chars: chars, at: lineStart) {
                spans.append(CodeSyntaxHighlightSpan(start: lineStart, end: lineEnd, kind: .diffRemove))
            } else if starts(with: "@@", chars: chars, at: lineStart) {
                spans.append(CodeSyntaxHighlightSpan(start: lineStart, end: lineEnd, kind: .keyword))
            }
        }
        lineStart = lineEnd == chars.count ? chars.count : lineEnd + 1
    }
    return spans
}

private func highlightGeneric(_ code: String, language: String) -> [CodeSyntaxHighlightSpan] {
    let chars = Array(code)
    var spans: [CodeSyntaxHighlightSpan] = []
    var i = 0
    while i < chars.count {
        let ch = chars[i]
        if starts(with: "<!--", chars: chars, at: i), language == "markup" {
            let end = endOfNeedle("-->", chars: chars, from: i + 4, includeNeedle: true)
            spans.append(CodeSyntaxHighlightSpan(start: i, end: end, kind: .comment))
            i = end
        } else if starts(with: "/*", chars: chars, at: i), blockCommentLanguages.contains(language) {
            let end = endOfNeedle("*/", chars: chars, from: i + 2, includeNeedle: true)
            spans.append(CodeSyntaxHighlightSpan(start: i, end: end, kind: .comment))
            i = end
        } else if starts(with: "//", chars: chars, at: i), slashCommentLanguages.contains(language) {
            let end = lineEnd(chars, from: i)
            spans.append(CodeSyntaxHighlightSpan(start: i, end: end, kind: .comment))
            i = end
        } else if starts(with: "--", chars: chars, at: i), dashCommentLanguages.contains(language) {
            let end = lineEnd(chars, from: i)
            spans.append(CodeSyntaxHighlightSpan(start: i, end: end, kind: .comment))
            i = end
        } else if ch == "#", hashCommentLanguages.contains(language) {
            let end = lineEnd(chars, from: i)
            spans.append(CodeSyntaxHighlightSpan(start: i, end: end, kind: .comment))
            i = end
        } else if ch == "\"" || ch == "'" || ch == "`" {
            let end = quotedEnd(chars, start: i, quote: ch)
            let kind: CodeSyntaxHighlighter.Kind = propertyStringLanguages.contains(language) && nextNonWhitespace(chars, from: end) == ":"
                ? .property
                : .string
            spans.append(CodeSyntaxHighlightSpan(start: i, end: end, kind: kind))
            i = end
        } else if ch.isNumber || (ch == "-" && i + 1 < chars.count && chars[i + 1].isNumber) {
            let end = numberEnd(chars, start: i)
            spans.append(CodeSyntaxHighlightSpan(start: i, end: end, kind: .number))
            i = end
        } else if isIdentifierStart(ch) {
            let end = identifierEnd(chars, start: i)
            let word = String(chars[i..<end])
            if let kind = classifyIdentifier(word, chars: chars, end: end, language: language) {
                spans.append(CodeSyntaxHighlightSpan(start: i, end: end, kind: kind))
            }
            i = end
        } else if operatorChars.contains(ch) {
            spans.append(CodeSyntaxHighlightSpan(start: i, end: i + 1, kind: .operator))
            i += 1
        } else if punctuationChars.contains(ch) {
            spans.append(CodeSyntaxHighlightSpan(start: i, end: i + 1, kind: .punctuation))
            i += 1
        } else {
            i += 1
        }
    }
    return spans
}

private let slashCommentLanguages: Set<String> = [
    "javascript",
    "typescript",
    "kotlin",
    "java",
    "c",
    "cpp",
    "csharp",
    "go",
    "rust",
    "php",
    "dart",
    "scala",
    "objectivec",
    "swift",
    "css"
]
private let blockCommentLanguages: Set<String> = slashCommentLanguages.union(["markup"])
private let dashCommentLanguages: Set<String> = ["sql", "lua"]
private let hashCommentLanguages: Set<String> = ["python", "shell", "yaml", "markdown", "ruby", "r", "php"]
private let propertyStringLanguages: Set<String> = ["json", "yaml"]
private let genericLanguages: Set<String> = [
    "javascript",
    "typescript",
    "kotlin",
    "java",
    "c",
    "cpp",
    "csharp",
    "go",
    "rust",
    "php",
    "ruby",
    "dart",
    "scala",
    "sql",
    "lua",
    "r",
    "objectivec",
    "swift",
    "python",
    "shell",
    "json",
    "yaml",
    "markup",
    "css",
    "markdown"
]
private let typedLanguages: Set<String> = [
    "javascript",
    "typescript",
    "kotlin",
    "java",
    "c",
    "cpp",
    "csharp",
    "go",
    "rust",
    "php",
    "ruby",
    "dart",
    "scala",
    "objectivec",
    "swift",
    "python"
]
private let operatorChars: Set<Character> = ["=", "+", "-", "*", "/", "%", "!", "<", ">", "&", "|", "?", ":"]
private let punctuationChars: Set<Character> = ["(", ")", "{", "}", "[", "]", ".", ",", ";"]
private let commonKeywords: Set<String> = ["true", "false", "null", "nil", "none"]
private let jsKeywords: Set<String> = [
    "await", "async", "break", "case", "catch", "class", "const", "continue", "default", "delete",
    "do", "else", "export", "extends", "finally", "for", "from", "function", "if", "import", "in",
    "instanceof", "let", "new", "of", "return", "switch", "this", "throw", "try", "typeof", "var",
    "void", "while", "yield", "interface", "type", "enum", "implements", "private", "protected", "public"
]
private let kotlinKeywords: Set<String> = [
    "as", "break", "class", "continue", "data", "do", "else", "false", "for", "fun", "if", "in", "interface",
    "is", "null", "object", "package", "private", "protected", "public", "return", "sealed", "super", "this",
    "throw", "true", "try", "typealias", "val", "var", "when", "while"
]
private let javaKeywords: Set<String> = [
    "abstract", "break", "case", "catch", "class", "const", "continue", "default", "do", "else", "enum",
    "extends", "final", "finally", "for", "if", "implements", "import", "instanceof", "interface", "new",
    "package", "private", "protected", "public", "return", "static", "super", "switch", "this", "throw",
    "throws", "try", "void", "while"
]
private let cKeywords: Set<String> = [
    "auto", "break", "case", "char", "const", "continue", "default", "do", "double", "else", "enum",
    "extern", "float", "for", "goto", "if", "inline", "int", "long", "register", "restrict", "return",
    "short", "signed", "sizeof", "static", "struct", "switch", "typedef", "union", "unsigned", "void",
    "volatile", "while"
]
private let cppKeywords: Set<String> = cKeywords.union([
    "alignas", "alignof", "and", "asm", "bitand", "bitor", "bool", "catch", "class", "concept", "const_cast",
    "constexpr", "decltype", "delete", "dynamic_cast", "explicit", "export", "false", "friend", "mutable",
    "namespace", "new", "noexcept", "not", "nullptr", "operator", "or", "private", "protected", "public",
    "reinterpret_cast", "requires", "static_assert", "static_cast", "template", "this", "thread_local",
    "throw", "true", "try", "typename", "using", "virtual", "xor"
])
private let goKeywords: Set<String> = [
    "break", "case", "chan", "const", "continue", "default", "defer", "else", "fallthrough", "for", "func",
    "go", "goto", "if", "import", "interface", "map", "package", "range", "return", "select", "struct",
    "switch", "type", "var"
]
private let rustKeywords: Set<String> = [
    "as", "async", "await", "break", "const", "continue", "crate", "dyn", "else", "enum", "extern", "false",
    "fn", "for", "if", "impl", "in", "let", "loop", "match", "mod", "move", "mut", "pub", "ref", "return",
    "self", "Self", "static", "struct", "super", "trait", "true", "type", "unsafe", "use", "where", "while"
]
private let csharpKeywords: Set<String> = [
    "abstract", "as", "base", "bool", "break", "case", "catch", "char", "checked", "class", "const",
    "continue", "decimal", "default", "delegate", "do", "double", "else", "enum", "event", "explicit",
    "extern", "false", "finally", "fixed", "float", "for", "foreach", "goto", "if", "implicit", "in",
    "int", "interface", "internal", "is", "lock", "long", "namespace", "new", "null", "object", "operator",
    "out", "override", "params", "private", "protected", "public", "readonly", "ref", "return", "sbyte",
    "sealed", "short", "sizeof", "stackalloc", "static", "string", "struct", "switch", "this", "throw",
    "true", "try", "typeof", "uint", "ulong", "unchecked", "unsafe", "ushort", "using", "virtual", "void",
    "volatile", "while", "async", "await", "var", "record"
]
private let phpKeywords: Set<String> = [
    "abstract", "and", "array", "as", "break", "callable", "case", "catch", "class", "clone", "const",
    "continue", "declare", "default", "die", "do", "echo", "else", "elseif", "empty", "enddeclare",
    "endfor", "endforeach", "endif", "endswitch", "endwhile", "eval", "exit", "extends", "final", "finally",
    "fn", "for", "foreach", "function", "global", "goto", "if", "implements", "include", "include_once",
    "instanceof", "insteadof", "interface", "isset", "list", "match", "namespace", "new", "or", "print",
    "private", "protected", "public", "readonly", "require", "require_once", "return", "static", "switch",
    "throw", "trait", "try", "unset", "use", "var", "while", "xor", "yield"
]
private let rubyKeywords: Set<String> = [
    "alias", "and", "begin", "break", "case", "class", "def", "defined", "do", "else", "elsif", "end",
    "ensure", "false", "for", "if", "in", "module", "next", "nil", "not", "or", "redo", "rescue", "retry",
    "return", "self", "super", "then", "true", "undef", "unless", "until", "when", "while", "yield"
]
private let dartKeywords: Set<String> = [
    "abstract", "as", "assert", "async", "await", "break", "case", "catch", "class", "const", "continue",
    "covariant", "default", "deferred", "do", "dynamic", "else", "enum", "export", "extends", "extension",
    "external", "factory", "false", "final", "finally", "for", "function", "get", "hide", "if", "implements",
    "import", "in", "interface", "is", "late", "library", "mixin", "new", "null", "on", "operator", "part",
    "required", "rethrow", "return", "set", "show", "static", "super", "switch", "sync", "this", "throw",
    "true", "try", "typedef", "var", "void", "while", "with", "yield"
]
private let scalaKeywords: Set<String> = [
    "abstract", "case", "catch", "class", "def", "do", "else", "enum", "export", "extends", "false", "final",
    "finally", "for", "forSome", "given", "if", "implicit", "import", "lazy", "match", "new", "null", "object",
    "override", "package", "private", "protected", "return", "sealed", "super", "then", "this", "throw",
    "trait", "true", "try", "type", "val", "var", "while", "with", "yield"
]
private let sqlKeywords: Set<String> = [
    "add", "all", "alter", "and", "as", "asc", "between", "by", "case", "create", "delete", "desc",
    "distinct", "drop", "else", "end", "exists", "false", "from", "group", "having", "in", "insert",
    "into", "is", "join", "left", "like", "limit", "not", "null", "on", "or", "order", "outer", "right",
    "select", "set", "table", "then", "true", "union", "update", "values", "when", "where"
]
private let luaKeywords: Set<String> = [
    "and", "break", "do", "else", "elseif", "end", "false", "for", "function", "goto", "if", "in", "local",
    "nil", "not", "or", "repeat", "return", "then", "true", "until", "while"
]
private let rKeywords: Set<String> = [
    "break", "else", "false", "for", "function", "if", "in", "inf", "na", "nan", "next", "null", "repeat",
    "return", "true", "while"
]
private let objectiveCKeywords: Set<String> = cKeywords.union([
    "@autoreleasepool", "@catch", "@class", "@dynamic", "@encode", "@end", "@finally", "@implementation",
    "@interface", "@optional", "@private", "@property", "@protected", "@protocol", "@public", "@required",
    "@selector", "@synthesize", "@throw", "@try", "id", "instancetype", "nil", "no", "self", "super", "yes"
])
private let swiftKeywords: Set<String> = [
    "actor", "as", "break", "case", "catch", "class", "continue", "default", "defer", "do", "else", "enum",
    "extension", "false", "for", "func", "guard", "if", "import", "in", "let", "nil", "private", "public",
    "return", "self", "struct", "super", "switch", "throw", "true", "try", "var", "while"
]
private let pythonKeywords: Set<String> = [
    "and", "as", "assert", "async", "await", "break", "class", "continue", "def", "elif", "else", "except",
    "false", "finally", "for", "from", "global", "if", "import", "in", "is", "lambda", "none", "not", "or",
    "pass", "raise", "return", "true", "try", "while", "with", "yield"
]
private let shellKeywords: Set<String> = [
    "case", "do", "done", "elif", "else", "esac", "export", "fi", "for", "function", "if", "in", "local",
    "then", "while"
]
private let markupKeywords: Set<String> = ["html", "head", "body", "div", "span", "script", "style", "template", "section"]
private let cssKeywords: Set<String> = ["@media", "@supports", "from", "to", "important"]
private let markdownKeywords: Set<String> = ["todo", "fixme", "note"]

private func classifyIdentifier(_ word: String, chars: [Character], end: Int, language: String) -> CodeSyntaxHighlighter.Kind? {
    let lower = word.lowercased()
    if CodeSyntaxHighlighter.literals.contains(word) { return .literal }
    if keywords(for: language).contains(lower) || (CodeSyntaxHighlighter.keywordSets[language]?.contains(word) ?? false) || commonKeywords.contains(lower) {
        return .keyword
    }
    if ["json", "yaml"].contains(language), nextNonWhitespace(chars, from: end) == ":" {
        return .property
    }
    if typedLanguages.contains(language), word.first?.isUppercase == true {
        return .type
    }
    if nextNonWhitespace(chars, from: end) == "(" {
        return .function
    }
    return nil
}

private func keywords(for language: String) -> Set<String> {
    switch language {
    case "javascript", "typescript": return jsKeywords
    case "kotlin": return kotlinKeywords
    case "java": return javaKeywords
    case "c": return cKeywords
    case "cpp": return cppKeywords
    case "csharp": return csharpKeywords
    case "go": return goKeywords
    case "rust": return rustKeywords
    case "php": return phpKeywords
    case "ruby": return rubyKeywords
    case "dart": return dartKeywords
    case "scala": return scalaKeywords
    case "sql": return sqlKeywords
    case "lua": return luaKeywords
    case "r": return rKeywords
    case "objectivec": return objectiveCKeywords
    case "swift": return swiftKeywords
    case "python": return pythonKeywords
    case "shell": return shellKeywords
    case "markup": return markupKeywords
    case "css": return cssKeywords
    case "markdown": return markdownKeywords
    default: return []
    }
}

private func quotedEnd(_ chars: [Character], start: Int, quote: Character) -> Int {
    var i = start + 1
    while i < chars.count {
        if chars[i] == "\\" {
            i += 2
        } else if chars[i] == quote {
            return i + 1
        } else {
            i += 1
        }
    }
    return chars.count
}

private func numberEnd(_ chars: [Character], start: Int) -> Int {
    var i = start
    if chars[i] == "-" {
        i += 1
    }
    while i < chars.count, chars[i].isNumber || chars[i] == "_" || chars[i] == "." {
        i += 1
    }
    if i < chars.count, String(chars[i]).lowercased() == "e" {
        i += 1
        if i < chars.count, chars[i] == "+" || chars[i] == "-" {
            i += 1
        }
        while i < chars.count, chars[i].isNumber {
            i += 1
        }
    }
    return i
}

private func identifierEnd(_ chars: [Character], start: Int) -> Int {
    var i = start + 1
    while i < chars.count, isIdentifierPart(chars[i]) {
        i += 1
    }
    return i
}

private func lineEnd(_ chars: [Character], from start: Int) -> Int {
    var i = start
    while i < chars.count && chars[i] != "\n" {
        i += 1
    }
    return i
}

private func endOfNeedle(_ needle: String, chars: [Character], from start: Int, includeNeedle: Bool) -> Int {
    var i = start
    while i < chars.count {
        if starts(with: needle, chars: chars, at: i) {
            return includeNeedle ? i + needle.count : i
        }
        i += 1
    }
    return chars.count
}

private func nextNonWhitespace(_ chars: [Character], from start: Int) -> Character? {
    var i = start
    while i < chars.count, chars[i].isWhitespace {
        i += 1
    }
    return i < chars.count ? chars[i] : nil
}

private func starts(with prefix: String, chars: [Character], at index: Int) -> Bool {
    let prefixChars = Array(prefix)
    guard index + prefixChars.count <= chars.count else { return false }
    for offset in 0..<prefixChars.count where chars[index + offset] != prefixChars[offset] {
        return false
    }
    return true
}

private func isIdentifierStart(_ ch: Character) -> Bool {
    ch == "_" || ch == "$" || ch == "@" || ch.isLetter
}

private func isIdentifierPart(_ ch: Character) -> Bool {
    ch == "_" || ch == "$" || ch.isLetter || ch.isNumber
}
