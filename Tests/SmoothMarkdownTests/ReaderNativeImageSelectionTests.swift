#if os(iOS)
import UIKit
import XCTest
@testable import SmoothMarkdown

final class ReaderNativeImageSelectionTests: XCTestCase {
    func testRemoteImageDecodingProvidesNaturalSizeAndRejectsBadData() {
        let svgKey = ReaderRemoteImageKey(url: URL(string: "https://example.com/vector.svg")!, svg: true)
        let svg = Data("<svg xmlns='http://www.w3.org/2000/svg' width='64' height='32'></svg>".utf8)
        XCTAssertEqual(ReaderRemoteImageResolution.decode(svg, key: svgKey).naturalSize,
                       CGSize(width: 64, height: 32))
        let extensionlessKey = ReaderRemoteImageKey(
            url: URL(string: "https://img.shields.io/github/stars/owner/repo?style=flat")!, svg: false)
        if case let .svg(decoded) = ReaderRemoteImageResolution.decode(svg, key: extensionlessKey) {
            XCTAssertEqual(decoded.size, CGSize(width: 64, height: 32))
            XCTAssertEqual(decoded.baseURL, extensionlessKey.url)
        } else { XCTFail("An extensionless SVG response must use the vector renderer") }
        if case .failure = ReaderRemoteImageResolution.decode(Data("broken".utf8), key: svgKey) {
            // Malformed bytes are retryable after the view reappears.
        } else { XCTFail("Malformed SVG should be a retryable failure") }
        if case .rejected = ReaderRemoteImageResolution.decode(
            Data(count: ReaderRemoteImagePolicy.maxSVGBytes + 1), key: svgKey) {
            // Oversized payloads are rejected before SVG parsing.
        } else { XCTFail("Oversized SVG must be rejected") }

        let bitmapKey = ReaderRemoteImageKey(url: URL(string: "https://example.com/photo.png")!, svg: false)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let bitmap = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 10), format: format).pngData { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 20, height: 10))
        }
        XCTAssertEqual(ReaderRemoteImageResolution.decode(bitmap, key: bitmapKey).naturalSize,
                       CGSize(width: 20, height: 10))
        if case .bitmap = ReaderRemoteImageResolution.decode(bitmap, key: extensionlessKey) {
            // The response bytes, rather than a missing suffix, choose the bitmap decoder.
        } else { XCTFail("An extensionless bitmap response must stay a bitmap") }
        if case .rejected = ReaderRemoteImageResolution.decode(
            Data(count: ReaderRemoteImagePolicy.maxBitmapBytes + 1), key: extensionlessKey) {
            // The bitmap byte limit is unchanged.
        } else { XCTFail("Oversized remote payload must be rejected") }
    }

    func testStyleRerenderKeepsNativeSelectionButDocumentReplacementClearsIt() {
        let source = "Before 😀\n█\nAfter"
        let anchor = (source as NSString).range(of: "█").location
        let range = (source as NSString).range(of: "😀\n█\nAfter")
        let view = ReaderNativeImageTextView(frame: .zero, textContainer: nil)
        view.isSelectable = true
        view.applyRenderedContent(NSAttributedString(string: source), imageAnchorsUTF16: [anchor])
        view.selectedRange = range

        let styled = NSAttributedString(string: source,
                                        attributes: [.font: UIFont.systemFont(ofSize: 24)])
        view.applyRenderedContent(styled, imageAnchorsUTF16: [anchor])
        XCTAssertEqual(view.selectedRange, range)

        view.applyRenderedContent(NSAttributedString(string: "Changed"), imageAnchorsUTF16: [])
        XCTAssertEqual(view.selectedRange, NSRange(location: 0, length: 0))
    }

    func testTextKitOneImageGlyphKeepsNativeRangeAndCopiesOnlyText() {
        let source = NSMutableAttributedString(string: "Before 🐈 image.\n")
        let anchor = source.length
        source.append(NSAttributedString(string: ReaderNativeImageTextView.imageAnchor,
                                         attributes: [.font: UIFont.systemFont(ofSize: 64),
                                                      .foregroundColor: UIColor.clear]))
        source.append(NSAttributedString(string: "\nAfter 😀 image."))

        let view = ReaderNativeImageTextView(frame: .zero, textContainer: nil)
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.attributedText = source
        view.frame = CGRect(x: 0, y: 0, width: 300, height: 200)
        view.layoutIfNeeded()
        let glyph = view.layoutManager.glyphIndexForCharacter(at: anchor)
        let frame = view.layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1),
                                                    in: view.textContainer)
        XCTAssertGreaterThan(frame.width, 0)
        XCTAssertGreaterThanOrEqual(frame.height, 64)
        XCTAssertEqual(ReaderNativeImageTextView.selectedCopyText(
            in: source, range: NSRange(location: 0, length: source.length), imageAnchorsUTF16: [anchor]),
                       "Before 🐈 image.\nAfter 😀 image.")
        let tail = (source.string as NSString).range(of: "After")
        XCTAssertEqual(ReaderNativeImageTextView.selectedCopyText(
            in: source, range: tail, imageAnchorsUTF16: [anchor]), "After")

        let inlineCode = NSMutableAttributedString(string: "var\u{00A0}x\n")
        inlineCode.addAttribute(NSAttributedString.Key("SmoothMarkdownCodeSpace"), value: true,
                                range: NSRange(location: 3, length: 1))
        let codeAnchor = inlineCode.length
        inlineCode.append(NSAttributedString(string: ReaderNativeImageTextView.imageAnchor))
        inlineCode.append(NSAttributedString(string: "\nresult"))
        XCTAssertEqual(ReaderNativeImageTextView.selectedCopyText(
            in: inlineCode, range: NSRange(location: 0, length: inlineCode.length),
            imageAnchorsUTF16: [codeAnchor]), "var x\nresult")
    }
}
#endif
