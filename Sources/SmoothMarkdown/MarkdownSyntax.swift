import Foundation
import Markdown

enum MarkdownSyntax {
    static func parse(_ source: String) -> Document {
        MarkdownParseCache.shared.parse(source)
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
