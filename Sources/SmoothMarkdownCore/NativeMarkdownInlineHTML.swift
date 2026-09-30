import Foundation

public enum NativeMarkdownInlineHTML {
    private static let whitespace = #"[ \t\r\n]"#
    private static let name = #"[A-Za-z_:][A-Za-z0-9_.:-]*"#
    private static let value = #"(?:"[^"]*"|'[^']*'|[^ \t\r\n"'=<>`]+)"#
    private static let attribute = whitespace + "+" + name + "(?:" + whitespace + "*=" + whitespace + "*" + value + ")?"
    private static let pattern = "^(?:<[A-Za-z][A-Za-z0-9-]*(?:" + attribute + ")*" + whitespace + "*/?>|</[A-Za-z][A-Za-z0-9-]*" + whitespace + "*>|<!--(?:>|->|[\\s\\S]*?-->)|<\\?[\\s\\S]*?\\?>|<![A-Z]+" + whitespace + "+[^>]*>|<!\\[CDATA\\[[\\s\\S]*?\\]\\]>)"
    private static let expression = try! NSRegularExpression(pattern: pattern)

    public static func length(in characters: [Character], at start: Int) -> Int? {
        guard characters.indices.contains(start), characters[start] == "<" else { return nil }
        let suffix = String(characters[start...]) as NSString
        guard let match = expression.firstMatch(in: suffix as String,
                                                range: NSRange(location: 0, length: suffix.length)) else { return nil }
        return suffix.substring(with: match.range).count
    }
}
