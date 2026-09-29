import XCTest
@testable import SmoothMarkdown

final class MermaidStructuredTests: XCTestCase {
    func testChineseStateFixtureKeepsDistinctStartEndAndTransitions() {
        let source = """
        stateDiagram-v2
            [*] --> 待支付
            待支付 --> 已支付: 支付成功
            已支付 --> 已发货: 发货
            已发货 --> 已完成: 确认收货
            已完成 --> [*]
            待支付 --> 已取消: 超时/取消
            已取消 --> [*]
        """
        let diagram = MermaidParser.parse(source)!
        XCTAssertEqual(diagram.kind, .stateDiagram)
        XCTAssertEqual(diagram.nodes.count, 7)
        XCTAssertEqual(diagram.edges.count, 7)
        XCTAssertEqual(diagram.node("$state:start")?.shape, .stateStart)
        XCTAssertEqual(diagram.node("$state:end")?.shape, .stateEnd)
        XCTAssertEqual(diagram.edges[5].label, "超时/取消")
        assertValidLayout(diagram)
    }

    func testStateAliasesChoiceSelfLoopAndDirection() {
        let diagram = MermaidParser.parse("""
        stateDiagram
        direction LR
        state "Waiting for payment" as pending
        state choice <<choice>>
        pending --> pending: retry
        pending --> choice
        choice --> done
        done : Completed
        """)!
        XCTAssertEqual(diagram.direction, .leftToRight)
        XCTAssertEqual(diagram.node("pending")?.label, "Waiting for payment")
        XCTAssertEqual(diagram.node("choice")?.shape, .diamond)
        XCTAssertEqual(diagram.node("done")?.label, "Completed")
        XCTAssertEqual(diagram.edges[0].from, diagram.edges[0].to)
        assertValidLayout(diagram)
    }

    func testStateSelfLoopLabelsAndArrowTangentsFitInAllDirections() {
        let source = """
        stateDiagram-v2
        [*] --> Idle
        [*] --> Waiting
        Idle --> Idle: RETRY AFTER VALIDATION
        Waiting --> Waiting: WAIT FOR CONFIRMATION
        Idle --> Done
        Waiting --> Done
        Done --> [*]
        """
        for (token, direction) in [("TB", MermaidDirection.topToBottom),
                                   ("BT", .bottomToTop), ("LR", .leftToRight),
                                   ("RL", .rightToLeft)] {
            let diagram = MermaidParser.parse(source.replacingOccurrences(
                of: "stateDiagram-v2\n", with: "stateDiagram-v2\ndirection \(token)\n"))!
            XCTAssertEqual(diagram.direction, direction)
            let layout = MermaidLayout.compute(diagram)
            assertValidLayout(diagram)
            let bounds = CGRect(origin: .zero, size: layout.size)
            let loops = layout.edges.filter { $0.edge.from == $0.edge.to }
            XCTAssertEqual(loops.count, 2, token)
            let labelFrames = loops.compactMap { $0.selfLoop?.labelFrame }
            XCTAssertEqual(labelFrames.count, 2, token)
            for placed in loops {
                guard let loop = placed.selfLoop, let label = loop.labelFrame else {
                    XCTFail("Missing self-loop geometry for \(token)"); continue
                }
                XCTAssertTrue(bounds.contains(label), token)
                XCTAssertTrue(bounds.contains(loop.control1), token)
                XCTAssertTrue(bounds.contains(loop.control2), token)
                for node in layout.nodes.values {
                    XCTAssertFalse(label.intersects(node), "\(token): label overlaps a state")
                }
                let angle = atan2(placed.end.y - loop.control2.y,
                                  placed.end.x - loop.control2.x)
                let expected: CGFloat = direction == .leftToRight || direction == .rightToLeft
                    ? atan2(45, -25) : atan2(-25, -45)
                XCTAssertEqual(angle, expected, accuracy: 0.01, token)
            }
            XCTAssertFalse(labelFrames[0].intersects(labelFrames[1]), token)
        }
    }

