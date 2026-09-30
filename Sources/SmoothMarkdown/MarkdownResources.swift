import Foundation
import SwiftUI

/// Default uses the bounded library memory cache, reload refreshes it, noStore bypasses it.
public enum MarkdownResourceCachePolicy: String, Sendable { case `default`, reload, noStore }

public struct MarkdownResourceRequest: Sendable {
    public let url: URL
    public let headers: [String: String]
    public let cachePolicy: MarkdownResourceCachePolicy
    public init(url: URL, headers: [String: String] = [:], cachePolicy: MarkdownResourceCachePolicy = .default) {
        self.url = url; self.headers = headers; self.cachePolicy = cachePolicy
    }
    public var urlRequest: URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        return request
    }
}

/// Supply encoded image bytes. Respect task cancellation; decoded content still receives library size checks.
public protocol MarkdownResourceLoader: Sendable {
    func load(_ request: MarkdownResourceRequest) async throws -> Data
}

/// Per-reader loading behavior. Replace this value to restart visible image requests after credentials change.
public struct MarkdownResourceOptions {
    public var headers: [String: String]
    public var cachePolicy: MarkdownResourceCachePolicy
    public var loader: (any MarkdownResourceLoader)? {
        didSet { identity = UUID() }
    }
    public var placeholder: ((URL, String) -> AnyView)?
    public var error: ((URL, String) -> AnyView)?
    /// Changing this identity explicitly invalidates visible results and isolates the in-memory cache.
    public var identity: UUID
    public init(headers: [String: String] = [:], cachePolicy: MarkdownResourceCachePolicy = .default,
                loader: (any MarkdownResourceLoader)? = nil,
                placeholder: ((URL, String) -> AnyView)? = nil,
                error: ((URL, String) -> AnyView)? = nil, identity: UUID? = nil) {
        self.headers = headers; self.cachePolicy = cachePolicy; self.loader = loader
        self.placeholder = placeholder; self.error = error
        self.identity = identity ?? (loader == nil ? Self.defaultIdentity : UUID())
    }
    private static let defaultIdentity = UUID(uuidString: "7A8029CE-FDDC-49C6-BC09-E35D72CDCC6F")!
    var cacheIdentity: String {
        identity.uuidString + headers.sorted { $0.key < $1.key }.map { Data($0.key.utf8).base64EncodedString() + ":" + Data($0.value.utf8).base64EncodedString() }.joined(separator: "|")
    }
    var requestIdentity: String { cacheIdentity + cachePolicy.rawValue }
}

private struct MarkdownResourcesKey: EnvironmentKey {
    static let defaultValue = MarkdownResourceOptions()
}
public extension EnvironmentValues {
    var markdownResources: MarkdownResourceOptions {
        get { self[MarkdownResourcesKey.self] }
        set { self[MarkdownResourcesKey.self] = newValue }
    }
}

/// Cancellation-aware, bounded system transport shared by both reader modes.
struct SystemMarkdownResourceLoader: MarkdownResourceLoader {
    func load(_ request: MarkdownResourceRequest) async throws -> Data {
        guard case .remote? = ImageSource.parse(request.url.absoluteString) else { throw URLError(.unsupportedURL) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpShouldSetCookies = false
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request.urlRequest,
            delegate: ResourceRedirectGuard(original: request.url))
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode),
              let finalURL = response.url,
              ReaderRemoteImagePolicy.permitsRedirect(from: request.url, to: finalURL) else { throw URLError(.badServerResponse) }
        let limit = ReaderRemoteImagePolicy.maxBitmapBytes
        guard response.expectedContentLength <= limit else { throw URLError(.dataLengthExceedsMaximum) }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < limit else { bytes.task.cancel(); throw URLError(.dataLengthExceedsMaximum) }
            data.append(byte)
        }
        return data
    }
}

private final class ResourceRedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let original: URL
    init(original: URL) { self.original = original }
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        guard let next = request.url, ReaderRemoteImagePolicy.permitsRedirect(from: original, to: next) else {
            completionHandler(nil); return
        }
        // Never forward credentials to a different origin.
        var redirected = request
        if next.host != original.host || next.port != original.port || next.scheme != original.scheme {
            redirected.allHTTPHeaderFields = [:]
        }
        completionHandler(redirected)
    }
}

actor MarkdownResourceDataCache {
    static let shared = MarkdownResourceDataCache()
    private var data: [String: Data] = [:]
    private var order: [String] = []
    private var bytes = 0
    func load(_ request: MarkdownResourceRequest, loader: (any MarkdownResourceLoader)?, identity: String) async throws -> Data {
        let key = identity + request.url.absoluteString
        if request.cachePolicy == .default, let cached = data[key] { return cached }
        let result = try await (loader ?? SystemMarkdownResourceLoader()).load(request)
        try Task.checkCancellation()
        guard result.count <= ReaderRemoteImagePolicy.maxBitmapBytes else { throw URLError(.dataLengthExceedsMaximum) }
        if request.cachePolicy != .noStore {
            if let previous = data.removeValue(forKey: key) { bytes -= previous.count }
            order.removeAll { $0 == key }
            data[key] = result; order.append(key); bytes += result.count
            while bytes > 32 * 1024 * 1024, !order.isEmpty {
                let oldest = order.removeFirst()
                if let removed = data.removeValue(forKey: oldest) { bytes -= removed.count }
            }
        }
        return result
    }
}
