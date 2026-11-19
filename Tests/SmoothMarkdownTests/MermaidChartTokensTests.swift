import SwiftUI
import XCTest
@testable import SmoothMarkdown

final class MermaidChartTokensTests: XCTestCase {
    func testInvalidChartGeometryIsBoundedWithoutMutatingHost() {
        var style = MarkdownMermaidTokens()
        style.charts.seriesLineWidth = .nan
        style.charts.pointRadius = -8
        style.charts.fillOpacity = 4
        style.charts.gridWidth = .infinity
        let resolved = style.normalized()
        XCTAssertEqual(resolved.charts.seriesLineWidth, 0)
        XCTAssertEqual(resolved.charts.pointRadius, 0)
        XCTAssertEqual(resolved.charts.fillOpacity, 1)
        XCTAssertEqual(resolved.charts.gridWidth, 0)
        XCTAssertTrue(style.charts.seriesLineWidth!.isNaN)
    }
    func testSeriesPaletteCyclesAndEmptyPalettePreservesDefaults() {
        var charts = MarkdownMermaidChartTokens()
        XCTAssertEqual(charts.seriesColor(12, fallback: .blue), .blue)
        charts.seriesColors = [.red, .green]
        XCTAssertEqual(charts.seriesColor(2, fallback: .blue), .red)
        XCTAssertEqual(charts.seriesColor(3, fallback: .blue), .green)
    }
}
