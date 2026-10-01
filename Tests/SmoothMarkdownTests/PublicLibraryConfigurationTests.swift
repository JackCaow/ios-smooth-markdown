import Combine
import SwiftUI
import XCTest
@testable import SmoothMarkdown

final class PublicLibraryConfigurationTests: XCTestCase {
    func testInvalidTokenConstructionDoesNotTrapAndUsesUnifiedPolicy() {
        let tokens = MarkdownDesignTokens(
            heading: .init(decoratedThroughLevel: 100, barWidth: -.infinity, barEndAlpha: 2),
            quote: .init(iconSize: .nan, shadowX: -4),
            math: .init(inlineFontSize: .nan, displayScale: -1, fontFamily: "invalid"),
            imagePlaceholderMinSize: .infinity)
        XCTAssertEqual(tokens.heading.decoratedThroughLevel, 6)
        XCTAssertEqual(tokens.heading.barWidth, 0)
        XCTAssertEqual(tokens.heading.barEndAlpha, 1)
        XCTAssertEqual(tokens.quote.iconSize, 0)
        XCTAssertEqual(tokens.quote.shadowX, -4)
        XCTAssertEqual(tokens.math.inlineFontSize, 16)
        XCTAssertEqual(tokens.math.displayScale, 1.25)
        XCTAssertEqual(tokens.math.fontFamily, "serif")
        XCTAssertEqual(tokens.imagePlaceholderMinSize, 0)
    }

    func testMutatedNestedTokensCannotBypassReaderNormalization() {
        var style = MarkdownStyleSheet.default()
        style.designTokens.heading.padding.leading = .nan
        style.designTokens.code.copyFeedbackSeconds = .infinity
        style.designTokens.plugins.artifact.maximumContentHeight = -8
        style.designTokens.typography.headingLineHeights = [.nan]
        style.contentPadding = -.infinity
        style.linkStyle = .init(fontSize: .nan)
        let reader = SmoothMarkdownView(markdown: "###### Six", styleSheet: style)
        XCTAssertEqual(reader.styleSheet.contentPadding, 0)
        XCTAssertEqual(reader.styleSheet.designTokens.heading.padding.leading, 0)
        XCTAssertEqual(reader.styleSheet.designTokens.code.copyFeedbackSeconds, 0)
        XCTAssertEqual(reader.styleSheet.designTokens.plugins.artifact.maximumContentHeight, 0)
        XCTAssertEqual(reader.styleSheet.designTokens.typography.headingLineHeights, [1.3, 1.3, 1.4, 1.4, 1.4, 1.4])
        XCTAssertEqual(reader.styleSheet.linkStyle?.fontSize, 17)
    }

    func testPartialHeadingArraysAndNamedHeadingValuesAreSafe() {
        var typography = MarkdownTypographyTokens(headings: [.init(size: 20)], headingLineHeights: [])
        XCTAssertEqual(typography.headings?.count, 6)
        XCTAssertEqual(typography.headingLineHeights.count, 6)
        typography.headingLineHeightsByLevel.h6 = 2
        XCTAssertEqual(typography.headingLineHeights[5], 2)
        var levels = MarkdownHeadingValues(h1: 1, h2: 2, h3: 3, h4: 4, h5: 5, h6: 6)
        XCTAssertEqual(levels[level: -10], 1)
        XCTAssertEqual(levels[level: 100], 6)
        levels[level: 100] = 9
        XCTAssertEqual(levels.h6, 9)
    }

    func testParserRegistryPublishesEffectiveMutationsAndKeepsCopyIndependent() throws {
        let registry = ParserPluginRegistry()
        var revisions: [UInt64] = []
        let subscription = registry.$revision.sink { revisions.append($0) }
        try registry.register(MentionPlugin())
        XCTAssertThrowsError(try registry.register(MentionPlugin()))
        XCTAssertFalse(registry.unregisterInline("missing"))
        let copied = registry.copy()
        XCTAssertTrue(registry.unregisterInline("mention"))
        registry.clear()
        XCTAssertEqual(revisions, [0, 1, 2])
        XCTAssertNotNil(copied.getInlinePlugin("mention"))
        XCTAssertEqual(copied.revision, 1)
        withExtendedLifetime(subscription) {}
    }

    func testBuilderRegistryRevisionTracksReplacementAndRemoval() {
        let registry = BuilderRegistry()
        var revisions: [UInt64] = []
        let subscription = registry.$revision.sink { revisions.append($0) }
        registry.register("paragraph", builder: ConfigurationBuilder())
        registry.register("paragraph", builder: ConfigurationBuilder())
        registry.unregister("missing")
        registry.unregister("paragraph")
        registry.clear()
        XCTAssertEqual(revisions, [0, 1, 2, 3])
        withExtendedLifetime(subscription) {}
    }