    func testClassFixtureKeepsMembersRelationsAndEndpointMarkers() {
        let diagram = MermaidParser.parse("""
        classDiagram
        Animal <|-- Duck
        Animal : +int age
        Animal : +isMammal() bool
        class Duck {
            +String beakColor
            +swim()
            +quack()
        }
        Pond o-- Duck : contains
        Duck ..> Food : eats
        """)!
        XCTAssertEqual(diagram.kind, .classDiagram)
        XCTAssertEqual(diagram.node("Duck")?.compartments,
                       [["+String beakColor"], ["+swim()", "+quack()"]])
        XCTAssertEqual(diagram.edges[0].sourceMarker, .inheritance)
        XCTAssertEqual(diagram.edges[1].sourceMarker, .aggregation)
        XCTAssertEqual(diagram.edges[2].line, .dotted)
        XCTAssertEqual(diagram.edges[2].label, "eats")
        let layout = MermaidLayout.compute(diagram)
        XCTAssertGreaterThan(layout.nodes["Duck"]!.height, 100)
        assertValidLayout(diagram)
    }

    func testClassMultiplicityAndAllBasicRelationshipMarkers() {
        let cases: [(String, MermaidMarker?, MermaidMarker?)] = [
            ("<|--", .inheritance, nil), ("--|>", nil, .inheritance),
            ("*--", .composition, nil), ("--*", nil, .composition),
            ("o--", .aggregation, nil), ("--o", nil, .aggregation),
        ]
        for (token, sourceMarker, targetMarker) in cases {
            let edge = MermaidParser.parse("classDiagram\nA \(token) B")!.edges[0]
            XCTAssertEqual(edge.sourceMarker, sourceMarker)
            XCTAssertEqual(edge.targetMarker, targetMarker)
        }
        let edge = MermaidParser.parse("classDiagram\nA \"1\" <-- \"many\" B : feeds")!.edges[0]
        XCTAssertEqual(edge.from, "B")
        XCTAssertEqual(edge.to, "A")
        XCTAssertEqual(edge.arrow, .arrow)
        XCTAssertEqual(edge.sourceArrow, .none)
        XCTAssertEqual(edge.sourceLabel, "many")
        XCTAssertEqual(edge.targetLabel, "1")
        XCTAssertEqual(edge.label, "feeds")
    }

    func testReverseClassRelationsDriveLayoutAndPreserveEndpointLabels() {
        for token in ["<--", "<.."] {
            let diagram = MermaidParser.parse("""
            classDiagram
            direction LR
            A "1" \(token) "many" B : feeds
            """)!
            let edge = diagram.edges[0]
            XCTAssertEqual(edge.from, "B", token)
            XCTAssertEqual(edge.to, "A", token)
            XCTAssertEqual(edge.arrow, .arrow, token)
            XCTAssertEqual(edge.sourceLabel, "many", token)
            XCTAssertEqual(edge.targetLabel, "1", token)
            XCTAssertEqual(edge.line, token == "<.." ? .dotted : .solid, token)
            let layout = MermaidLayout.compute(diagram)
            XCTAssertLessThan(layout.nodes["B"]!.midX, layout.nodes["A"]!.midX, token)
            XCTAssertLessThan(layout.edges[0].start.x, layout.edges[0].end.x, token)
        }
    }

    func testERFixtureKeepsAttributesAndCardinalities() {
        let diagram = MermaidParser.parse("""
        erDiagram
        CUSTOMER ||--o{ ORDER : places
        ORDER ||--|{ LINE_ITEM : contains
        CUSTOMER {
            int id PK
            string name
        }
        ORDER {
            int id PK
            int customer_id FK
        }
        LINE_ITEM {
            int id PK
            int order_id FK
            string product
        }
        """)!
        XCTAssertEqual(diagram.kind, .erDiagram)
        XCTAssertEqual(diagram.nodes.count, 3)
        XCTAssertEqual(diagram.node("ORDER")?.compartments, [["int id PK", "int customer_id FK"]])
        XCTAssertEqual(diagram.edges[0].sourceMarker, .exactlyOne)
        XCTAssertEqual(diagram.edges[0].targetMarker, .zeroOrMore)
        XCTAssertEqual(diagram.edges[1].targetMarker, .oneOrMore)
        assertValidLayout(diagram)
    }

