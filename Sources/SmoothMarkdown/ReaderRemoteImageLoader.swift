#if os(iOS)
import Foundation
import ImageIO
import UIKit

struct ReaderRemoteImageKey: Hashable, Sendable {
    let url: URL
    let svg: Bool
}

enum ReaderRemoteImageResolution: @unchecked Sendable {
    case svg(SVG)
    case bitmap(UIImage)
    case failure
    case rejected

    var naturalSize: CGSize? {
        switch self {
        case let .svg(image): image.size
        case let .bitmap(image): image.size
        case .failure, .rejected: nil
        }
    }

    var pixelCost: Int {
        switch self {
        case let .svg(image):
            return Int(ceil(image.size.width)) * Int(ceil(image.size.height))
        case let .bitmap(image):
            guard let image = image.cgImage else { return 0 }
            return image.width * image.height
        case .failure, .rejected: return 0
        }
    }

    static func decode(_ data: Data?, key: ReaderRemoteImageKey) -> Self {
        guard let data else { return .failure }
        guard ReaderRemoteImagePolicy.acceptsPayloadBytes(data.count, svg: key.svg) else { return .rejected }
        if data.count <= ReaderRemoteImagePolicy.maxSVGBytes,
           let image = SVG(data: data, baseURL: key.url) {
            let size = image.size
            guard size.width.isFinite, size.height.isFinite,
                  size.width > 0, size.height > 0,
                  size.width <= CGFloat(ReaderRemoteImagePolicy.maxPixelSide),
                  size.height <= CGFloat(ReaderRemoteImagePolicy.maxPixelSide),
                  ReaderRemoteImagePolicy.acceptsPixelSize(
                    width: Int(ceil(size.width)), height: Int(ceil(size.height))) else { return .rejected }
            return .svg(image)
        }
        if key.svg { return .failure }
        let options: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithData(data as CFData, options as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as NSDictionary?,
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return .failure }
        guard ReaderRemoteImagePolicy.acceptsPixelSize(width: width, height: height) else { return .rejected }
        guard let image = UIImage(data: data) else { return .failure }
        return .bitmap(image)
    }
}

enum ReaderRemoteImageFetchResult: Sendable {
    case data(Data)
    case failure
    case rejected
}

enum ReaderRemoteImageLoader {
    static func fetch(_ key: ReaderRemoteImageKey, options: MarkdownResourceOptions = .init()) async -> ReaderRemoteImageFetchResult {
        guard case .remote? = ImageSource.parse(key.url.absoluteString) else { return .rejected }
        do {
            let request = MarkdownResourceRequest(url: key.url, headers: options.headers, cachePolicy: options.cachePolicy)
            let data = try await MarkdownResourceDataCache.shared.load(request, loader: options.loader, identity: options.cacheIdentity)
            guard ReaderRemoteImagePolicy.acceptsPayloadBytes(data.count, svg: key.svg) else { return .rejected }
            return .data(data)
        } catch { return .failure }
    }
}
#endif
