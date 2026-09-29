import SwiftUI
import XCTest
@testable import SmoothMarkdown

final class MarkdownEditorThemeTests: XCTestCase {
    func testExplicitThemeOverridesAmbientValuesAndRetainsUnspecifiedFields() {
        let ambient = MarkdownEditorTheme(
            editorBorderColor: .blue, editorBorderRadius: 9,
            toolbarColor: .gray, sourceFontSize: 16,
            sourcePadding: EdgeInsets(top: 10, leading: 11, bottom: 12, trailing: 13))
        let explicit = MarkdownEditorTheme(
            editorBorderRadius: 0, toolbarColor: .orange,
            sourceFontName: "Menlo", sourcePadding: EdgeInsets())
        let merged = ambient.merging(explicit)

        XCTAssertEqual(merged.editorBorderColor, .blue)
        XCTAssertEqual(merged.editorBorderRadius, 0)
        XCTAssertEqual(merged.toolbarColor, .orange)
        XCTAssertEqual(merged.sourceFontName, "Menlo")
        XCTAssertEqual(merged.sourceFontSize, 16)
        XCTAssertEqual(merged.sourcePadding?.top, 0)
        XCTAssertEqual(merged.sourcePadding?.leading, 0)
        XCTAssertEqual(merged.sourcePadding?.bottom, 0)
        XCTAssertEqual(merged.sourcePadding?.trailing, 0)
    }

    func testUnsetThemeKeepsAllOverridesNil() {
        let theme = MarkdownEditorTheme().merging(nil)
        XCTAssertNil(theme.editorBackgroundColor)
        XCTAssertNil(theme.editorBorderColor)
        XCTAssertNil(theme.toolbarColor)
        XCTAssertNil(theme.sourceFontSize)
        XCTAssertNil(theme.sourcePadding)
        XCTAssertNil(theme.previewPadding)
        XCTAssertNil(theme.contentPadding)
    }
}
