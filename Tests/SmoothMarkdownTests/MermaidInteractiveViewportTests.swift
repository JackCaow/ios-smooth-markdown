import Foundation
import XCTest
@testable import SmoothMarkdown

final class MermaidInteractiveViewportTests: XCTestCase {
    func testFlutterGalleryFlowchartFitsPortraitAndLandscapeAndKeepsSourceNodeIDs() throws {
        // Mermaid 06 is copied unchanged from the Flutter example gallery.
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Demo/SmoothMarkdownDemo/Examples/Mermaid/mermaid-06.mmd")
        let diagram = try XCTUnwrap(MermaidParser.parse(String(contentsOf: fixture)))
        let layout = MermaidLayout.compute(diagram)
        let size = CGSize(width: max(layout.size.width, 180), height: max(layout.size.height, 100))
        let portrait = CGSize(width: 390, height: 600)
        let landscape = CGSize(width: 844, height: 390)
        let portraitFit = MermaidInteractiveViewportGeometry.fittedScale(content: size, viewport: portrait)
        let landscapeFit = MermaidInteractiveViewportGeometry.fittedScale(content: size, viewport: landscape)
        XCTAssertGreaterThanOrEqual(portraitFit, 0.5)
        XCTAssertLessThanOrEqual(portraitFit, 1)
        XCTAssertGreaterThanOrEqual(landscapeFit, 0.5)
        XCTAssertLessThanOrEqual(landscapeFit, 1)

        let frame = try XCTUnwrap(layout.nodes["A"])
        let point = CGPoint(x: frame.midX, y: frame.midY)
        XCTAssertEqual(MermaidInteractiveViewportGeometry.nodeID(
            at: point, layout: layout, diagram: diagram, contentScale: 1), "A")
        XCTAssertEqual(MermaidInteractiveViewportGeometry.nodeID(
            at: CGPoint(x: point.x * 1.5, y: point.y * 1.5),
            layout: layout, diagram: diagram, contentScale: 1.5), "A")
        // UIScrollView converts a zoomed touch to hosted-view coordinates.
        let zoom: CGFloat = 2
        let inset = MermaidInteractiveViewportGeometry.centeredInset(
            content: size, viewport: landscape, scale: zoom)
        let screenPoint = CGPoint(x: inset.width + point.x * zoom,
                                  y: inset.height + point.y * zoom)
        let hostedPoint = CGPoint(x: (screenPoint.x - inset.width) / zoom,
                                  y: (screenPoint.y - inset.height) / zoom)
        XCTAssertEqual(MermaidInteractiveViewportGeometry.nodeID(
            at: hostedPoint, layout: layout, diagram: diagram, contentScale: 1), "A")
        XCTAssertNil(MermaidInteractiveViewportGeometry.nodeID(
            at: CGPoint(x: -10, y: -10), layout: layout, diagram: diagram, contentScale: 1))
    }

    func testFitClampsAndCentersLargeAndSmallDiagrams() {
        XCTAssertEqual(MermaidInteractiveViewportGeometry.fittedScale(
            content: CGSize(width: 100, height: 100), viewport: CGSize(width: 390, height: 600)), 1)
        XCTAssertEqual(MermaidInteractiveViewportGeometry.fittedScale(
            content: CGSize(width: 2_000, height: 1_000), viewport: CGSize(width: 390, height: 600)), 0.5)
        XCTAssertEqual(MermaidInteractiveViewportGeometry.centeredInset(
            content: CGSize(width: 100, height: 100), viewport: CGSize(width: 390, height: 600), scale: 1),
                       CGSize(width: 145, height: 250))
        XCTAssertEqual(MermaidInteractiveViewportGeometry.centeredInset(
            content: CGSize(width: 2_000, height: 1_000), viewport: CGSize(width: 390, height: 600), scale: 0.5),
                       CGSize(width: 0, height: 50))
    }
}
