import SwiftUI

enum CodeSyntaxHighlighter {
    enum Kind: Equatable {
        case plain, keyword, string, comment, number, literal
    }

    struct Token: Equatable {
        let text: String
        let kind: Kind
    }

    private static let keywordSets: [String: Set<String>] = [
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
    private static let literals: Set<String> = ["true", "false", "null", "nil", "None", "True", "False", "undefined"]

    static func normalizedLanguage(_ language: String?) -> String? {
        guard let language = language?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !language.isEmpty else { return nil }
        switch language {
        case "js", "jsx": return "javascript"
        case "ts", "tsx": return "typescript"
        case "py": return "python"
        case "sh", "bash", "zsh": return "shell"
        case "kt", "kts": return "kotlin"
        default: return language
        }
    }

    static func tokenize(_ code: String, language: String?) -> [Token] {
        guard let language = normalizedLanguage(language), let keywords = keywordSets[language] else {
            return [.init(text: code, kind: .plain)]
        }
        let characters = Array(code)
        var tokens: [Token] = []
        var index = 0
        func append(_ text: String, _ kind: Kind) {
            guard !text.isEmpty else { return }
            if kind == .plain, let last = tokens.last, last.kind == .plain {
                tokens[tokens.count - 1] = .init(text: last.text + text, kind: .plain)
            } else {
                tokens.append(.init(text: text, kind: kind))
            }
        }
        while index < characters.count {
            let start = index
            let current = characters[index]
            let next = index + 1 < characters.count ? characters[index + 1] : nil
            if (current == "/" && next == "/" && language != "json") ||
                (current == "#" && ["python", "shell"].contains(language)) {
                while index < characters.count && characters[index] != "\n" { index += 1 }
                append(String(characters[start..<index]), .comment)
            } else if current == "/", next == "*", ["swift", "kotlin", "java", "dart", "javascript", "typescript"].contains(language) {
                index += 2
                while index + 1 < characters.count && !(characters[index] == "*" && characters[index + 1] == "/") { index += 1 }
                index = min(characters.count, index + 2)
                append(String(characters[start..<index]), .comment)
            } else if current == "\"" || current == "'" || (current == "`" && ["javascript", "typescript"].contains(language)) {
                index += 1
                while index < characters.count {
                    if characters[index] == "\\" { index = min(characters.count, index + 2); continue }
                    if characters[index] == current { index += 1; break }
                    index += 1
                }
                append(String(characters[start..<index]), .string)
            } else if current.isNumber {
                index += 1
                while index < characters.count && (characters[index].isNumber || characters[index] == "." || characters[index] == "_") { index += 1 }
                append(String(characters[start..<index]), .number)
            } else if current.isLetter || current == "_" {
                index += 1
                while index < characters.count && (characters[index].isLetter || characters[index].isNumber || characters[index] == "_") { index += 1 }
                let word = String(characters[start..<index])
                append(word, literals.contains(word) ? .literal : (keywords.contains(word) ? .keyword : .plain))
            } else {
                index += 1
                append(String(current), .plain)
            }
        }
        return tokens
    }

    static func attributed(_ code: String, language: String?, dark: Bool, enabled: Bool) -> AttributedString {
        guard enabled else { return AttributedString(code) }
        var result = AttributedString()
        for token in tokenize(code, language: language) {
            var fragment = AttributedString(token.text)
            switch token.kind {
            case .plain: break
            case .keyword: fragment.foregroundColor = dark ? Color(red: 0.78, green: 0.56, blue: 1) : Color(red: 0.53, green: 0.21, blue: 0.73)
            case .string: fragment.foregroundColor = dark ? Color(red: 0.95, green: 0.62, blue: 0.55) : Color(red: 0.65, green: 0.16, blue: 0.19)
            case .comment: fragment.foregroundColor = dark ? Color(red: 0.54, green: 0.69, blue: 0.58) : Color(red: 0.26, green: 0.48, blue: 0.29)
            case .number: fragment.foregroundColor = dark ? Color(red: 0.55, green: 0.75, blue: 1) : Color(red: 0.16, green: 0.38, blue: 0.69)
            case .literal: fragment.foregroundColor = dark ? Color(red: 0.43, green: 0.82, blue: 0.82) : Color(red: 0.07, green: 0.49, blue: 0.52)
            }
            result += fragment
        }
        return result
    }
}
