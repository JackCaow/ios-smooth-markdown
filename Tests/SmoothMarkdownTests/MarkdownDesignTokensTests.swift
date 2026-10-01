import SwiftUI
import XCTest
@testable import SmoothMarkdown

final class MarkdownDesignTokensTests: XCTestCase {
    func testSyntaxPaletteOverridesActualCodeTokenColors() {
        let colors = MarkdownSyntaxColors(keyword: .pink, string: .green, comment: .gray, number: .orange, literal: .yellow)
        let text = CodeSyntaxHighlighter.attributed("let answer = 42", language: "swift", dark: false, enabled: true, colors: colors)
        XCTAssertEqual(String(text.characters), "let answer = 42")
        XCTAssertTrue(text.runs.contains { $0.foregroundColor == .pink })
        XCTAssertTrue(text.runs.contains { $0.foregroundColor == .orange })
    }
    func testMathFamilyIsSafelyContainedInsideCss() {
        XCTAssertTrue(NativeMathML.html("x^2", display: true, fontFamily: "monospace").contains("font-family:monospace"))
        let css = NativeMathML.cssFontFamily("x\";</style><script>")
        XCTAssertFalse(css.contains("</style>"))
        XCTAssertFalse(css.contains("<script>"))
    }
    func testExistingDecorationSurvivesNestedTokenOverrides() {
        var sheet = MarkdownStyleSheet.github()
        let existing = sheet.codeBlockDecoration?.cornerRadius
        sheet.designTokens.code.copyLabel = "复制代码"
        sheet.designTokens.heading.barWidth = 0
        XCTAssertEqual(sheet.designTokens.code.copyLabel, "复制代码")
        XCTAssertEqual(sheet.codeBlockDecoration?.cornerRadius, existing)
    }
}
