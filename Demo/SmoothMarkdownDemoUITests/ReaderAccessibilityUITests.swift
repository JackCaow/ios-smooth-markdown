import XCTest

final class ReaderAccessibilityUITests: XCTestCase {
    func testReaderLabelsAndActionTargets() {
        let app = XCUIApplication()
        app.launchArguments = ["--accessibility-fixture"]
        app.launch()

        let heading = app.staticTexts["Accessible heading"]
        XCTAssertTrue(heading.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["First list item"].exists)
        XCTAssertTrue(app.staticTexts["Quoted guidance"].exists)
        XCTAssertTrue(app.staticTexts["Alpha"].exists)
        print("AX_TABLE \(app.staticTexts["42"].debugDescription)")
        XCTAssertTrue(app.staticTexts["Footnote explanation."].exists)
        print("AX_HEADING \(heading.debugDescription)")

        let image = app.buttons["Bundled vector"]
        reveal(image, in: app)
        XCTAssertTrue(image.isHittable)
        XCTAssertGreaterThanOrEqual(image.frame.width, 44)
        XCTAssertGreaterThanOrEqual(image.frame.height, 44)
        image.tap()
        XCTAssertTrue(app.staticTexts["Image taps: 1"].exists)
        let inlineImage = app.buttons["Inline icon"]
        reveal(inlineImage, in: app)
        XCTAssertGreaterThanOrEqual(inlineImage.frame.width, 44)
        XCTAssertGreaterThanOrEqual(inlineImage.frame.height, 44)

        let details = app.buttons["More information"]
        reveal(details, in: app)
        XCTAssertTrue(details.isHittable)
        XCTAssertGreaterThanOrEqual(details.frame.height, 44)
        XCTAssertEqual(details.value as? String, "Collapsed")
        details.tap()
        XCTAssertEqual(details.value as? String, "Expanded")
        XCTAssertTrue(app.staticTexts["Expanded explanation."].exists)

        let copy = app.buttons["Copy code"]
        reveal(copy, in: app)
        XCTAssertTrue(copy.isHittable)
        XCTAssertGreaterThanOrEqual(copy.frame.width, 44)
        XCTAssertGreaterThanOrEqual(copy.frame.height, 44)

        let diagram = app.otherElements["mermaid-diagram"]
        reveal(diagram, in: app)
        XCTAssertTrue(diagram.exists)
        XCTAssertTrue(diagram.label.contains("Work split"))
        XCTAssertTrue(diagram.label.contains("Reader 60"))
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 where !element.isHittable { app.swipeUp() }
    }
}
