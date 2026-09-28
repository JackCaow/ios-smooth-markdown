@testable import SmoothMarkdown
import XCTest

final class MermaidAccessibilityTests: XCTestCase {
    func testFlowchartReadsNamedNodesAndLabeledConnections() throws {
        let diagram = try XCTUnwrap(MermaidParser.parse("""
        flowchart LR
        A[开始] -->|确认| B[完成]
        """))
        let summary = diagram.voiceOverSummary
        XCTAssertTrue(summary.contains("开始"))
        XCTAssertTrue(summary.contains("完成"))
        XCTAssertTrue(summary.contains("确认"))
    }

    func testPieReadsValuesAndLongListsStayBounded() {
        let diagram = MermaidDiagram(kind: .pie, direction: .leftToRight,
            title: "Revenue", pieSlices: (1...12).map { .init(label: "Item \($0)", value: Double($0)) })
        let summary = diagram.voiceOverSummary
        XCTAssertTrue(summary.contains("Revenue"))
        XCTAssertTrue(summary.contains("Item 1 1"))
        XCTAssertTrue(summary.contains("4 more"))
        XCTAssertFalse(summary.contains("Item 12"))
    }
}
