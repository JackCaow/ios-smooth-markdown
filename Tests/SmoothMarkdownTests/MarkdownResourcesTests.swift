import XCTest
@testable import SmoothMarkdown

private actor CountingResourceLoader: MarkdownResourceLoader {
    private(set) var count = 0
    func load(_ request: MarkdownResourceRequest) async throws -> Data {
        count += 1
        return Data(request.headers["Authorization", default: "anonymous"].utf8)
    }
}
private struct WaitingResourceLoader: MarkdownResourceLoader {
    func load(_ request: MarkdownResourceRequest) async throws -> Data {
        try await Task.sleep(nanoseconds: 60_000_000_000)
        return Data()
    }
}
final class MarkdownResourcesTests: XCTestCase {
    func testDefaultNamespaceIsStableAndCredentialChangesInvalidate() {
        XCTAssertEqual(MarkdownResourceOptions().requestIdentity, MarkdownResourceOptions().requestIdentity)
        var options = MarkdownResourceOptions()
        let first = options.requestIdentity
        options.headers = ["Authorization": "different-account"]
        XCTAssertNotEqual(first, options.requestIdentity)
        var reload = options
        reload.cachePolicy = .reload
        XCTAssertEqual(options.cacheIdentity, reload.cacheIdentity)
        XCTAssertNotEqual(options.requestIdentity, reload.requestIdentity)
    }
    func testReplacingProviderAutomaticallyInvalidatesCacheNamespace() {
        var options = MarkdownResourceOptions()
        let original = options.cacheIdentity
        options.loader = CountingResourceLoader()
        let firstProvider = options.cacheIdentity
        XCTAssertNotEqual(original, firstProvider)
        options.loader = CountingResourceLoader()
        XCTAssertNotEqual(firstProvider, options.cacheIdentity)
        let customProvider = options.cacheIdentity
        options.loader = nil
        XCTAssertNotEqual(customProvider, options.cacheIdentity)
        XCTAssertEqual(MarkdownResourceOptions().cacheIdentity, MarkdownResourceOptions().cacheIdentity)
    }
    func testHeadersReachURLRequest() {
        let request = MarkdownResourceRequest(url: URL(string: "https://example.test/image.png")!, headers: ["Authorization": "test-only"])
        XCTAssertEqual(request.urlRequest.value(forHTTPHeaderField: "Authorization"), "test-only")
    }
    func testCacheReloadNoStoreAndAccountIsolation() async throws {
        let loader = CountingResourceLoader()
        let url = URL(string: "https://example.test/\(UUID().uuidString).png")!
        let identity = UUID().uuidString
        func load(_ policy: MarkdownResourceCachePolicy, header: String = "account-a") async throws -> Data {
            let request = MarkdownResourceRequest(url: url, headers: ["Authorization": header], cachePolicy: policy)
            return try await MarkdownResourceDataCache.shared.load(request, loader: loader, identity: identity + header)
        }
        _ = try await load(.default)
        _ = try await load(.default)
        var count = await loader.count
        XCTAssertEqual(count, 1)
        _ = try await load(.reload)
        _ = try await load(.default)
        count = await loader.count
        XCTAssertEqual(count, 2)
        _ = try await load(.noStore)
        _ = try await load(.noStore)
        count = await loader.count
        XCTAssertEqual(count, 4)
        let second = try await load(.default, header: "account-b")
        XCTAssertEqual(String(data: second, encoding: .utf8), "account-b")
        count = await loader.count
        XCTAssertEqual(count, 5)
    }
    func testSVGReferencedImagesUseHostLoaderAndInlineData() async throws {
        let loader = CountingResourceLoader()
        let markup = #"<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"><image href="photo.png" width="10" height="10"/></svg>"#
        let svg = try XCTUnwrap(SVG(data: Data(markup.utf8), baseURL: URL(string: "https://example.test/badge.svg")))
        let options = MarkdownResourceOptions(headers: ["Authorization": "account-svg"], loader: loader)
        let resolved = await SVGResourceResolver.resolve(svg, options: options)
        let data = try XCTUnwrap(resolved?.sourceData)
        let html = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(html.contains("data:image/png;base64,"))
        XCTAssertFalse(html.contains("photo.png"))
        let count = await loader.count
        XCTAssertEqual(count, 1)
    }
    func testCancellationIsPropagatedToCustomLoader() async {
        let task = Task {
            try await MarkdownResourceDataCache.shared.load(
                .init(url: URL(string: "https://example.test/cancel.png")!),
                loader: WaitingResourceLoader(), identity: UUID().uuidString)
        }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled request succeeded") }
        catch is CancellationError { }
        catch { XCTFail("Unexpected cancellation error: \(error)") }
    }
    func testLocalizedTemplatesPreserveLiteralAuthorValues() {
        var strings = MarkdownStrings()
        strings.overrides["Code language: {language}"] = "代码语言：{language} {missing}"
        XCTAssertEqual(strings.format("Code language: {language}", ["language": "custom {missing} %s"]), "代码语言：custom {missing} %s {missing}")
    }
    func testLocalizedLabelsAndAdditionalOverrides() {
        var strings = MarkdownStrings()
        strings.copy = "复制"
        strings.overrides = ["Save": "保存"]
        XCTAssertEqual(strings.copy, "复制")
        XCTAssertEqual(strings["Save"], "保存")
        XCTAssertEqual(strings["Unknown host label"], "Unknown host label")
    }
}
