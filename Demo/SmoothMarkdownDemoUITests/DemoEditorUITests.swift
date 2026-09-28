import XCTest

final class DemoEditorUITests: XCTestCase {
    func testFindAndFocusControlsOnFlutterEditorDemo() {
        let app = XCUIApplication()
        app.launch()
        app.buttons["open-demo-editor"].tap()

        let focus = app.buttons["editor-focus-toggle"]
        XCTAssertTrue(focus.waitForExistence(timeout: 10))
        focus.tap()
        XCTAssertFalse(app.segmentedControls.buttons["Blocks"].exists)
        XCTAssertFalse(app.buttons["File"].exists)
        XCTAssertFalse(app.buttons["editor-find-open"].exists)
        XCTAssertTrue(app.staticTexts["Scratch-style editor preview"].exists)
        focus.tap()
        XCTAssertTrue(app.segmentedControls.buttons["Blocks"].exists)

        app.buttons["editor-find-open"].tap()
        let find = app.textFields["editor-find-field"]
        XCTAssertTrue(find.waitForExistence(timeout: 5))
        find.tap()
        find.typeText("Mermaid")
        XCTAssertEqual(app.staticTexts["editor-find-count"].label, "1/2")
        focus.tap()
        XCTAssertTrue(find.exists)
        focus.tap()
        app.buttons["editor-find-next"].tap()
        XCTAssertTrue(app.textViews["markdown-source"].waitForExistence(timeout: 5))
        app.buttons["editor-find-close"].tap()
        XCTAssertFalse(find.exists)
    }

    func testCommandFFindsInFlutterEditorDemo() {
        let app = XCUIApplication()
        app.launch()
        app.buttons["open-demo-editor"].tap()

        XCTAssertTrue(app.buttons["editor-find-open"].waitForExistence(timeout: 10))
        app.typeKey("f", modifierFlags: .command)
        XCTAssertTrue(app.textFields["editor-find-field"].waitForExistence(timeout: 5))
    }

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
