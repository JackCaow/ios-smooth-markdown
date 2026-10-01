import Foundation

/// Inline referenced resources before WebKit sees them. Its CSP blocks any unhandled network access.
enum SVGResourceResolver {
    static func resolve(_ svg: SVG, options: MarkdownResourceOptions) async -> SVG? {
        guard let source = String(data: svg.sourceData, encoding: .utf8) else { return nil }
        let pattern = #"(?:href\s*=\s*["']([^"']+)["']|url\(\s*["']?([^)'"\s]+)["']?\s*\))"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let text = source as NSString
        var replacements: [String: String] = [:]
        var totalBytes = 0
        for match in regex.matches(in: source, range: NSRange(location: 0, length: text.length)) {
            let range = match.range(at: match.range(at: 1).location != NSNotFound ? 1 : 2)
            let value = text.substring(with: range)
            guard !value.hasPrefix("#"), !value.hasPrefix("data:"), replacements[value] == nil,
                  let url = URL(string: value, relativeTo: svg.baseURL)?.absoluteURL else { continue }
            guard !Task.isCancelled else { return nil }
            let data: Data?
            if url.isFileURL, let base = svg.baseURL, base.isFileURL,
               url.path.hasPrefix(base.deletingLastPathComponent().path + "/") {
                data = try? Data(contentsOf: url)
            } else if case .remote? = ImageSource.parse(url.absoluteString) {
                let request = MarkdownResourceRequest(url: url, headers: options.headers, cachePolicy: options.cachePolicy)
                data = try? await MarkdownResourceDataCache.shared.load(request, loader: options.loader, identity: options.cacheIdentity)
            } else { data = nil }
            guard let data, data.count <= 2 * 1024 * 1024, replacements.count < 32, totalBytes + data.count <= 8 * 1024 * 1024 else { replacements[value] = "data:,"; continue }
            totalBytes += data.count
            let mime: String = switch url.pathExtension.lowercased() {
            case "svg": "image/svg+xml"
            case "woff2": "font/woff2"
            case "woff": "font/woff"
            case "ttf": "font/ttf"
            case "otf": "font/otf"
            case "jpg", "jpeg": "image/jpeg"
            case "gif": "image/gif"
            case "webp": "image/webp"
            default: "image/png"
            }
            replacements[value] = "data:\(mime);base64,\(data.base64EncodedString())"
        }
        var resolved = source
        for (original, inline) in replacements { resolved = resolved.replacingOccurrences(of: original, with: inline) }
        return SVG(data: Data(resolved.utf8), baseURL: svg.baseURL)
    }
}
