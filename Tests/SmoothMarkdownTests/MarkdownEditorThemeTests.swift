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
        XCTAssertNil(theme.blockBorderColor)
        XCTAssertNil(theme.tableBorderColor)
        XCTAssertNil(theme.selectionColor)
        XCTAssertNil(theme.suggestionPanelColor)
    }

    func testBlockAndSuggestionOverridesMergeWithoutLosingAmbientValues() {
        let ambient = MarkdownEditorTheme(
            blockBorderColor: .gray, blockBorderRadius: 8,
            tableBorderColor: .blue, selectionColor: .yellow,
            suggestionPanelColor: .black)
        let explicit = MarkdownEditorTheme(
            blockBorderRadius: 0, tableBorderColor: .orange,
            suggestionSelectedBackgroundColor: .green)
        let merged = ambient.merging(explicit)

        XCTAssertEqual(merged.blockBorderColor, .gray)
        XCTAssertEqual(merged.blockBorderRadius, 0)
        XCTAssertEqual(merged.tableBorderColor, .orange)
        XCTAssertEqual(merged.selectionColor, .yellow)
        XCTAssertEqual(merged.suggestionPanelColor, .black)
        XCTAssertEqual(merged.suggestionSelectedBackgroundColor, .green)
    }

    func testTableCellSelectionAndActiveBorderTakePriorityOverHeaderAndGrid() {
        let theme = MarkdownEditorTheme(
            tableBorderColor: .gray, tableHeaderColor: .blue,
            tableSelectionColor: .yellow, tableActiveBorderColor: .orange)

        XCTAssertEqual(theme.tableCellBackground(isSelected: false, isHeader: true), .blue)
        XCTAssertEqual(theme.tableCellBackground(isSelected: true, isHeader: true), .yellow)
        XCTAssertNil(theme.tableCellBackground(isSelected: false, isHeader: false))
        XCTAssertEqual(theme.tableCellBorder(isActive: false), .gray)
        XCTAssertEqual(theme.tableCellBorder(isActive: true), .orange)
        XCTAssertNil(MarkdownEditorTheme().tableCellBorder(isActive: true))
    }
}
