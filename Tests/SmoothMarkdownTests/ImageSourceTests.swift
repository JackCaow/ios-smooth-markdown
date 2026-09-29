import Markdown
import SwiftDraw
import XCTest
@testable import SmoothMarkdown

final class ImageSourceTests: XCTestCase {
    func testRemoteAndBundledSVGsTakeVectorPath() {
        XCTAssertEqual(ImageSource.parse("https://example.com/logo.svg"),
                       .remote(URL(string: "https://example.com/logo.svg")!, svg: true))
        XCTAssertEqual(ImageSource.parse("https://example.com/photo.png"),
                       .remote(URL(string: "https://example.com/photo.png")!, svg: false))
        XCTAssertEqual(ImageSource.parse("Assets/mark.SVG"), .bundled("Assets/mark.SVG", svg: true))
        XCTAssertEqual(ImageSource.parse("icon.png"), .bundled("icon.png", svg: false))
    }

    func testUnsafeImageSourcesNeverReachSVGLoader() {
        XCTAssertNil(ImageSource.parse("javascript:alert(1).svg"))
        XCTAssertNil(ImageSource.parse("data:image/svg+xml,<svg/>"))
        XCTAssertNil(ImageSource.parse("file:///etc/private.svg"))
        XCTAssertNil(ImageSource.parse("../secret.svg"))
        XCTAssertNil(ImageSource.parse("//example.com/mark.svg"))
        XCTAssertNil(ImageSource.parse("https://"))
    }

    func testRemoteFailurePresentationKeepsUnsafeSourcesSeparateFromNetworkErrors() {
        XCTAssertEqual(ImageSource.parse("https://example.com/broken.png")?.remoteFailurePresentation,
                       .bitmapErrorIcon)
        XCTAssertEqual(ImageSource.parse("https://example.com/broken.svg")?.remoteFailurePresentation,
                       .svgAltText)
        XCTAssertNil(ImageSource.parse("javascript:alert(1).png")?.remoteFailurePresentation)
        XCTAssertNil(ImageSource.parse("icon.png")?.remoteFailurePresentation)
    }

    func testBundledSVGParsesWithNativeRenderer() {
        let svg = SVG(named: "vector.svg", in: .module)
        XCTAssertEqual(svg?.size.width, 64)
        XCTAssertEqual(svg?.size.height, 32)
        XCTAssertNil(SVG(named: "missing.svg", in: .module))
    }

    func testMarkdownAndOptInHTMLImagesShareSVGPath() {
        let paragraph = MarkdownSyntax.parse("before ![vector](native-vector.svg) after").child(at: 0)!
        let markdownImage = InlineContent.runs(in: paragraph, enableHTML: false).compactMap { run -> SafeHTML.ImageSpec? in
            if case let .image(image) = run { return image }
            return nil
        }.first
        XCTAssertEqual(markdownImage?.source, "native-vector.svg")
        XCTAssertEqual((markdownImage?.source).flatMap(ImageSource.parse), .bundled("native-vector.svg", svg: true))

        let htmlImage = SafeHTML.imageTag("<img src='https://example.com/logo.svg' alt='logo' width='32'>")
        XCTAssertEqual(htmlImage?.width, 32)
        XCTAssertEqual((htmlImage?.source).flatMap(ImageSource.parse),
                       .remote(URL(string: "https://example.com/logo.svg")!, svg: true))
    }
}
