import XCTest

final class MermaidSubgraphUITests: XCTestCase {
    func testStructuredDemoShowsGroupedFlowchart() {
        let app = XCUIApplication()
        app.launch()
        app.buttons["Structured"].tap()

        let diagram = app.otherElements["mermaid-diagram"].firstMatch
        XCTAssertTrue(diagram.waitForExistence(timeout: 10))
        XCTAssertTrue(diagram.label.contains("Groups: Grouped work"))
        XCTAssertTrue(diagram.label.contains("Inside"))

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Mermaid subgraph flowchart"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
