import Foundation

enum NativeMarkdownHTMLBlock {
    enum End {
        case blank
        case marker(String, insensitive: Bool)

        func matches(_ line: String) -> Bool {
            switch self {
            case .blank: return line.allSatisfy { $0 == " " || $0 == "\t" }
            case let .marker(pattern, insensitive):
                return line.range(of: pattern, options: insensitive ? [.regularExpression, .caseInsensitive] : [.regularExpression]) != nil
            }
        }
    }

    static func end(for line: String, interruptingParagraph: Bool = false) -> End? {
        let body = String(line.drop(while: { $0 == " " }))
        guard line.count - body.count <= 3, body.hasPrefix("<") else { return nil }
        if body.range(of: #"^<(?:script|pre|style|textarea)(?:[ \t>]|$)"#,
                      options: [.regularExpression, .caseInsensitive]) != nil {
            return .marker(#"</(?:script|pre|style|textarea)>"#, insensitive: true)
        }
        if body.hasPrefix("<!--") { return .marker("-->", insensitive: false) }
        if body.hasPrefix("<?") { return .marker(#"\?>"#, insensitive: false) }
        if body.range(of: #"^<![A-Z]"#, options: .regularExpression) != nil {
            return .marker(">", insensitive: false)
        }
        if body.hasPrefix("<![CDATA[") { return .marker(#"\]\]>"#, insensitive: false) }
        let tags = "address|article|aside|base|basefont|blockquote|body|caption|center|col|colgroup|dd|details|dialog|dir|div|dl|dt|fieldset|figcaption|figure|footer|form|frame|frameset|h[1-6]|head|header|hr|html|iframe|legend|li|link|main|menu|menuitem|nav|noframes|ol|optgroup|option|p|param|search|section|summary|table|tbody|td|tfoot|th|thead|title|tr|track|ul"
        if body.range(of: "^</?(?:" + tags + #")(?:[ \t]|/?>|$)"#,
                      options: [.regularExpression, .caseInsensitive]) != nil { return .blank }
        guard !interruptingParagraph, body.range(of: #"^</?[A-Za-z]"#, options: .regularExpression) != nil,
              let length = NativeMarkdownInlineHTML.length(in: Array(body), at: 0),
              body.dropFirst(length).allSatisfy({ $0 == " " || $0 == "\t" }) else { return nil }
        return .blank
    }
}
