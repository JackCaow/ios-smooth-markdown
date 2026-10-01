import XCTest
import SwiftUI
@testable import SmoothMarkdown

final class MarkdownPluginTokensTests: XCTestCase {
    func testPluginGroupsRemainIndependentAndCustomizable() {
        var tokens = MarkdownPluginTokens()
        tokens.artifact.cornerRadius = 24
        tokens.thinking.contentFont = .caption
        tokens.mentionStyle = MarkdownInlineTextStyle(fontSize: 22, textColor: .purple, bold: true)
        XCTAssertEqual(tokens.artifact.cornerRadius, 24)
        XCTAssertEqual(tokens.toolCall.cornerRadius, 8)
        XCTAssertEqual(tokens.mentionStyle.fontSize, 22)
        XCTAssertEqual(tokens.mentionStyle.bold, true)
    }

    func testInvalidDimensionsNormalizeAndZeroHidesDecoration() {
        let panel = MarkdownPluginPanelTokens(cornerRadius: -.infinity, borderWidth: -3, dividerThickness: 0)
        let admonition = MarkdownAdmonitionTokens(backgroundAlpha: 2, accentWidth: -1)
        XCTAssertEqual(panel.cornerRadius, 0)
        XCTAssertEqual(panel.borderWidth, 0)
        XCTAssertEqual(panel.dividerThickness, 0)
        XCTAssertEqual(admonition.backgroundAlpha, 1)
        XCTAssertEqual(admonition.accentWidth, 0)
    }

    func testMermaidPublicPaletteCanOverridePresetWithoutChangingIt() {
        let original = MermaidTheme.forest.palette
        var custom = original
        custom.nodeFill = 0xFF00FF
        let tokens = MarkdownMermaidTokens(colors: custom, maxHeight: 500)
        XCTAssertEqual(tokens.colors?.nodeFill, 0xFF00FF)
        XCTAssertEqual(MermaidTheme.forest.palette.nodeFill, original.nodeFill)
        XCTAssertEqual(tokens.maxHeight, 500)
        XCTAssertEqual(MarkdownMermaidTokens(maxHeight: .nan).maxHeight, 420)
    }
}