    func testERQuotedEntityAliasAndDottedRelation() {
        let diagram = MermaidParser.parse("""
        erDiagram
        direction LR
        "Customer Account"["Customer"] {
          int id PK "identifier"
        }
        "Customer Account" ||..o{ "Order Line" : "has"
        """)!
        XCTAssertEqual(diagram.direction, .leftToRight)
        XCTAssertEqual(diagram.node("Customer Account")?.label, "Customer")
        XCTAssertEqual(diagram.node("Customer Account")?.compartments, [["int id PK \"identifier\""]])
        XCTAssertEqual(diagram.edges[0].line, .dotted)
        XCTAssertEqual(diagram.edges[0].targetMarker, .zeroOrMore)
        XCTAssertEqual(diagram.edges[0].label, "has")
        assertValidLayout(diagram)
    }

    func testUnsupportedStructuredStatementsFallBackInsteadOfPartialRender() {
        for source in [
            "stateDiagram-v2\nA --> B\nstate composite {",
            "classDiagram\nclass A {\n+int x",
            "classDiagram\nA --> B\nunsupported directive",
            "erDiagram\nA ||--o{ B : has\ninvalid syntax",
            "classDiagram",
            "erDiagram",
        ] {
            XCTAssertNil(MermaidParser.parse(source), source)
        }
    }

    func testOptInMermaidPluginReceivesStructuredFences() {
        let registry = ParserPluginRegistry.builtIns()
        for header in ["classDiagram", "stateDiagram-v2", "erDiagram"] {
            let body = switch header {
            case "classDiagram": "A -- B"
            case "stateDiagram-v2": "A --> B"
            default: "A ||--o{ B : owns"
            }
            let sections = PluginBlockSyntax.sections("```mermaid\n\(header)\n\(body)\n```", registry: registry)
            XCTAssertEqual(sections.count, 1)
            if case let .plugin(plugin, match) = sections[0] {
                XCTAssertEqual(plugin.id, "mermaid")
                XCTAssertNotNil(MermaidParser.parse(match.content))
            } else { XCTFail("Expected opt-in Mermaid plugin") }
        }
        let malformed = MermaidPlugin().parse(["```mermaid", "classDiagram", "unsupported", "```"], at: 0)
        XCTAssertNotNil(malformed)
        XCTAssertNil(MermaidParser.parse(malformed!.content))
    }

    private func assertValidLayout(_ diagram: MermaidDiagram, file: StaticString = #filePath, line: UInt = #line) {
        let layout = MermaidLayout.compute(diagram)
        XCTAssertGreaterThan(layout.size.width, 0, file: file, line: line)
        XCTAssertGreaterThan(layout.size.height, 0, file: file, line: line)
        XCTAssertEqual(layout.nodes.count, diagram.nodes.count, file: file, line: line)
        let frames = Array(layout.nodes.values)
        for (index, frame) in frames.enumerated() {
            XCTAssertGreaterThanOrEqual(frame.minX, 0, file: file, line: line)
            XCTAssertGreaterThanOrEqual(frame.minY, 0, file: file, line: line)
            XCTAssertLessThanOrEqual(frame.maxX, layout.size.width, file: file, line: line)
            XCTAssertLessThanOrEqual(frame.maxY, layout.size.height, file: file, line: line)
            for other in frames.dropFirst(index + 1) {
                XCTAssertFalse(frame.intersects(other), file: file, line: line)
            }
        }
    }
}
