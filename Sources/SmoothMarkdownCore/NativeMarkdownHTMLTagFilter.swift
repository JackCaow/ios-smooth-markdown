import Foundation

/// GFM's tagfilter extension changes only the opening angle bracket of these tags.
/// This is independent of the reader's stricter HTML safety policy.
public enum NativeMarkdownHTMLTagFilter {
    public static func filter(_ html: String) -> String {
        let pattern = #"(?i)<(?=/?(?:title|textarea|style|xmp|iframe|noembed|noframes|script|plaintext)(?:[\t\n\r ]|/?>))"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return html }
        return expression.stringByReplacingMatches(in: html,
            range: NSRange(location: 0, length: (html as NSString).length), withTemplate: "&lt;")
    }
}
