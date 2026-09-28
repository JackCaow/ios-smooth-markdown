import Foundation

/// Chooses the native bitmap or SVG path without allowing unsafe URL schemes.
enum ImageSource: Equatable {
    case remote(URL, svg: Bool)
    case bundled(String, svg: Bool)

    static func parse(_ source: String) -> ImageSource? {
        guard SafeHTML.isSafeImageSource(source) else { return nil }
        let svg = source.lowercased().hasSuffix(".svg")
        if let url = URL(string: source), let scheme = url.scheme?.lowercased() {
            guard scheme == "http" || scheme == "https", url.host != nil else { return nil }
            return .remote(url, svg: svg)
        }
        guard !source.hasPrefix("/"), !source.contains(".."),
              !source.contains(":"), !source.contains("\\") else { return nil }
        return .bundled(source, svg: svg)
    }
}
