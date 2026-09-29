import SwiftUI
import XCTest
@testable import SmoothMarkdown

#if os(iOS)
@MainActor
final class MarkdownTypographyTests: XCTestCase {
    func testSemanticReaderFontsFollowDynamicType() {
        let normal = MarkdownTypography.traits(for: .large)
        let accessible = MarkdownTypography.traits(for: .accessibility2)
        let normalBody = MarkdownTypography.font(forHeading: nil, weight: .regular,
                                                 customSize: nil, traits: normal)
        let largeBody = MarkdownTypography.font(forHeading: nil, weight: .regular,
                                                customSize: nil, traits: accessible)
        let normalTitle = MarkdownTypography.font(forHeading: 1, weight: .semibold,
                                                  customSize: nil, traits: normal)
        let largeTitle = MarkdownTypography.font(forHeading: 1, weight: .semibold,
                                                 customSize: nil, traits: accessible)
        XCTAssertEqual(normalBody.pointSize, UIFont.preferredFont(forTextStyle: .body,
                                                                   compatibleWith: normal).pointSize)
        XCTAssertGreaterThan(normalTitle.pointSize, normalBody.pointSize)
        XCTAssertGreaterThan(largeBody.pointSize, normalBody.pointSize)
        XCTAssertGreaterThan(largeTitle.pointSize, normalTitle.pointSize)
    }

    func testCustomInlineSizeScalesWithAccessibilityText() {
        let normal = MarkdownTypography.font(forHeading: nil, weight: .regular, customSize: 21,
                                             traits: MarkdownTypography.traits(for: .large))
        let accessible = MarkdownTypography.font(forHeading: nil, weight: .regular, customSize: 21,
                                                 traits: MarkdownTypography.traits(for: .accessibility2))
        XCTAssertEqual(normal.pointSize, 21, accuracy: 0.1)
        XCTAssertGreaterThan(accessible.pointSize, normal.pointSize)
    }

    func testSelectableChatUsesSameSemanticSizeAsSwiftUIStyle() {
        var style = MarkdownStyleSheet.light()
        style.paragraphFont = .subheadline
        style.readerParagraphTextStyle = .subheadline
        style.readerHeadingTextStyles = [.title2, .title3, .headline, .subheadline, .footnote, .caption]
        let source = "# Title\n\nMessage body"
        let document = ReaderSelectionDocument.compose(Array(MarkdownSyntax.parse(source).children),
                                                       enableHTML: false, plugins: nil)!
        let text = ReaderSelectionTextView(document: document, styleSheet: style,
                                           onLinkTap: nil, onTextLongPress: nil, selectable: true)
            .attributedContent(traits: MarkdownTypography.traits(for: .large)).text
        let messageRange = (text.string as NSString).range(of: "Message body")
        let titleRange = (text.string as NSString).range(of: "Title")
        let messageFont = text.attribute(.font, at: messageRange.location, effectiveRange: nil) as? UIFont
        let titleFont = text.attribute(.font, at: titleRange.location, effectiveRange: nil) as? UIFont
        XCTAssertEqual(messageFont?.pointSize, UIFont.preferredFont(forTextStyle: .subheadline).pointSize)
        XCTAssertEqual(titleFont?.pointSize, UIFont.preferredFont(forTextStyle: .title2).pointSize)
    }

    func testSelectableReaderReservesDecorationSpaceOnlyForFirstTwoHeadings() {
        let source = "# First\n\n## Second\n\n### Third\n\nBody"
        let document = ReaderSelectionDocument.compose(Array(MarkdownSyntax.parse(source).children),
                                                       enableHTML: false, plugins: nil)!
        let style = MarkdownStyleSheet.light()
        let built = ReaderSelectionTextView(document: document, styleSheet: style,
                                            onLinkTap: nil, onTextLongPress: nil, selectable: true)
            .attributedContent(traits: MarkdownTypography.traits(for: .large))
        XCTAssertEqual(built.headingRegions.count, 2)
        XCTAssertEqual(built.headingRegions.map {
            (built.text.string as NSString).substring(with: $0)
        }, ["First", "Second"])
        for title in ["First", "Second"] {
            let range = (built.text.string as NSString).range(of: title)
            let paragraph = built.text.attribute(.paragraphStyle, at: range.location,
                                                 effectiveRange: nil) as? NSParagraphStyle
            XCTAssertEqual(paragraph?.firstLineHeadIndent, 16)
            XCTAssertEqual(paragraph?.paragraphSpacingBefore, 8)
            XCTAssertEqual(paragraph?.paragraphSpacing, style.blockSpacing + 10)
        }
        let third = (built.text.string as NSString).range(of: "Third")
        let thirdParagraph = built.text.attribute(.paragraphStyle, at: third.location,
                                                  effectiveRange: nil) as? NSParagraphStyle
        XCTAssertEqual(thirdParagraph?.firstLineHeadIndent, 0)
        XCTAssertEqual(thirdParagraph?.paragraphSpacingBefore, 0)
    }
}
#endif
