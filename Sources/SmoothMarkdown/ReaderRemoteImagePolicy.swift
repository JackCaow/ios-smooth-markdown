import Foundation

/// Bounds the extra remote-image work done for one native selection group.
/// Oversized or unsupported groups keep the existing block-range renderer.
enum ReaderRemoteImagePolicy {
    static let maxConcurrentRequests = 2
    static let maxRemoteImages = 8
    static let maxBitmapBytes = 8 * 1024 * 1024
    static let maxSVGBytes = 2 * 1024 * 1024
    static let maxPixelsPerImage = 12_000_000
    static let maxTotalPixels = 24_000_000
    static let maxPixelSide = 8_192
    static let retryDelay: TimeInterval = 15

    static func maxBytes(svg: Bool) -> Int { svg ? maxSVGBytes : maxBitmapBytes }

    static func acceptsContentLength(_ length: Int64, svg: Bool) -> Bool {
        length < 0 || length <= maxBytes(svg: svg)
    }

    static func acceptsPayloadBytes(_ count: Int, svg: Bool) -> Bool {
        count >= 0 && count <= maxBytes(svg: svg)
    }

    static func acceptsPixelSize(width: Int, height: Int) -> Bool {
        width > 0 && height > 0 && width <= maxPixelSide && height <= maxPixelSide &&
            width <= maxPixelsPerImage / height
    }

    static func canRetain(pixels: Int, after current: Int) -> Bool {
        pixels >= 0 && current >= 0 && current <= maxTotalPixels &&
            pixels <= maxTotalPixels - current
    }

    static func shouldRetry(failedAt: Date?, now: Date) -> Bool {
        guard let failedAt else { return true }
        return now.timeIntervalSince(failedAt) >= retryDelay
    }

    static func permitsRedirect(from original: URL, to next: URL) -> Bool {
        guard case .remote? = ImageSource.parse(original.absoluteString),
              case .remote? = ImageSource.parse(next.absoluteString) else { return false }
        return original.scheme?.lowercased() != "https" || next.scheme?.lowercased() == "https"
    }
}
