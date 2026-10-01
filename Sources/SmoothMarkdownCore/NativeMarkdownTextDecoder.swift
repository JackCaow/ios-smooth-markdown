import Foundation

/// Decodes CommonMark text after its structural delimiters have been recognized.
public enum NativeMarkdownTextDecoder {
    private static let escapedPunctuation = CharacterSet(charactersIn:
        ##"!"#$%&'()*+,-./:;<=>?@[\]^_`{|}~"##)

    public static func decode(_ source: String) -> String {
        let characters = Array(source)
        var result = ""
        result.reserveCapacity(source.count)
        var index = 0
        while index < characters.count {
            if characters[index] == "\\", index + 1 < characters.count,
               let scalar = characters[index + 1].unicodeScalars.first,
               characters[index + 1].unicodeScalars.count == 1,
               escapedPunctuation.contains(scalar) {
                result.append(characters[index + 1])
                index += 2
                continue
            }
            if characters[index] == "&" {
                var end = index + 1
                while end < characters.count, end - index <= 33,
                      characters[end] != ";", !characters[end].isWhitespace { end += 1 }
                if end < characters.count, characters[end] == ";",
                   let entity = reference(String(characters[(index + 1)..<end])) {
                    result += entity
                    index = end + 1
                    continue
                }
            }
            result.append(characters[index])
            index += 1
        }
        return result
    }

    public static func codeSpan(_ source: String) -> String {
        let markerCount = source.prefix(while: { $0 == "`" }).count
        guard markerCount > 0, source.count >= markerCount * 2 else { return source }
        let inner = source.dropFirst(markerCount).dropLast(markerCount)
        let value = inner.replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        if value.count >= 2, value.first == " ", value.last == " ",
           value.contains(where: { $0 != " " }) {
            return String(value.dropFirst().dropLast())
        }
        return value
    }

    private static func reference(_ token: String) -> String? {
        guard token.hasPrefix("#") else { return NativeHTMLEntityTable.values[token] }
        let digits: Substring
        let radix: Int
        if token.hasPrefix("#x") || token.hasPrefix("#X") {
            digits = token.dropFirst(2)
            radix = 16
        } else {
            digits = token.dropFirst()
            radix = 10
        }
        guard !digits.isEmpty, digits.count <= (radix == 16 ? 6 : 7),
              digits.unicodeScalars.allSatisfy({ scalar in
            switch radix {
            case 16: return CharacterSet(charactersIn: "0123456789abcdefABCDEF").contains(scalar)
            default: return CharacterSet.decimalDigits.contains(scalar) && scalar.value < 128
            }
        }) else { return nil }
        let value = UInt32(digits, radix: radix) ?? 0xFFFD
        guard value != 0, !(0xD800...0xDFFF).contains(value),
              let scalar = Unicode.Scalar(value) else { return "\u{FFFD}" }
        return String(scalar)
    }
}
