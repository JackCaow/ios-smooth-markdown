import XCTest

final class PerformanceUITests: XCTestCase {
    func testStaticReaderScroll() {
        let app = XCUIApplication()
        app.launch()
        app.buttons["Perf"].tap()
        XCTAssertTrue(app.staticTexts["68,282 B"].waitForExistence(timeout: 10))
        let firstAppear = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'First appear:'")).firstMatch
        XCTAssertTrue(firstAppear.waitForExistence(timeout: 10))
        print("PERF_UI static \(firstAppear.label)")
        keepScreenshot(app, named: "Static first screen")

        app.buttons["Record frames"].tap()
        let reader = app.scrollViews.firstMatch
        XCTAssertTrue(reader.waitForExistence(timeout: 10))
        for _ in 0..<12 { reader.swipeUp() }
        app.buttons["Stop frames"].tap()
        let summary = app.staticTexts["frameSummary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 10))
        print("PERF_UI staticScroll \(summary.label)")
        keepScreenshot(app, named: "Static after twelve swipes")
    }

    func testRapidStreamCompletes() {
        measureStream(throttleMillis: "50")
    }

    func testRapidStreamWithLongerThrottleCompletes() {
        measureStream(throttleMillis: "150")
    }

    private func measureStream(throttleMillis: String) {
        let app = XCUIApplication()
        app.launchEnvironment["SMOOTH_PERF_THROTTLE_MS"] = throttleMillis
        app.launch()
        app.buttons["Perf"].tap()
        app.segmentedControls.buttons["Rapid stream"].tap()
        XCTAssertTrue(app.staticTexts["68,282 B"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["\(throttleMillis) ms"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Flutter Smooth Markdown"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["Complete 68,282 B"].waitForExistence(timeout: 30))
        app.buttons["Stop frames"].tap()
        let summary = app.staticTexts["frameSummary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 10))
        print("PERF_UI rapidStream throttle=\(throttleMillis) \(summary.label)")
        let firstAppear = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'First appear:'")).firstMatch
        print("PERF_UI rapidStream throttle=\(throttleMillis) \(firstAppear.label)")
        keepScreenshot(app, named: "Rapid stream \(throttleMillis) ms after completion")
    }

    private func keepScreenshot(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
