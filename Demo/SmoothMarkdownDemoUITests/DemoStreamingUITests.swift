import XCTest

final class DemoStreamingUITests: XCTestCase {
    func testFlutterStreamingControlsProgressCompletionAndReset() {
        let app = XCUIApplication()
        app.launch()
        app.buttons["open-examples"].tap()
        let entry = app.buttons["feature-streaming"]
        for _ in 0..<15 where !entry.isHittable { app.swipeUp() }
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.tap()

        let start = app.buttons["stream-demo-start"]
        let reset = app.buttons["stream-demo-reset"]
        let status = app.staticTexts["stream-demo-status"]
        let emptyMessage = app.staticTexts["Click \"Start Stream\" to begin"]
        XCTAssertTrue(emptyMessage.waitForExistence(timeout: 5))
        XCTAssertEqual(status.label, "Ready")
        XCTAssertTrue(start.isEnabled)
        XCTAssertFalse(reset.isEnabled)

        start.tap()
        XCTAssertFalse(emptyMessage.exists)
        XCTAssertFalse(start.isEnabled)
        XCTAssertTrue(reset.isEnabled)
        XCTAssertTrue(status.label.hasPrefix("Streaming "))
        let complete = NSPredicate(format: "label == %@", "Complete 48/48 chunks")
        expectation(for: complete, evaluatedWith: status)
        waitForExpectations(timeout: 12)
        XCTAssertFalse(start.isEnabled)

        reset.tap()
        XCTAssertEqual(status.label, "Ready")
        XCTAssertTrue(emptyMessage.exists)
        XCTAssertTrue(start.isEnabled)
        XCTAssertFalse(reset.isEnabled)

        start.tap()
        XCTAssertTrue(status.label.hasPrefix("Streaming "))
        reset.tap()
        XCTAssertEqual(status.label, "Ready")
        XCTAssertTrue(emptyMessage.exists)
    }
}
