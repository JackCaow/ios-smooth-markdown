import SwiftUI
import XCTest
@testable import SmoothMarkdown

#if os(iOS)
@MainActor
final class MarkdownTypographyTests: XCTestCase {

    func testSystemTokenFontsUseTheSuppliedEnvironmentTraitsForEachRole() {
        let normal = MarkdownTypography.traits(for: .large)
        let accessible = MarkdownTypography.traits(for: .accessibility3)
        for role: Font.TextStyle in [.body, .title, .footnote] {
            for monospaced in [false, true] {
                let token = MarkdownFontToken(size: 17, weight: .semibold, monospaced: monospaced)
                let uiNormal = token.uiFont(textStyle: role, traits: normal)
                let uiAccessible = token.uiFont(textStyle: role, traits: accessible)
                XCTAssertGreaterThan(uiAccessible.pointSize, uiNormal.pointSize)
                XCTAssertEqual(token.font(relativeTo: role, traits: normal), .system(size: uiNormal.pointSize, weight: .semibold, design: monospaced ? .monospaced : .default))
                XCTAssertEqual(token.font(relativeTo: role, traits: accessible), .system(size: uiAccessible.pointSize, weight: .semibold, design: monospaced ? .monospaced : .default))
                XCTAssertNotEqual(token.font(relativeTo: role, traits: normal), token.font(relativeTo: role, traits: accessible))
            }
        }
        let custom = MarkdownFontToken(fontName: "Helvetica", size: 17)
        XCTAssertEqual(custom.font(relativeTo: .body, traits: accessible), custom.font(relativeTo: .body))
    }

