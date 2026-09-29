import SwiftUI
import XCTest
@testable import SmoothMarkdown

@MainActor
final class BlockquoteStyleTests: XCTestCase {
    func testDecorationAndFourSidedPaddingOverrideLegacyQuoteStyle() {
        let style = MarkdownStyleSheet(
            quoteBarColor: .blue,
            quoteBackground: .gray,
            blockquoteDecoration: MarkdownBlockquoteDecoration(
                backgroundColor: .red, borderColor: .green, borderWidth: 7),
            blockquotePadding: EdgeInsets(top: 2, leading: 4, bottom: 6, trailing: 8)
        )
        let resolved = style.resolvedBlockquoteDecoration
        XCTAssertEqual(resolved.borderWidth, 7)
        XCTAssertEqual(style.blockquotePadding.top, 2)
        XCTAssertEqual(style.blockquotePadding.leading, 4)
        XCTAssertEqual(style.blockquotePadding.bottom, 6)
        XCTAssertEqual(style.blockquotePadding.trailing, 8)
        #if os(iOS)
        XCTAssertEqual(UIColor(resolved.backgroundColor!), UIColor(.red))
        XCTAssertEqual(UIColor(resolved.borderColor!), UIColor(.green))
        #endif
    }

    func testLegacyQuoteColorsRemainEffectiveWithoutDecorationOverride() {
        let style = MarkdownStyleSheet(quoteBarColor: .blue, quoteBackground: .gray)
        let resolved = style.resolvedBlockquoteDecoration
        XCTAssertEqual(resolved.borderWidth, 4)
        #if os(iOS)
        XCTAssertEqual(UIColor(resolved.backgroundColor!), UIColor(.gray))
        XCTAssertEqual(UIColor(resolved.borderColor!), UIColor(.blue))
        #endif
    }

    #if os(iOS)
    func testOneQuoteRegionSpansMultipleRenderedParagraphs() {
        let view = QuoteTextView(frame: CGRect(x: 0, y: 0, width: 240, height: 240))
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        let text = "First paragraph\nSecond paragraph\nThird paragraph"
        view.attributedText = NSAttributedString(string: text, attributes: [
            .font: UIFont.systemFont(ofSize: 16),
        ])
        view.quoteRegions = [.init(range: NSRange(location: 0, length: (text as NSString).length), depth: 1)]
        view.layoutManager.ensureLayout(for: view.textContainer)
        let frames = view.quoteFrames()
        XCTAssertEqual(frames.count, 1)
        XCTAssertGreaterThan(frames[0].0.height, UIFont.systemFont(ofSize: 16).lineHeight * 2)
    }
    #endif
}
