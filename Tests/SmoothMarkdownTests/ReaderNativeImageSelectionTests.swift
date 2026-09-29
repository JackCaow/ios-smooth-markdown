#if os(iOS)
import UIKit
import XCTest
@testable import SmoothMarkdown

final class ReaderNativeImageSelectionTests: XCTestCase {
    func testStyleRerenderKeepsNativeSelectionButDocumentReplacementClearsIt() {
        let source = "Before 😀\n█\nAfter"
        let anchor = (source as NSString).range(of: "█").location
        let range = (source as NSString).range(of: "😀\n█\nAfter")
        let view = ReaderNativeImageTextView(usingTextLayoutManager: false)
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

        let view = ReaderNativeImageTextView(usingTextLayoutManager: false)
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
