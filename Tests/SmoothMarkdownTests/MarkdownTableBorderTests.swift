import SwiftUI
import XCTest
@testable import SmoothMarkdown

final class MarkdownTableBorderTests: XCTestCase {
    func testDefaultAndLegacyColorResolution() {
        XCTAssertNil(MarkdownStyleSheet.default().resolvedTableBorder)

        let legacy = MarkdownStyleSheet(tableBorderColor: .orange).resolvedTableBorder
        XCTAssertEqual(legacy?.top?.color, .orange)
        XCTAssertEqual(legacy?.horizontalInside?.color, .orange)
        XCTAssertEqual(legacy?.verticalInside?.width, 1)

        let noLines = MarkdownStyleSheet(tableBorderColor: .orange, tableBorder: .init())
        XCTAssertTrue(MarkdownTableGridLayout.segments(border: noLines.resolvedTableBorder,
                                                      rowIndex: 0, rowCount: 2, columnCount: 2,
                                                      columnWidth: 100, rowHeight: 30).isEmpty)
    }

    func testInnerRulesDrawOnceAtSharedEdges() {
        let border = MarkdownTableBorder.all(color: .purple, width: 3)
        let first = MarkdownTableGridLayout.segments(border: border, rowIndex: 0, rowCount: 2,
                                                     columnCount: 3, columnWidth: 100, rowHeight: 30)
        let second = MarkdownTableGridLayout.segments(border: border, rowIndex: 1, rowCount: 2,
                                                      columnCount: 3, columnWidth: 100, rowHeight: 40)
        XCTAssertEqual(first.count, 5) // top, left, right, two inner columns
        XCTAssertEqual(second.count, 6) // inner row, bottom, left, right, two inner columns
        XCTAssertEqual(first.filter { $0.start.y == $0.end.y }.count, 1)
        XCTAssertEqual(second.filter { $0.start.y == $0.end.y }.count, 2)
        XCTAssertEqual(first.filter { $0.start.x == 100 || $0.start.x == 200 }.count, 2)
        XCTAssertEqual(second.filter { $0.start.x == 100 || $0.start.x == 200 }.count, 2)
        XCTAssertTrue((first + second).allSatisfy { $0.side.width == 3 && $0.side.color == .purple })
    }

    func testSelectiveOuterAndInnerSidesAndClampedWidth() {
        let border = MarkdownTableBorder(top: .init(color: .red, width: 2),
                                         bottom: .init(color: .blue, width: -1),
                                         verticalInside: .init(color: .green, width: 4))
        let onlyRow = MarkdownTableGridLayout.segments(border: border, rowIndex: 0, rowCount: 1,
                                                       columnCount: 2, columnWidth: 80, rowHeight: 28)
        XCTAssertEqual(onlyRow.count, 2)
        XCTAssertEqual(onlyRow[0].side.color, .red)
        XCTAssertEqual(onlyRow[0].start.y, 1)
        XCTAssertEqual(onlyRow[1].side.color, .green)
        XCTAssertEqual(onlyRow[1].start.x, 80)
        XCTAssertEqual(onlyRow[1].side.width, 4)
    }
}
