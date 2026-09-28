import XCTest
@testable import SmoothMarkdown

final class MermaidTests: XCTestCase {
    func testFlutterIssue46SubgraphFixtureKeepsContainerAndNodes() {
        let diagram = MermaidParser.parse("""
        graph LR
            %% node definitions
            A[矩形] --> B(圆角矩形)
            B --> C{菱形}
            C -->|条件| D[(圆柱形)]
            E==>|粗线|F
            F-.->|虚线|G
            subgraph 子图
                H[内部节点]
            end
        """)!
        XCTAssertEqual(diagram.kind, .flowchart)
        XCTAssertEqual(diagram.subgraphs, [.init(id: "子图", label: "子图", nodeIDs: ["H"])])
        XCTAssertEqual(diagram.node("H")?.label, "内部节点")
        let layout = MermaidLayout.compute(diagram)
        XCTAssertTrue(layout.subgraphs["子图"]!.contains(layout.nodes["H"]!))
        for node in diagram.nodes where node.id != "H" {
            XCTAssertFalse(layout.subgraphs["子图"]!.intersects(layout.nodes[node.id]!))
        }
        XCTAssertTrue(diagram.voiceOverSummary.contains("Groups: 子图"))
    }

    func testNestedFlowchartSubgraphsContainChildrenAndRejectUnclosedGroups() {
        let source = """
        flowchart TB
        subgraph outer [Outer]
          A[Alpha]
          subgraph inner [Inner]
            B[Beta]
          end
          A --> B
        end
        """
        let diagram = MermaidParser.parse(source)!
        XCTAssertEqual(diagram.subgraphs.map(\.id), ["outer", "inner"])
        XCTAssertEqual(diagram.subgraphs[0].nodeIDs, ["A", "B"])
        XCTAssertEqual(diagram.subgraphs[1].parentID, "outer")
        let layout = MermaidLayout.compute(diagram)
        XCTAssertTrue(layout.subgraphs["outer"]!.contains(layout.subgraphs["inner"]!))
        XCTAssertTrue(layout.subgraphs["inner"]!.contains(layout.nodes["B"]!))
        let canvas = CGRect(origin: .zero, size: layout.size)
        XCTAssertTrue(canvas.contains(layout.subgraphs["outer"]!))
        XCTAssertNil(MermaidParser.parse("flowchart TB\nsubgraph A\nB[Beta]"))
        XCTAssertNil(MermaidParser.parse("flowchart TB\nend"))
    }

    func testFlowchartEdgeCanConnectAGroupWithoutCreatingAFalseNode() {
        let diagram = MermaidParser.parse("""
        graph LR
        subgraph work [Work]
          A[Build]
          B[Test]
          A --> B
        end
        work --> C[Ship]
        """)!
        XCTAssertNil(diagram.node("work"))
        XCTAssertEqual(diagram.edges.last?.from, "work")
        XCTAssertEqual(diagram.edges.last?.to, "C")
        let layout = MermaidLayout.compute(diagram)
        XCTAssertEqual(layout.edges.count, 2)
        XCTAssertEqual(layout.edges.last?.start.x, layout.subgraphs["work"]?.maxX)
        XCTAssertGreaterThan(layout.nodes["C"]!.minX, layout.subgraphs["work"]!.maxX)
    }

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

    func testGanttFixtureSectionsStatusesDependenciesAndLayout() {
        let diagram = MermaidParser.parse("""
        gantt
          title Software Development Timeline
          dateFormat YYYY-MM-DD
          section Planning
            Requirements :done, req, 2024-01-01, 14d
            Design :done, design, after req, 10d
          section Development
            Frontend :active, front, 2024-01-25, 30d
            Backend :crit, back, 2024-01-20, 2024-02-10
            Release :milestone, rel, after back, 0d
        """)!
        XCTAssertEqual(diagram.kind, .gantt)
        XCTAssertEqual(diagram.title, "Software Development Timeline")
        XCTAssertEqual(diagram.ganttTasks.count, 5)
        XCTAssertEqual(diagram.ganttTasks.map(\.section), ["Planning", "Planning", "Development", "Development", "Development"])
        XCTAssertEqual(diagram.ganttTasks.map(\.status), [.done, .done, .active, .critical, .milestone])
        XCTAssertEqual(diagram.ganttTasks[1].dependencies, ["req"])
        XCTAssertEqual(diagram.ganttTasks[1].startDate.timeIntervalSince(diagram.ganttTasks[0].endDate), 86_400, accuracy: 1)
        XCTAssertEqual(diagram.ganttTasks[3].endDate.timeIntervalSince(diagram.ganttTasks[3].startDate), 21 * 86_400, accuracy: 1)
        XCTAssertEqual(diagram.ganttTasks[4].startDate, diagram.ganttTasks[4].endDate)
        let bars = MermaidLayout.ganttBars(diagram)
        XCTAssertEqual(bars.count, 5)
        XCTAssertGreaterThan(bars[1].minX, bars[0].minX)
        XCTAssertGreaterThan(MermaidLayout.compute(diagram).size.width, 500)
        XCTAssertNil(MermaidParser.parse("gantt\ntitle Empty"))
    }

