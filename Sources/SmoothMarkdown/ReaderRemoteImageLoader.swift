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
        if key.svg {
            guard let image = SVG(data: data, baseURL: key.url) else { return .failure }
            let size = image.size
            guard size.width.isFinite, size.height.isFinite,
                  size.width > 0, size.height > 0,
                  size.width <= CGFloat(ReaderRemoteImagePolicy.maxPixelSide),
                  size.height <= CGFloat(ReaderRemoteImagePolicy.maxPixelSide),
                  ReaderRemoteImagePolicy.acceptsPixelSize(
                    width: Int(ceil(size.width)), height: Int(ceil(size.height))) else { return .rejected }
            return .svg(image)
        }
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

private final class ReaderRemoteImageRedirectGuard: NSObject, URLSessionTaskDelegate {
    let original: URL

    init(original: URL) { self.original = original }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        guard let next = request.url,
              ReaderRemoteImagePolicy.permitsRedirect(from: original, to: next) else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}

enum ReaderRemoteImageLoader {
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpMaximumConnectionsPerHost = ReaderRemoteImagePolicy.maxConcurrentRequests
        configuration.httpShouldSetCookies = false
        return URLSession(configuration: configuration)
    }()

    static func fetch(_ key: ReaderRemoteImageKey) async -> ReaderRemoteImageFetchResult {
        guard case .remote? = ImageSource.parse(key.url.absoluteString) else { return .rejected }
        let request = URLRequest(url: key.url, cachePolicy: .reloadIgnoringLocalCacheData,
                                 timeoutInterval: 20)
        do {
            let (bytes, response) = try await session.bytes(
                for: request, delegate: ReaderRemoteImageRedirectGuard(original: key.url))
            guard let response = response as? HTTPURLResponse,
                  (200..<300).contains(response.statusCode),
                  let finalURL = response.url,
                  ReaderRemoteImagePolicy.permitsRedirect(from: key.url, to: finalURL) else {
                bytes.task.cancel()
                return .failure
            }
            guard ReaderRemoteImagePolicy.acceptsContentLength(
                response.expectedContentLength, svg: key.svg) else {
                bytes.task.cancel()
                return .rejected
            }
            let limit = ReaderRemoteImagePolicy.maxBytes(svg: key.svg)
            var data = Data()
            if response.expectedContentLength > 0 {
                data.reserveCapacity(min(limit, Int(response.expectedContentLength)))
            }
            for try await byte in bytes {
                if data.count >= limit {
                    bytes.task.cancel()
                    return .rejected
                }
                data.append(byte)
            }
            return .data(data)
        } catch {
            return .failure
        }
    }
}
#endif
