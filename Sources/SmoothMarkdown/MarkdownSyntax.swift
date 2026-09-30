import Foundation

enum MarkdownSyntax {
    static func parse(_ source: String, useCache: Bool = true, enableHTML: Bool = false) -> Document {
        if useCache { return MarkdownParseCache.shared.parse(source, enableHTML: enableHTML) }
        let document = Document(parsing: source)
        return enableHTML ? HTMLCodeLiteralSyntax.restore(document, source: source) : document
    }

    static func isSafeLink(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return ["http", "https", "mailto", "tel"].contains(scheme)
    }

    static func isSafeImage(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return ["http", "https"].contains(scheme)
    }
}