    func testPublicSwiftUIReaderSystemTokensRespectLocalDynamicTypeOverride() {
        var sheet = MarkdownStyleSheet.light()
        sheet.contentPadding = 0
        sheet.designTokens.typography.paragraph = .init(size: 17)
        sheet.designTokens.typography.headings = (0..<6).map { _ in .init(size: 22, weight: .semibold) }
        for source in ["Body", "# Heading"] {
            func height(_ size: DynamicTypeSize) -> CGFloat {
                let view = SmoothMarkdownView(markdown: source, styleSheet: sheet, selectable: false,
                    enableCrossBlockSelection: false, scrollable: false).environment(\.dynamicTypeSize, size)
                let host = UIHostingController(rootView: view)
                return host.sizeThatFits(in: CGSize(width: 1000, height: 1000)).height
            }
            XCTAssertGreaterThan(height(.accessibility3), height(.large) * 1.5, source)
        }
    }

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
                                           onLinkTap: nil, onTextLongPress: nil, selectable: true,
                                           onCharacterTap: nil)
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
                                            onLinkTap: nil, onTextLongPress: nil, selectable: true,
                                            onCharacterTap: nil, useEnhancedComponents: true)
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

    func testSelectableReaderKeepsOneTextKitLayoutForMeasurementAndDecorations() {
        let source = """
        # 🚀 完整 Markdown 功能展示

        欢迎来到 Flutter Smooth Markdown 的完整功能演示页面！

        ## 📝 我的建议 - 粗体标题

        标题现在支持所有行内格式，包括粗体、斜体、代码、链接等！
        """
        let document = ReaderSelectionDocument.compose(Array(MarkdownSyntax.parse(source).children),
                                                       enableHTML: false, plugins: nil)!
        let reader = ReaderSelectionTextView(document: document, styleSheet: .light(),
                                              onLinkTap: nil, onTextLongPress: nil,
                                              selectable: true, onCharacterTap: nil)
        // Exercise the same factory makeUIView uses without depending on when
        // UIHostingController attaches its SwiftUI subtree in CI.
        let native = ReaderSelectionTextView.makeTextView()
        native.attributedText = reader.attributedContent(traits: MarkdownTypography.traits(for: .large)).text
        native.frame = CGRect(x: 0, y: 0, width: 370, height: 900)
        XCTAssertNil(native.textLayoutManager, "TextKit 2 would be replaced after the first glyph geometry read")
        let before = native.sizeThatFits(CGSize(width: 370, height: CGFloat.greatestFiniteMagnitude)).height
        native.layoutManager.ensureLayout(for: native.textContainer)
        let after = native.sizeThatFits(CGSize(width: 370, height: CGFloat.greatestFiniteMagnitude)).height
        XCTAssertEqual(before, after, accuracy: 1)
        XCTAssertGreaterThanOrEqual(after + 1, native.layoutManager.usedRect(for: native.textContainer).maxY)
    }

    func testReaderLineHeightsAndInlineCodeWrappingFollowLightStyle() {
        let source = """
        # 🚀 完整 Markdown 功能展示

        This is a paragraph with `var x = 42;` inline code.
        """
        let document = ReaderSelectionDocument.compose(Array(MarkdownSyntax.parse(source).children),
                                                       enableHTML: false, plugins: nil)!
        let reader = ReaderSelectionTextView(document: document, styleSheet: .light(),
                                              onLinkTap: nil, onTextLongPress: nil,
                                              selectable: true, onCharacterTap: nil)
        let text = reader.attributedContent(traits: MarkdownTypography.traits(for: .large)).text
        let sourceText = text.string as NSString
        let titleRange = sourceText.range(of: "完整 Markdown")
        let bodyRange = sourceText.range(of: "This is a paragraph")
        let codeRange = sourceText.range(of: "var\u{00A0}x\u{00A0}=\u{00A0}42;")
        guard codeRange.location != NSNotFound else { return XCTFail("Inline code lost its source text") }
        let titleStyle = text.attribute(.paragraphStyle, at: titleRange.location,
                                        effectiveRange: nil) as? NSParagraphStyle
        let bodyStyle = text.attribute(.paragraphStyle, at: bodyRange.location,
                                       effectiveRange: nil) as? NSParagraphStyle
        let titleFont = text.attribute(.font, at: titleRange.location, effectiveRange: nil) as? UIFont
        let bodyFont = text.attribute(.font, at: bodyRange.location, effectiveRange: nil) as? UIFont
        let codeFont = text.attribute(.font, at: codeRange.location, effectiveRange: nil) as? UIFont
        XCTAssertEqual(titleStyle?.minimumLineHeight ?? 0, (titleFont?.pointSize ?? 0) * 1.3,
                       accuracy: 0.1)
        XCTAssertEqual(bodyStyle?.minimumLineHeight ?? 0, (bodyFont?.pointSize ?? 0) * 1.5,
                       accuracy: 0.1)
        XCTAssertEqual(titleStyle?.lineBreakStrategy, .pushOut)
        XCTAssertEqual(codeFont?.pointSize ?? 0, 14, accuracy: 0.1)
        XCTAssertEqual(QuoteTextView.transformedCopyText(in: text, ruleRegions: [], range: codeRange),
                       "var x = 42;")
        XCTAssertNil(QuoteTextView.transformedCopyText(in: text, ruleRegions: [], range: bodyRange))
    }
    func testPublicNamedFontAndLineHeightTokensReachSelectableReaderAndScale() throws {
        var style = MarkdownStyleSheet.light()
        style.designTokens.typography.paragraph = MarkdownFontToken(fontName: "Helvetica", size: 22)
        style.designTokens.typography.paragraphLineHeight = 1.8
        let document = try XCTUnwrap(ReaderSelectionDocument.compose(
            Array(MarkdownSyntax.parse("Custom body").children), enableHTML: false, plugins: nil))
        let reader = ReaderSelectionTextView(document: document, styleSheet: style,
            onLinkTap: nil, onTextLongPress: nil, selectable: true, onCharacterTap: nil)
        let normal = reader.attributedContent(traits: MarkdownTypography.traits(for: .large)).text
        let accessible = reader.attributedContent(traits: MarkdownTypography.traits(for: .accessibility2)).text
        let normalFont = try XCTUnwrap(normal.attribute(.font, at: 0, effectiveRange: nil) as? UIFont)
        let accessibleFont = try XCTUnwrap(accessible.attribute(.font, at: 0, effectiveRange: nil) as? UIFont)
        let normalParagraph = try XCTUnwrap(normal.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
        let accessibleParagraph = try XCTUnwrap(accessible.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
        XCTAssertEqual(normalFont.familyName, "Helvetica")
        XCTAssertEqual(normalFont.pointSize, 22, accuracy: 0.1)
        XCTAssertEqual(normalParagraph.minimumLineHeight, normalFont.pointSize * 1.8, accuracy: 0.1)
        XCTAssertGreaterThan(accessibleFont.pointSize, normalFont.pointSize)
        XCTAssertEqual(accessibleParagraph.minimumLineHeight, accessibleFont.pointSize * 1.8, accuracy: 0.1)
    }

    func testPluginColorsReachSelectableNativeTextWithoutChangingSource() throws {
        let plugins = ParserPluginRegistry()
        try plugins.register(MentionPlugin())
        try plugins.register(HashtagPlugin())
        let source = "Hello @alice #ios"
        let document = try XCTUnwrap(ReaderSelectionDocument.compose(
            Array(MarkdownSyntax.parse(source).children), enableHTML: false, plugins: plugins))
        var style = MarkdownStyleSheet.light()
        style.designTokens.plugins.mentionStyle = MarkdownInlineTextStyle(textColor: .purple)
        style.designTokens.plugins.hashtagStyle = MarkdownInlineTextStyle(textColor: .green, backgroundColor: .yellow)
        let text = ReaderSelectionTextView(document: document, styleSheet: style,
            onLinkTap: nil, onTextLongPress: nil, selectable: true, onCharacterTap: nil)
            .attributedContent(traits: MarkdownTypography.traits(for: .large)).text
        let mention = (text.string as NSString).range(of: "@alice")
        let hashtag = (text.string as NSString).range(of: "#ios")
        XCTAssertNotEqual(mention.location, NSNotFound)
        XCTAssertNotEqual(hashtag.location, NSNotFound)
        guard mention.location != NSNotFound, hashtag.location != NSNotFound else { return }
        XCTAssertEqual(text.attribute(.foregroundColor, at: mention.location, effectiveRange: nil) as? UIColor, UIColor(Color.purple))
        XCTAssertEqual(text.attribute(.foregroundColor, at: hashtag.location, effectiveRange: nil) as? UIColor, UIColor(Color.green))
        XCTAssertEqual(text.attribute(.backgroundColor, at: hashtag.location, effectiveRange: nil) as? UIColor, UIColor(Color.yellow))
        XCTAssertTrue(text.string.contains(source))
    }

}
#endif
