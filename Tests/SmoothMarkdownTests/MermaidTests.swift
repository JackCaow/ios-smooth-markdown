import XCTest
@testable import SmoothMarkdown

final class MermaidTests: XCTestCase {
    func testFlowchartShapesEdgesDirectionsAndComments() {
        let source = """
        flowchart LR
        %% ignored
        A[Start] --> B{Decision}
        B -->|Yes| C((Done))
        B -.->|No| D(Retry)
        D ==> A
        """
        let diagram = MermaidParser.parse(source)
        XCTAssertEqual(diagram?.kind, .flowchart)
        XCTAssertEqual(diagram?.direction, .leftToRight)
        XCTAssertEqual(diagram?.nodes.count, 4)
        XCTAssertEqual(diagram?.node("A")?.label, "Start")
        XCTAssertEqual(diagram?.node("B")?.shape, .diamond)
        XCTAssertEqual(diagram?.node("C")?.shape, .circle)
        XCTAssertEqual(diagram?.node("D")?.shape, .rounded)
        XCTAssertEqual(diagram?.edges.count, 4)
        XCTAssertEqual(diagram?.edges[1].label, "Yes")
        XCTAssertEqual(diagram?.edges[2].line, .dotted)
        XCTAssertEqual(diagram?.edges[3].line, .thick)
        XCTAssertEqual(MermaidParser.parse("graph BT\nA --> B")?.direction, .bottomToTop)
        XCTAssertEqual(MermaidParser.parse("graph RL\nA --> B")?.direction, .rightToLeft)
        XCTAssertNil(MermaidParser.parse("pie\ntitle Empty"))
    }

    func testFlowchartChainAndLayoutAreDeterministic() {
        let diagram = MermaidParser.parse("graph TD\nA[Start] --> B{Choose} --> C[Done]")!
        XCTAssertEqual(diagram.edges.count, 2)
        let first = MermaidLayout.compute(diagram)
        let second = MermaidLayout.compute(diagram)
        XCTAssertEqual(first.nodes, second.nodes)
        XCTAssertGreaterThan(first.nodes["B"]!.midY, first.nodes["A"]!.midY)
        XCTAssertGreaterThan(first.nodes["C"]!.midY, first.nodes["B"]!.midY)
        XCTAssertEqual(first.edges.count, 2)
        XCTAssertGreaterThan(first.size.height, 0)
        let reversed = MermaidLayout.compute(MermaidParser.parse("graph BT\nA --> B")!)
        XCTAssertGreaterThan(reversed.nodes["A"]!.midY, reversed.nodes["B"]!.midY)
    }

    func testSequenceParticipantsMessagesAndLayout() {
        let diagram = MermaidParser.parse("""
        sequenceDiagram
        actor U as User
        participant S as Server
        U->>S: Request
        S-->>U: Response
        U-xS: Cancel
        """)!
        XCTAssertEqual(diagram.kind, .sequence)
        XCTAssertEqual(diagram.nodes.map(\.id), ["U", "S"])
        XCTAssertEqual(diagram.node("U")?.label, "User")
        XCTAssertEqual(diagram.node("U")?.participantType, .actor)
        XCTAssertEqual(diagram.edges.map(\.label), ["Request", "Response", "Cancel"])
        XCTAssertEqual(diagram.edges[1].line, .dotted)
        XCTAssertEqual(diagram.edges[2].arrow, .cross)
        let layout = MermaidLayout.compute(diagram)
        XCTAssertGreaterThan(layout.nodes["S"]!.midX, layout.nodes["U"]!.midX)
        XCTAssertGreaterThan(layout.edges[1].start.y, layout.edges[0].start.y)
    }

    func testPieFixturesOptionsValuesAndUnsupportedFallback() {
        let diagram = MermaidParser.parse("""
        pie showData
          title Favorite Pets
          %% ignored
          "Dogs" : 386
          'Cats' : 85
          Rats : 15.5
          Zero : 0
          Negative : -10
        """)!
        XCTAssertEqual(diagram.kind, .pie)
        XCTAssertEqual(diagram.title, "Favorite Pets")
        XCTAssertTrue(diagram.showData)
        XCTAssertEqual(diagram.pieSlices.map(\.label), ["Dogs", "Cats", "Rats"])
        XCTAssertEqual(diagram.pieSlices.map(\.value), [386, 85, 15.5])
        XCTAssertEqual(MermaidLayout.compute(diagram).edges.count, 0)
        XCTAssertGreaterThan(MermaidLayout.compute(diagram).size.height, 0)
        XCTAssertNil(MermaidParser.parse("pie\ntitle Empty Pie"))
        XCTAssertNil(MermaidParser.parse("pie\nInvalid : nope"))
    }

    func testTimelineFixturesContinuationsDescriptionsAndLayout() {
        let diagram = MermaidParser.parse("""
        timeline
          title Product History
          2002 : LinkedIn
          2004 : Facebook
               : Google
               : MySpace
          2005-2006 : YouTube
                      Major update
        """)!
        XCTAssertEqual(diagram.kind, .timeline)
        XCTAssertEqual(diagram.title, "Product History")
        XCTAssertEqual(diagram.timelineSections.map(\.title), ["2002", "2004", "2005-2006"])
        XCTAssertEqual(diagram.timelineSections[1].events.map(\.title), ["Facebook", "Google", "MySpace"])
        XCTAssertEqual(diagram.timelineSections[2].events[0].description, "Major update")
        XCTAssertGreaterThan(MermaidLayout.compute(diagram).size.width, 500)
        XCTAssertNil(MermaidParser.parse("timeline\ntitle Empty Timeline"))
    }

    func testMermaidFencePluginAndOrdinaryFenceFallback() throws {
        let registry = ParserPluginRegistry.builtIns()
        let source = """
        Intro
        ~~~mermaid theme=dark
        graph LR
        A --> B
        ~~~
        Outro
        """
        let sections = PluginBlockSyntax.sections(source, registry: registry)
        XCTAssertEqual(sections.count, 3)
        if case let .plugin(plugin, match) = sections[1] {
            XCTAssertEqual(plugin.id, "mermaid")
            XCTAssertEqual(match.attributes["fence"], "~~~")
            XCTAssertEqual(match.attributes["theme"], "dark")
            XCTAssertEqual(match.content, "graph LR\nA --> B")
            XCTAssertNotNil(MermaidParser.parse(match.content))
        } else { XCTFail("Expected Mermaid plugin section") }
        XCTAssertEqual(PluginBlockSyntax.sections("```swift\ngraph LR\nA --> B\n```", registry: registry).count, 1)
        XCTAssertNil(MermaidPlugin().parse(["```mermaid", "```"], at: 0))
        XCTAssertEqual(PluginBlockSyntax.sections("```mermaid\nsequenceDiagram\nA->>B: Hi", registry: registry).count, 1)
    }
}