    func testKanbanFixtureYAMLMetadataWIPAndFallback() {
        let diagram = MermaidParser.parse("""
        ---
        config:
          kanban:
            ticketBaseUrl: 'https://example.com/#TICKET#'
        ---
        kanban
          title Product Development
          todo[To Do] wip:1
            task1[Fix bug] @{ assigned: "Alice", ticket: "P-123", priority: "High" }
            task2[Review patch] @{ priority: "Very Low" }
          done[Done]
            task3[Ship it]
        """)!
        XCTAssertEqual(diagram.kind, .kanban)
        XCTAssertEqual(diagram.title, "Product Development")
        XCTAssertEqual(diagram.kanbanTicketBaseURL, "https://example.com/#TICKET#")
        XCTAssertEqual(diagram.kanbanColumns.map(\.title), ["To Do", "Done"])
        XCTAssertTrue(diagram.kanbanColumns[0].isOverLimit)
        XCTAssertEqual(diagram.kanbanColumns[0].tasks.map(\.id), ["task1", "task2"])
        XCTAssertEqual(diagram.kanbanColumns[0].tasks[0].assigned, "Alice")
        XCTAssertEqual(diagram.kanbanColumns[0].tasks[0].ticket, "P-123")
        XCTAssertEqual(diagram.kanbanColumns[0].tasks.map(\.priority), [.high, .veryLow])
        XCTAssertEqual(MermaidLayout.kanbanColumns(diagram).count, 2)
        XCTAssertGreaterThan(MermaidLayout.compute(diagram).size.height, 200)
        XCTAssertNil(MermaidParser.parse("kanban\ntitle Empty Board"))
        XCTAssertEqual(MermaidParser.parse("erDiagram\nA ||--o{ B : owns")?.kind, .erDiagram)
    }

    func testRadarFixturesChineseLabelsOptionsAndFallback() {
        let diagram = MermaidParser.parse("""
        radar-beta
          title 技能评估
          axis 编程["Programming"], 设计, 沟通
          curve 张三["Alice"]{编程:5, 设计:3, 沟通:4}
          curve 李四{3, 5, 2}
          showLegend false
          max 10
          min 0
          graticule circle
          ticks 4
        """)!
        XCTAssertEqual(diagram.kind, .radar)
        XCTAssertEqual(diagram.title, "技能评估")
        XCTAssertEqual(diagram.radarAxes.map(\.label), ["Programming", "设计", "沟通"])
        XCTAssertEqual(diagram.radarCurves.map(\.label), ["Alice", "李四"])
        XCTAssertEqual(diagram.radarCurves[0].values, [5, 3, 4])
        XCTAssertFalse(diagram.radarShowLegend)
        XCTAssertEqual(diagram.radarMaximum, 10)
        XCTAssertEqual(diagram.radarMinimum, 0)
        XCTAssertEqual(diagram.radarGraticule, .circle)
        XCTAssertEqual(diagram.radarTicks, 4)
        XCTAssertGreaterThan(MermaidLayout.compute(diagram).size.width, 0)
        XCTAssertNotEqual(MermaidLayout.radarPoint(index: 0, count: 3, radius: 100),
                          MermaidLayout.radarPoint(index: 1, count: 3, radius: 100))
        XCTAssertNil(MermaidParser.parse("radar-beta\ncurve c1{1,2,3}"))
        XCTAssertNil(MermaidParser.parse("radar-beta\naxis A, B, C"))
    }

    func testXYChartFixturesMixedSeriesOrientationAndFallback() {
        let diagram = MermaidParser.parse("""
        xychart-beta
          title "Sales Revenue"
          x-axis ["Q1 2024", "Q2 2024", "Q3 2024"]
          y-axis "Revenue" -10 --> 100
          bar [23, 45, 67]
          line [20, -3.4, .98]
        """)!
        XCTAssertEqual(diagram.kind, .xyChart)
        XCTAssertEqual(diagram.title, "Sales Revenue")
        XCTAssertEqual(diagram.xyCategories, ["Q1 2024", "Q2 2024", "Q3 2024"])
        XCTAssertEqual(diagram.xyYAxisTitle, "Revenue")
        XCTAssertEqual(diagram.xyYAxisMinimum, -10)
        XCTAssertEqual(diagram.xyYAxisMaximum, 100)
        XCTAssertEqual(diagram.xySeries.map(\.type), [.bar, .line])
        XCTAssertEqual(diagram.xySeries[1].values, [20, -3.4, 0.98])
        XCTAssertGreaterThan(MermaidLayout.compute(diagram).size.height, 0)
        XCTAssertGreaterThan(MermaidLayout.xyPlotFrame(diagram).width, 0)
        let horizontal = MermaidParser.parse("xychart horizontal\nx-axis [A, B]\nbar [10, 20]")!
        XCTAssertEqual(horizontal.xyOrientation, .horizontal)
        XCTAssertNil(MermaidParser.parse("xychart-beta\nx-axis [A, B]"))
        XCTAssertEqual(MermaidParser.parse("erDiagram\nA ||--o{ B : owns")?.kind, .erDiagram)
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
