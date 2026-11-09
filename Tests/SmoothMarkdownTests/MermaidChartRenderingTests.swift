import SwiftUI
import XCTest
@testable import SmoothMarkdown

@MainActor
final class MermaidChartRenderingTests: XCTestCase {
    func testEverySpecialtyChartRendersAndUpdatesHostPalette() throws {
        let sources = [
            "pie\n\"One\" : 40\n\"Two\" : 60",
            "timeline\n2024 : Launch",
            "gantt\nTask :crit, a, 2024-06-01, 3d",
            "kanban\n  todo[Todo]\n    task[Fix] @{ priority: \"High\" }",
            "radar-beta\naxis A, B, C\ncurve c{4, 7, 6}",
            "xychart-beta\nx-axis [A, B]\nbar [3, 8]\nline [5, 7]",

        ]
        for source in sources {
            let diagram = try XCTUnwrap(MermaidParser.parse(source), source)
            let normal = try pixels(diagram: diagram, color: nil)
            let custom = try pixels(diagram: diagram, color: Color(red: 1, green: 0, blue: 1))
            XCTAssertGreaterThan(custom, normal + 100, "Chart ignored host palette: \(source)")
        }
    }
    private func pixels(diagram: MermaidDiagram, color: Color?) throws -> Int {
        var style = MarkdownMermaidTokens()
        if let color {
            style.charts.seriesColors = [color]
            style.charts.ganttStatusColors = [.critical: color]
            style.charts.kanbanPriorityColors = [.high: color]
        }
        let renderer = ImageRenderer(content: MermaidDiagramView(diagram: diagram, theme: .light,
            scrollable: false, style: style).background(Color.white))
        let image = try XCTUnwrap(renderer.cgImage)
        let bytes = UnsafeMutablePointer<UInt8>.allocate(capacity: image.width * image.height * 4)
        defer { bytes.deallocate() }
        let bitmap = try XCTUnwrap(CGContext(data: bytes, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        bitmap.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return stride(from: 0, to: image.width * image.height * 4, by: 4).filter {
            bytes[$0] > 200 && bytes[$0 + 1] < 80 && bytes[$0 + 2] > 200
        }.count
    }
}
