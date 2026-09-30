import SwiftUI
import XCTest
@testable import SmoothMarkdown

@MainActor
final class TableColumnPresentationTests: XCTestCase {
    func testReaderUsesGFMDelimiterAlignmentForHeaderAndBodyColumns() {
        let source = "| Left | Center | Right | Default |\n| :--- | :---: | ---: | --- |\n| one | two | three | four |"
        guard let table = MarkdownSyntax.parse(source).child(at: 0) as? Markdown.Table else {
            return XCTFail("Expected GFM table")
        }
        XCTAssertEqual(table.columnAlignments.map(MarkdownTableColumnPresentation.init),
                       [.left, .center, .right, .left])
        XCTAssertEqual(MarkdownTableColumnPresentation(.center as Markdown.Table.ColumnAlignment).textAlignment,
                       .center)
        XCTAssertEqual(MarkdownTableColumnPresentation(.right as Markdown.Table.ColumnAlignment).frameAlignment,
                       .trailing)
    }

    func testFormattedAlignmentEditUpdatesReaderPresentationAndUndo() {
        let source = "| Name | Amount |\n| --- | ---: |\n| A | 12 |"
        let controller = MarkdownEditorController(text: source)
        XCTAssertTrue(controller.updateSemanticTable(id: "block-0") {
            $0.settingColumnAlignment(0, to: .center)
        })
        guard case let .table(edited) = controller.semanticDocument.blocks[0].kind,
              let readerTable = MarkdownSyntax.parse(controller.text).child(at: 0) as? Markdown.Table else {
            return XCTFail("Expected edited table in both paths")
        }
        XCTAssertEqual(edited.alignments.map(MarkdownTableColumnPresentation.init), [.center, .right])
        XCTAssertEqual(readerTable.columnAlignments.map(MarkdownTableColumnPresentation.init), [.center, .right])
        XCTAssertEqual(controller.text, "| Name | Amount |\n| :---: | ---: |\n| A | 12 |")
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, source)
    }

    func testEqualFlexibleWidthsAndOnlyMinimumPaddingOverflow() {
        XCTAssertEqual(MarkdownTableViewport<EmptyView>.columnWidth(
            viewportWidth: 600, columnCount: 3, padding: 8), 200)
        XCTAssertEqual(MarkdownTableViewport<EmptyView>.columnWidth(
            viewportWidth: 300, columnCount: 3, padding: 8), 100)
        XCTAssertEqual(MarkdownTableViewport<EmptyView>.columnWidth(
            viewportWidth: 80, columnCount: 5, padding: 8), 17)
        XCTAssertEqual(MarkdownTableViewport<EmptyView>.columnWidth(
            viewportWidth: 0, columnCount: 3, padding: 8), 166)
        XCTAssertEqual(MarkdownTableViewport<EmptyView>.columnWidth(
            viewportWidth: .infinity, columnCount: 3, padding: 8), 166)
        XCTAssertEqual(MarkdownTableViewport<EmptyView>.columnWidth(
            viewportWidth: .nan, columnCount: 3, padding: 8), 166)
    }

    #if os(iOS)
    func testNativeEditorFieldUsesSameAlignment() {
        XCTAssertEqual(MarkdownTableColumnPresentation(nil as MarkdownTableAlignment?).fieldTextAlignment, .left)
        XCTAssertEqual(MarkdownTableColumnPresentation(.center as MarkdownTableAlignment).fieldTextAlignment, .center)
        XCTAssertEqual(MarkdownTableColumnPresentation(.right as MarkdownTableAlignment).fieldTextAlignment, .right)
    }
    #endif
}
