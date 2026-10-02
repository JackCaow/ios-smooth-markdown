import SwiftUI
import XCTest
@testable import SmoothMarkdown

final class MermaidRoutingTests: XCTestCase {
    func testDiamondBranchesAndMergesUseSeparateBoundaryPortsAndClearLabels() throws {
        let diagram = try XCTUnwrap(MermaidParser.parse("""
        flowchart TD
        A[Start] --> B{Check}
        B -->|Yes| C[First]
        B -->|No| D[Second]
        C --> E[End]
        D --> E
        """))
        let layout = MermaidLayout.compute(diagram)
        let branches = layout.edges.filter { $0.edge.from == "B" }
        let merges = layout.edges.filter { $0.edge.to == "E" }
        XCTAssertEqual(branches.count, 2)
        XCTAssertNotEqual(branches[0].start, branches[1].start)
        XCTAssertNotEqual(merges[0].end, merges[1].end)
        let diamond = try XCTUnwrap(layout.nodes["B"])
        for branch in branches {
            let point = branch.start
            XCTAssertEqual(abs(point.x - diamond.midX) / (diamond.width / 2)
                           + abs(point.y - diamond.midY) / (diamond.height / 2), 1, accuracy: 0.001)
            let label = try XCTUnwrap(branch.labelFrame)
            XCTAssertFalse(layout.nodes.values.contains { $0.intersects(label) })
        }
        assertBounded(layout)
    }

    func testReverseTransitionsDoNotSharePortsOrTheSameRoute() throws {
        let diagram = try XCTUnwrap(MermaidParser.parse("""
        stateDiagram-v2
        [*] --> Idle
        Idle --> Running: Start
        Running --> Idle: Stop
        Running --> [*]
        """))
        let layout = MermaidLayout.compute(diagram)
        let forward = try XCTUnwrap(layout.edges.first { $0.edge.from == "Idle" && $0.edge.to == "Running" })
        let reverse = try XCTUnwrap(layout.edges.first { $0.edge.from == "Running" && $0.edge.to == "Idle" })
        XCTAssertGreaterThan(hypot(forward.start.x - reverse.end.x, forward.start.y - reverse.end.y), 10)
        XCTAssertNotEqual(forward.start, reverse.end)
        XCTAssertNotEqual(forward.end, reverse.start)
        XCTAssertNotEqual(forward.route, Array(reverse.route.reversed()))
        for edge in [forward, reverse] {
            XCTAssertGreaterThanOrEqual(edge.route.count, 2)
            XCTAssertNotEqual(edge.route.last, edge.route.dropLast().last, "Arrow tangent must have a nonzero terminal leg")
        }
        assertBounded(layout)
    }

    func testCurvedAndRoundedPathsPreserveEndpointsAndHostConfiguration() throws {
        let points = [CGPoint(x: 10, y: 10), .init(x: 10, y: 80), .init(x: 100, y: 80), .init(x: 100, y: 150)]
        for routing in [MermaidEdgeRouting.rounded, .curved] {
            let path = MermaidRouteGeometry.path(points, routing: routing, radius: 14)
            XCTAssertFalse(path.isEmpty)
            XCTAssertEqual(path.currentPoint, points.last)
            XCTAssertTrue(path.boundingRect.contains(points.first!))
        }
        var style = MarkdownMermaidTokens()
        style.edgeRouting = .curved; style.cornerRadius = 23; style.strokeWidth = 3
        style.arrowSize = 16; style.labelPadding = 9
        let resolved = style.normalized()
        XCTAssertEqual(resolved.edgeRouting, .curved)
        XCTAssertEqual(resolved.cornerRadius, 23)
        XCTAssertEqual(resolved.strokeWidth, 3)
        XCTAssertEqual(resolved.arrowSize, 16)
        XCTAssertEqual(resolved.labelPadding, 9)
        style.cornerRadius = -.infinity; style.strokeWidth = .nan; style.arrowSize = -1; style.labelPadding = .nan
        XCTAssertEqual(style.normalized().cornerRadius, 0)
        XCTAssertEqual(style.normalized().strokeWidth, 1.5)
        XCTAssertEqual(style.normalized().arrowSize, 10)
        XCTAssertEqual(style.normalized().labelPadding, 0)
    }

    func testClassAndERCanvasesHugActualInkAndKeepRelationshipSymbols() throws {
        for source in ["classDiagram\nAnimal <|-- Cat", "erDiagram\nUSER ||--o{ ORDER : owns"] {
            let diagram = try XCTUnwrap(MermaidParser.parse(source))
            let layout = MermaidLayout.compute(diagram)
            let nodes = layout.nodes.values.reduce(CGRect.null) { $0.union($1) }
            XCTAssertLessThanOrEqual(nodes.minX, 25)
            XCTAssertLessThanOrEqual(nodes.minY, 25)
            XCTAssertLessThan(layout.size.height - nodes.height, 100)
            XCTAssertTrue(layout.edges.contains { $0.edge.sourceMarker != nil || $0.edge.targetMarker != nil })
            assertBounded(layout)
        }
    }

    func testEmptyCompartmentsAndEndpointLabelsKeepNaturalBounds() throws {
        let diagram = MermaidDiagram(kind: .classDiagram, direction: .topToBottom,
            nodes: [.init(id: "A", label: "A", compartments: [[], []]), .init(id: "B", label: "B")],
            edges: [.init(from: "A", to: "B", label: "多行\nrelationship", sourceLabel: "1", targetLabel: "many")])
        let layout = MermaidLayout.compute(diagram)
        XCTAssertEqual(try XCTUnwrap(layout.nodes["A"]).height, 48)
        let edge = try XCTUnwrap(layout.edges.first)
        for frame in [edge.labelFrame, edge.sourceLabelFrame, edge.targetLabelFrame] {
            let label = try XCTUnwrap(frame)
            XCTAssertFalse(layout.nodes.values.contains { $0.intersects(label) })
        }
        XCTAssertGreaterThan(try XCTUnwrap(edge.labelFrame).height, 24)
        assertBounded(layout)
        // Public hand-built models may contain duplicate IDs; placement stays safe.
        let repeated = MermaidDiagram(kind: .flowchart, direction: .topToBottom,
            nodes: [.init(id: "A", label: "first"), .init(id: "A", label: "last")])
        XCTAssertNotNil(MermaidLayout.compute(repeated).nodes["A"])
    }

    private func assertBounded(_ layout: MermaidLayoutResult, file: StaticString = #filePath, line: UInt = #line) {
        let canvas = CGRect(origin: .zero, size: layout.size)
        for frame in layout.nodes.values { XCTAssertTrue(canvas.contains(frame), file: file, line: line) }
        for edge in layout.edges {
            for point in edge.route { XCTAssertTrue(canvas.contains(point), file: file, line: line) }
            for label in [edge.labelFrame, edge.sourceLabelFrame, edge.targetLabelFrame].compactMap({ $0 }) {
                XCTAssertTrue(canvas.contains(label), file: file, line: line)
            }
        }
    }
}
