import XCTest

final class DemoEditorUITests: XCTestCase {
    func testFlutterEditorDemoHostCallbacksAndSource() {
        let app = XCUIApplication()
        app.launch()
        app.buttons["open-demo-editor"].tap()

        let fileMenu = app.buttons["File"]
        XCTAssertTrue(fileMenu.waitForExistence(timeout: 10))
        XCTAssertTrue(app.segmentedControls.buttons["Blocks"].isSelected)

        fileMenu.tap()
        app.buttons["Export Markdown"].tap()
        let export = app.staticTexts["editor-last-export"]
        XCTAssertTrue(export.waitForExistence(timeout: 5))
        XCTAssertTrue(export.label.hasPrefix("Last export: "))
        XCTAssertFalse(export.label.contains("Last export: 0 characters"))

        fileMenu.tap()
        app.buttons["Export PDF"].tap()
        XCTAssertTrue(app.staticTexts["editor-host-message"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["editor-host-message"].label, "PDF export callback requested")
        XCTAssertFalse(export.label.contains("Last export: 0 characters"))

        fileMenu.tap()
        app.buttons["Import Markdown"].tap()
        app.segmentedControls.buttons["Source"].tap()
        let source = app.textViews["markdown-source"]
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        waitForSource("## Imported markdown", in: source)

        fileMenu.tap()
        app.buttons["Insert Image"].tap()
        waitForSource("![Sample image](https://picsum.photos/640/360", in: source)
    }

    private func waitForSource(_ fragment: String, in source: XCUIElement) {
        let predicate = NSPredicate(format: "value CONTAINS %@", fragment)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: source)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed)
    }
}
