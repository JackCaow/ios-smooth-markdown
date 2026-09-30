import Foundation

enum NativeMarkdownReferenceParser {
    struct Definition {
        let label: String
        let destination: String
        let title: String?
        let lineCount: Int
    }

    static func parse(_ source: String) -> Definition? {
        let chars = Array(source)
        var cursor = 0
        func horizontal(_ character: Character) -> Bool { character == " " || character == "\t" }
        func lineCount(through end: Int) -> Int { chars[..<end].filter { $0 == "\n" }.count + 1 }
        while cursor < chars.count, chars[cursor] == " " { cursor += 1 }
        guard cursor <= 3, cursor < chars.count, chars[cursor] == "[" else { return nil }
        cursor += 1
        let labelStart = cursor
        while cursor < chars.count, chars[cursor] != "]" {
            if chars[cursor] == "\\", cursor + 1 < chars.count {
                cursor += 2; continue
            }
            if chars[cursor] == "[" || (chars[cursor] == "\n" &&
                chars[(cursor + 1)...].drop(while: horizontal).first == "\n") { return nil }
            cursor += 1
        }
        guard cursor < chars.count, cursor - labelStart <= 999, cursor > labelStart else { return nil }
        let label = String(chars[labelStart..<cursor])
        guard !label.allSatisfy(\.isWhitespace) else { return nil }
        cursor += 1
        guard cursor < chars.count, chars[cursor] == ":" else { return nil }
        cursor += 1
        var lineEndings = 0
        while cursor < chars.count, horizontal(chars[cursor]) || chars[cursor] == "\n" {
            if chars[cursor] == "\n" { lineEndings += 1 }
            if lineEndings > 1 { return nil }
            cursor += 1
        }
        guard cursor < chars.count else { return nil }
        let destinationStart: Int
        let destinationEnd: Int
        if chars[cursor] == "<" {
            cursor += 1
            destinationStart = cursor
            while cursor < chars.count, chars[cursor] != ">" {
                if chars[cursor] == "<" || chars[cursor] == "\n" { return nil }
                if chars[cursor] == "\\", cursor + 1 < chars.count, chars[cursor + 1] != "\n" {
                    cursor += 2
                } else { cursor += 1 }
            }
            guard cursor < chars.count else { return nil }
            destinationEnd = cursor
            cursor += 1
        } else {
            destinationStart = cursor
            var depth = 0
            while cursor < chars.count, !horizontal(chars[cursor]), chars[cursor] != "\n" {
                let character = chars[cursor]
                if character == "<" || character == ">" || character.unicodeScalars.contains(where: { $0.value < 0x20 }) { return nil }
                if character == "\\", cursor + 1 < chars.count, chars[cursor + 1] != "\n" {
                    cursor += 2; continue
                }
                if character == "(" { depth += 1 }
                if character == ")" { depth -= 1 }
                if depth < 0 || depth > 32 { return nil }
                cursor += 1
            }
            guard cursor > destinationStart, depth == 0 else { return nil }
            destinationEnd = cursor
        }
        let destination = NativeMarkdownTextDecoder.decode(String(chars[destinationStart..<destinationEnd]))
        let separator = cursor
        while cursor < chars.count, horizontal(chars[cursor]) { cursor += 1 }
        let destinationLineEnd = cursor
        let titleOnNextLine = cursor < chars.count && chars[cursor] == "\n"
        if titleOnNextLine {
            cursor += 1
            while cursor < chars.count, horizontal(chars[cursor]) { cursor += 1 }
        }
        func withoutTitle() -> Definition? {
            guard destinationLineEnd == chars.count || chars[destinationLineEnd] == "\n" else { return nil }
            return .init(label: label, destination: destination, title: nil,
                         lineCount: lineCount(through: destinationLineEnd))
        }
        guard cursor < chars.count, cursor > separator,
              chars[cursor] == "\"" || chars[cursor] == "'" || chars[cursor] == "(" else {
            return withoutTitle()
        }
        let opening = chars[cursor]
        let closing: Character = opening == "(" ? ")" : opening
        cursor += 1
        let titleStart = cursor
        var newline = false
        while cursor < chars.count, chars[cursor] != closing {
            if chars[cursor] == "\\", cursor + 1 < chars.count {
                cursor += 2; newline = false; continue
            }
            if opening == "(", chars[cursor] == "(" { return titleOnNextLine ? withoutTitle() : nil }
            if chars[cursor] == "\n" {
                if newline { return titleOnNextLine ? withoutTitle() : nil }
                newline = true
            } else if !horizontal(chars[cursor]) { newline = false }
            cursor += 1
        }
        guard cursor < chars.count else { return titleOnNextLine ? withoutTitle() : nil }
        let title = NativeMarkdownTextDecoder.decode(String(chars[titleStart..<cursor]))
        cursor += 1
        while cursor < chars.count, horizontal(chars[cursor]) { cursor += 1 }
        guard cursor == chars.count || chars[cursor] == "\n" else { return titleOnNextLine ? withoutTitle() : nil }
        return .init(label: label, destination: destination, title: title, lineCount: lineCount(through: cursor))
    }
}
