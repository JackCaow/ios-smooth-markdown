import Foundation
import XCTest
@testable import SmoothMarkdown

final class PublicAPICallbackParityTests: XCTestCase {
    func testReaderInvokesNativeAndFlutterStyleCallbacks() {
        var nativeLinks: [URL] = []
        var stringLinks: [String] = []
        var nativeImages: [String] = []
        var flutterImages: [String] = []
        let reader = SmoothMarkdownView(
            markdown: "[Link](https://example.com) ![Alt](asset.png)",
            onLinkTap: { nativeLinks.append($0) },
            onTapLink: { stringLinks.append($0) },
            onImageTapWithMetadata: { nativeImages.append("\($0)|\($1 ?? "")|\($2 ?? "")") },
            onTapImage: { flutterImages.append("\($0)|\($1 ?? "")|\($2 ?? "")") }
        )

        reader.onLinkTap?(URL(string: "https://example.com/path")!)
        reader.onImageTapWithMetadata?("asset.png", "Alt", nil)

        XCTAssertEqual(nativeLinks.map(\.absoluteString), ["https://example.com/path"])
        XCTAssertEqual(stringLinks, ["https://example.com/path"])
        XCTAssertEqual(nativeImages, ["asset.png|Alt|"])
        XCTAssertEqual(flutterImages, nativeImages)
    }

    func testStreamInvokesNativeAndFlutterStyleCallbacks() {
        var nativeLinks: [URL] = []
        var stringLinks: [String] = []
        let stream = StreamMarkdownView(
            chunks: AsyncStream<String> { continuation in continuation.finish() },
            onLinkTap: { nativeLinks.append($0) },
            onTapLink: { stringLinks.append($0) }
        )

        stream.onLinkTap?(URL(string: "https://example.com")!)

        XCTAssertEqual(nativeLinks.map(\.absoluteString), ["https://example.com"])
        XCTAssertEqual(stringLinks, ["https://example.com"])
    }
}
