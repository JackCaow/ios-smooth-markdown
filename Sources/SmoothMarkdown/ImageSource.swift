import Foundation

/// Chooses the native bitmap or SVG path without allowing unsafe URL schemes.
enum ImageSource: Equatable {
    case remote(URL, svg: Bool)
    case bundled(String, svg: Bool)

    enum RemoteFailurePresentation: Equatable {
        case bitmapErrorIcon
        case svgAltText
    }

    var remoteFailurePresentation: RemoteFailurePresentation? {
        guard case let .remote(_, svg) = self else { return nil }
        return svg ? .svgAltText : .bitmapErrorIcon
    }

    static func parse(_ source: String) -> ImageSource? {
        guard SafeHTML.isSafeImageSource(source) else { return nil }
        if let url = URL(string: source), let scheme = url.scheme?.lowercased() {
            guard scheme == "http" || scheme == "https", url.host != nil else { return nil }
            return .remote(url, svg: url.pathExtension.lowercased() == "svg")
        }
        let svg = source.lowercased().hasSuffix(".svg")
        guard !source.hasPrefix("/"), !source.contains(".."),
              !source.contains(":"), !source.contains("\\") else { return nil }
        return .bundled(source, svg: svg)
    }
}
