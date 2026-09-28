import XCTest
import SwiftUI
@testable import SmoothMarkdown

final class CodeBlockStyleTests: XCTestCase {
    func testCustomDecorationAndFourSidedPaddingTakeEffect() {
        let style = MarkdownStyleSheet(codeBackground: .red, codePadding: 9,
                                       codeBlockDecoration: .init(backgroundColor: .blue,
                                                                  borderColor: .green,
                                                                  borderWidth: 2, cornerRadius: 11),
                                       codeBlockPadding: .init(top: 1, leading: 2, bottom: 3, trailing: 4))

        XCTAssertEqual(style.resolvedCodeBlockDecoration.borderWidth, 2)
        XCTAssertEqual(style.resolvedCodeBlockDecoration.cornerRadius, 11)
        XCTAssertNotNil(style.resolvedCodeBlockDecoration.backgroundColor)
        XCTAssertNotNil(style.resolvedCodeBlockDecoration.borderColor)
        XCTAssertEqual(style.resolvedCodeBlockPadding.top, 1)
        XCTAssertEqual(style.resolvedCodeBlockPadding.leading, 2)
        XCTAssertEqual(style.resolvedCodeBlockPadding.bottom, 3)
        XCTAssertEqual(style.resolvedCodeBlockPadding.trailing, 4)
    }

    func testLegacyPaddingAndPresetOutlines() {
        let legacy = MarkdownStyleSheet(codePadding: 7)
        XCTAssertEqual(legacy.resolvedCodeBlockPadding.leading, 7)
        XCTAssertEqual(legacy.resolvedCodeBlockPadding.bottom, 7)
        XCTAssertEqual(legacy.resolvedCodeBlockDecoration.cornerRadius, 8)

        XCTAssertEqual(MarkdownStyleSheet.light().resolvedCodeBlockDecoration.borderWidth, 1)
        XCTAssertEqual(MarkdownStyleSheet.dark().resolvedCodeBlockDecoration.cornerRadius, 4)
        XCTAssertEqual(MarkdownStyleSheet.github().resolvedCodeBlockDecoration.borderWidth, 0)
        XCTAssertEqual(MarkdownStyleSheet.github(dark: true).resolvedCodeBlockDecoration.cornerRadius, 6)
        XCTAssertEqual(MarkdownStyleSheet.vscode().resolvedCodeBlockDecoration.borderWidth, 1)
    }
}
