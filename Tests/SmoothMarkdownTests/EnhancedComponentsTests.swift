import Markdown
import SwiftUI
import XCTest
@testable import SmoothMarkdown

final class EnhancedComponentsTests: XCTestCase {
    func testReaderAndStreamDefaultToStandardComponents() {
        XCTAssertFalse(SmoothMarkdownView(markdown: "# Title").useEnhancedComponents)
        XCTAssertTrue(SmoothMarkdownView(markdown: "# Title", useEnhancedComponents: true)
            .useEnhancedComponents)

        let chunks = AsyncStream<String> { $0.finish() }
        XCTAssertFalse(StreamMarkdownView(chunks: chunks).useEnhancedComponents)
        XCTAssertTrue(StreamMarkdownView(chunks: chunks, useEnhancedComponents: true)
            .useEnhancedComponents)
    }

    func testEnhancedAICardsRequireOptInButCustomPluginRenderRemainsAvailable() {
        for id in ["thinking", "artifact", "tool_call"] {
            XCTAssertFalse(MarkdownEnhancedComponents.usesBuiltInAICard(for: id, enabled: false))
            XCTAssertTrue(MarkdownEnhancedComponents.usesBuiltInAICard(for: id, enabled: true))
        }
        XCTAssertTrue(MarkdownEnhancedComponents.usesBuiltInAICard(for: "mermaid", enabled: false))
    }

    func testExternalCueOnlyAppliesToWebLinks() {
        XCTAssertTrue(MarkdownEnhancedComponents.isExternalLink(URL(string: "https://example.com")!))
        XCTAssertTrue(MarkdownEnhancedComponents.isExternalLink(URL(string: "http://example.com")!))
        XCTAssertFalse(MarkdownEnhancedComponents.isExternalLink(URL(string: "mailto:hello@example.com")!))
    }

    #if os(iOS)
    @available(iOS 17.0, *)
    @MainActor
    func testEditorPreviewDefaultsToEnhancedAndCanOptOut() {
        let controller = MarkdownEditorController(text: "# Title")
        XCTAssertTrue(SmoothMarkdownEditor(controller: controller).useEnhancedComponents)
        XCTAssertFalse(SmoothMarkdownEditor(controller: controller, useEnhancedComponents: false)
            .useEnhancedComponents)
    }

    @available(iOS 17.0, *)
    func testNativeTextVariantsPreserveCopiedTextAndChangeDecoration() throws {
        let source = "# Heading\n\n> Quoted text\n\n[Website](https://example.com)"
        let nodes = Array(MarkdownSyntax.parse(source).children)
        let document = try XCTUnwrap(ReaderSelectionDocument.compose(
            nodes, enableHTML: false, plugins: nil))
        func styled(_ enhanced: Bool) ->
            (text: NSAttributedString, quoteRegions: [QuoteTextView.Region],
             ruleRegions: [NSRange], headingRegions: [NSRange]) {
            ReaderSelectionTextView(document: document, styleSheet: .default(),
                                    onLinkTap: nil, onTextLongPress: nil,
                                    selectable: true, onCharacterTap: nil,
                                    useEnhancedComponents: enhanced)
                .attributedContent(traits: UITraitCollection())
        }

        let standard = styled(false)
        let enhanced = styled(true)
        XCTAssertEqual(standard.text.string, document.selectionText)
        XCTAssertEqual(enhanced.text.string, document.selectionText)
        XCTAssertTrue(standard.headingRegions.isEmpty)
        XCTAssertEqual(enhanced.headingRegions.count, 1)
        XCTAssertEqual(standard.quoteRegions.count, enhanced.quoteRegions.count)

        let quote = (standard.text.string as NSString).range(of: "Quoted text").location
        let standardParagraph = try XCTUnwrap(standard.text.attribute(.paragraphStyle, at: quote,
                                                                      effectiveRange: nil) as? NSParagraphStyle)
        let enhancedParagraph = try XCTUnwrap(enhanced.text.attribute(.paragraphStyle, at: quote,
                                                                      effectiveRange: nil) as? NSParagraphStyle)
        XCTAssertEqual(enhancedParagraph.firstLineHeadIndent - standardParagraph.firstLineHeadIndent, 36)

        let lastLinkCharacter = (standard.text.string as NSString).range(of: "Website").upperBound - 1
        XCTAssertNil(standard.text.attribute(.underlineStyle, at: lastLinkCharacter,
                                             effectiveRange: nil))
        XCTAssertNotNil(enhanced.text.attribute(.underlineStyle, at: lastLinkCharacter,
                                               effectiveRange: nil))
        XCTAssertNotNil(enhanced.text.attribute(.kern, at: lastLinkCharacter, effectiveRange: nil))
    }
    #endif
}
