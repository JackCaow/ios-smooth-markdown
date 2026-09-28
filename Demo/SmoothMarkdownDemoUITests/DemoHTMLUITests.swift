import XCTest

final class DemoHTMLUITests: XCTestCase {
    func testFlutterHTMLToggleStreamAndStopReturnsToFullDocument() {
        let app = XCUIApplication()
        app.launch()
        app.buttons["open-examples"].tap()
        let entry = app.buttons["feature-html"]
        for _ in 0..<15 where !entry.isHittable { app.swipeUp() }
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.tap()

        let toggle = app.switches["html-demo-toggle"]
        let control = app.buttons["html-demo-stream-control"]
        let status = app.staticTexts["html-demo-status"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? String, "1")
        XCTAssertEqual(status.label, "Ready · HTML on")
        XCTAssertTrue(app.scrollViews["html-demo-reader"].exists)

        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(status.label, "Ready · HTML off")
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(status.label, "Ready · HTML on")

        control.tap()
        XCTAssertTrue(status.label.hasPrefix("Streaming "))
        XCTAssertTrue(control.label.contains("Stop streaming"))

        control.tap()
        XCTAssertEqual(status.label, "Ready · HTML on")
        XCTAssertTrue(app.scrollViews["html-demo-reader"].exists)

        control.tap()
        XCTAssertTrue(status.label.hasPrefix("Streaming "))
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertTrue(status.label.hasPrefix("Streaming "))
        XCTAssertTrue(status.label.hasSuffix("HTML off"))
        XCTAssertTrue(control.label.contains("Stop streaming"))
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertTrue(status.label.hasPrefix("Streaming "))
        XCTAssertTrue(status.label.hasSuffix("HTML on"))
        XCTAssertTrue(app.scrollViews["html-demo-reader"].exists)
        control.tap()
        XCTAssertEqual(status.label, "Ready · HTML on")
    }
}
