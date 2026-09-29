import XCTest
@testable import SmoothMarkdown

final class ReaderRemoteImagePolicyTests: XCTestCase {
    func testResponseAndStreamingByteLimits() {
        XCTAssertTrue(ReaderRemoteImagePolicy.acceptsContentLength(-1, svg: false))
        XCTAssertTrue(ReaderRemoteImagePolicy.acceptsContentLength(
            Int64(ReaderRemoteImagePolicy.maxBitmapBytes), svg: false))
        XCTAssertFalse(ReaderRemoteImagePolicy.acceptsContentLength(
            Int64(ReaderRemoteImagePolicy.maxBitmapBytes + 1), svg: false))
        XCTAssertFalse(ReaderRemoteImagePolicy.acceptsPayloadBytes(
            ReaderRemoteImagePolicy.maxSVGBytes + 1, svg: true))
    }

    func testPixelAndGroupBudgetsAvoidOverflow() {
        XCTAssertTrue(ReaderRemoteImagePolicy.acceptsPixelSize(width: 4_000, height: 3_000))
        XCTAssertFalse(ReaderRemoteImagePolicy.acceptsPixelSize(width: 8_193, height: 1))
        XCTAssertFalse(ReaderRemoteImagePolicy.acceptsPixelSize(width: Int.max, height: Int.max))
        XCTAssertTrue(ReaderRemoteImagePolicy.canRetain(pixels: 12_000_000, after: 12_000_000))
        XCTAssertFalse(ReaderRemoteImagePolicy.canRetain(pixels: 12_000_001, after: 12_000_000))
    }

    func testRedirectsAndRetryCooldown() {
        let secure = URL(string: "https://example.com/image.png")!
        XCTAssertTrue(ReaderRemoteImagePolicy.permitsRedirect(
            from: secure, to: URL(string: "https://cdn.example.com/image.png")!))
        XCTAssertFalse(ReaderRemoteImagePolicy.permitsRedirect(
            from: secure, to: URL(string: "http://cdn.example.com/image.png")!))
        XCTAssertFalse(ReaderRemoteImagePolicy.permitsRedirect(
            from: secure, to: URL(fileURLWithPath: "/tmp/image.png")))
        let now = Date(timeIntervalSince1970: 1_000)
        XCTAssertTrue(ReaderRemoteImagePolicy.shouldRetry(failedAt: nil, now: now))
        XCTAssertFalse(ReaderRemoteImagePolicy.shouldRetry(failedAt: now.addingTimeInterval(-14), now: now))
        XCTAssertTrue(ReaderRemoteImagePolicy.shouldRetry(failedAt: now.addingTimeInterval(-15), now: now))
    }
}
