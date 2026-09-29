import SwiftUI
import XCTest
@testable import SmoothMarkdown

final class MarkdownStyleSheetTests: XCTestCase {
    func testPresetsAndCustomValuesReachReaderAndStream() {
        let github = MarkdownStyleSheet.github()
        let githubDark = MarkdownStyleSheet.github(dark: true)
        let vscode = MarkdownStyleSheet.vscode()
        let vscodeDark = MarkdownStyleSheet.vscode(dark: true)
        XCTAssertEqual(github.linkColor, rgb(0x0969DA))
        XCTAssertEqual(githubDark.linkColor, rgb(0x58A6FF))
        XCTAssertEqual(vscode.linkColor, rgb(0x0066BF))
        XCTAssertEqual(vscodeDark.linkColor, rgb(0x4FC1FF))
        XCTAssertEqual(githubDark.darkCodeHighlighting, true)
        XCTAssertEqual(github.headingFonts?.count, 6)

        var custom = github
        custom.linkColor = .purple
        custom.blockSpacing = 20
        custom.paragraphFont = .system(size: 18)
        custom.horizontalRuleThickness = 3
        custom.tableHeaderBackgroundColor = .orange
        custom.listBulletFont = .title3
        custom.listBulletColor = .purple
        let reader = SmoothMarkdownView(markdown: "[link](https://example.com)", styleSheet: custom)
        XCTAssertEqual(reader.styleSheet.linkColor, .purple)
        XCTAssertEqual(reader.styleSheet.blockSpacing, 20)
        XCTAssertEqual(reader.styleSheet.horizontalRuleThickness, 3)
        XCTAssertEqual(reader.styleSheet.tableHeaderBackgroundColor, .orange)
        XCTAssertEqual(reader.styleSheet.listBulletColor, .purple)
        XCTAssertNotNil(reader.styleSheet.listBulletFont)

        let stream = StreamMarkdownView(chunks: AsyncStream<String> { continuation in continuation.finish() },
                                        styleSheet: custom)
        XCTAssertEqual(stream.styleSheet.blockSpacing, 20)
        XCTAssertEqual(stream.styleSheet.linkColor, .purple)
        XCTAssertEqual(stream.styleSheet.horizontalRuleThickness, 3)
        XCTAssertEqual(stream.styleSheet.tableHeaderBackgroundColor, .orange)
        XCTAssertEqual(stream.styleSheet.listBulletColor, .purple)
    }

    func testDefaultInheritsHostAndNegativeSpacingClampsToZero() {
        let defaults = MarkdownStyleSheet.default()
        XCTAssertNil(defaults.backgroundColor)
        XCTAssertNil(defaults.textColor)
        XCTAssertNil(defaults.darkCodeHighlighting)
        XCTAssertEqual(defaults.blockSpacing, 12)
        XCTAssertEqual(defaults.horizontalRuleThickness, 1)
        XCTAssertNil(defaults.tableHeaderBackgroundColor)
        XCTAssertNil(defaults.listBulletColor)

        let custom = MarkdownStyleSheet(horizontalRuleThickness: -1,
                                        blockSpacing: -1, contentPadding: -2, listIndent: -3)
        XCTAssertEqual(custom.blockSpacing, 0)
        XCTAssertEqual(custom.horizontalRuleThickness, 0)
        XCTAssertEqual(custom.contentPadding, 0)
        XCTAssertEqual(custom.listIndent, 0)
    }

    func testLightAndDarkTableHeadersMatchFlutterPresets() {
        XCTAssertEqual(MarkdownStyleSheet.light().tableHeaderBackgroundColor, rgb(0xEEEEEE))
        XCTAssertEqual(MarkdownStyleSheet.dark().tableHeaderBackgroundColor, rgb(0x303030))
        XCTAssertEqual(MarkdownStyleSheet.light().horizontalRuleThickness, 1)
        XCTAssertEqual(MarkdownStyleSheet.dark().horizontalRuleThickness, 1)
    }

    private func rgb(_ value: UInt32) -> Color {
        Color(.sRGB, red: Double((value >> 16) & 0xFF) / 255,
              green: Double((value >> 8) & 0xFF) / 255,
              blue: Double(value & 0xFF) / 255, opacity: 1)
    }
}