    func testStructuredAPIMapsBehaviorSelectionAndOneHandlerPerEvent() {
        var links: [URL] = []
        var images: [String] = []
        let view = SmoothMarkdownView(markdown: "hello",
            renderOptions: .init(enableHTML: true, useEnhancedComponents: true, enableCache: false, scrollable: false),
            selectionOptions: .init(mode: .block),
            events: .init(onLinkTap: { links.append($0) }, onImageTap: { event in images.append(event.source) }))
        XCTAssertTrue(view.selectable)
        XCTAssertFalse(view.enableCrossBlockSelection)
        XCTAssertFalse(view.enableCache)
        XCTAssertFalse(view.scrollable)
        XCTAssertTrue(view.enableHTML)
        view.onLinkTap?(URL(string: "https://example.com")!)
        view.onImageTapWithMetadata?("photo.png", "alt", nil)
        XCTAssertEqual(links.count, 1)
        XCTAssertEqual(images, ["photo.png"])
        XCTAssertNil(view.onImageTap)
    }

    func testDocumentTokensWinAndRemovingAnOverrideRestoresOriginalFallback() {
        var style = MarkdownStyleSheet(textColor: .red, linkColor: .red, quoteBackground: .red,
            blockquoteDecoration: .init(backgroundColor: .orange), linkStyle: .init(textColor: .orange))
        style.designTokens.document.textColor = .green
        style.designTokens.document.linkColor = .green
        style.designTokens.document.quoteBackground = .green
        let reader = SmoothMarkdownView(markdown: "theme", styleSheet: style)
        XCTAssertEqual(reader.styleSheet.textColor, .green)
        XCTAssertEqual(reader.styleSheet.linkStyle?.textColor, .green)
        XCTAssertEqual(reader.styleSheet.resolvedBlockquoteDecoration.backgroundColor, .green)
        style.designTokens.document = .init()
        XCTAssertEqual(SmoothMarkdownView(markdown: "theme", styleSheet: style).styleSheet.textColor, .red)
        XCTAssertEqual(style.blockquoteDecoration?.backgroundColor, .orange)
    }

    func testExplicitCodeOptionsWinOverEnhancedSwitchWhileDefaultsStayStandard() {
        let standard = SmoothMarkdownView(markdown: "```swift\nlet n = 1\n```", useEnhancedComponents: false)
        XCTAssertFalse(standard.usesEnhancedCodeBlocks)
        let explicit = SmoothMarkdownView(markdown: "code", useEnhancedComponents: false,
            codeBlockOptions: .init(showCopyButton: true, showLanguageTag: false, enableSyntaxHighlighting: false))
        XCTAssertTrue(explicit.usesEnhancedCodeBlocks)
        XCTAssertTrue(explicit.codeBlockOptions.showCopyButton)
        XCTAssertFalse(explicit.codeBlockOptions.showLanguageTag)
        XCTAssertFalse(explicit.codeBlockOptions.enableSyntaxHighlighting)
    }

    func testPluginBatchFailureIsAtomic() throws {
        let registry = ParserPluginRegistry()
        try registry.register(MentionPlugin())
        XCTAssertThrowsError(try registry.registerAll([HashtagPlugin(), MentionPlugin()]))
        XCTAssertNil(registry.getInlinePlugin("hashtag"))
        XCTAssertEqual(registry.revision, 1)
    }

    func testExplicitTypographyAndDecorationOverrideLegacyFallback() {
        var style = MarkdownStyleSheet(quoteBarColor: .red, quoteBackground: .blue,
            paragraphFont: .caption, blockquoteDecoration: .init(borderColor: .green),
            designTokens: .init(typography: .init(paragraph: .init(size: 21))))
        XCTAssertEqual(style.resolvedBlockquoteDecoration.backgroundColor, .blue)
        XCTAssertEqual(style.resolvedBlockquoteDecoration.borderColor, .green)
        style.blockquoteDecoration?.borderWidth = .infinity
        let resolved = style.normalized()
        XCTAssertEqual(resolved.blockquoteDecoration?.borderWidth, 0)
        XCTAssertEqual(resolved.designTokens.typography.paragraph?.size, 21)
    }
}

private struct ConfigurationBuilder: MarkdownWidgetBuilder {
    func canBuild(_ node: Markup) -> Bool { node is Paragraph }
    func build(_ node: Markup, context: MarkdownRenderContext) -> AnyView { AnyView(Text("replacement")) }
}
