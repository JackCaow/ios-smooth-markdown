import XCTest

final class ReaderImageRangeUITests: XCTestCase {
    func testNativeDragSelectionCrossesTwoBundledImages() {
        let app = XCUIApplication()
        app.launchArguments = ["--reader-multi-image-range-fixture"]
        app.launch()

        let reader = app.textViews["reader-native-image-selection"]
        XCTAssertTrue(reader.waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons.matching(identifier: "Bundled vector").count, 2)
        let start = reader.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.06))
        let end = reader.coordinate(withNormalizedOffset: CGVector(dx: 0.38, dy: 0.96))
        start.press(forDuration: 1, thenDragTo: end)
        let selected = XCTAttachment(screenshot: app.screenshot())
        selected.name = "Native selection across two images"
        selected.lifetime = .keepAlways
        add(selected)
        let copy = app.menuItems["Copy"]
        XCTAssertTrue(copy.waitForExistence(timeout: 5))
        copy.tap()
        app.buttons["Show clipboard"].tap()
        let copied = app.staticTexts["image-range-clipboard"].label
        XCTAssertTrue(copied.contains("Before"), copied)
        XCTAssertTrue(copied.contains("Middle"), copied)
        XCTAssertTrue(copied.contains("After"), copied)
        XCTAssertFalse(copied.contains("Bundled vector"), copied)
    }

    func testNativeDragSelectionCrossesBundledImage() {
        let app = XCUIApplication()
        app.launchArguments = ["--reader-image-range-fixture"]
        app.launch()

        let reader = app.textViews["reader-native-image-selection"]
        XCTAssertTrue(reader.waitForExistence(timeout: 10))
        let image = app.buttons["Bundled vector"]
        XCTAssertTrue(image.waitForExistence(timeout: 10))
        image.tap()
        XCTAssertTrue(app.staticTexts["Image taps: 1"].exists)

        let start = reader.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.13))
        // The image reserves a full line fragment. End well inside the final
        // paragraph rather than on the line break immediately after the image.
        let end = reader.coordinate(withNormalizedOffset: CGVector(dx: 0.40, dy: 0.94))
        start.press(forDuration: 1, thenDragTo: end)
        let selected = XCTAttachment(screenshot: app.screenshot())
        selected.name = "Native text selection spanning image"
        selected.lifetime = .keepAlways
        add(selected)
        let copy = app.menuItems["Copy"]
        XCTAssertTrue(copy.waitForExistence(timeout: 5))
        copy.tap()
        app.buttons["Show clipboard"].tap()
        let copied = app.staticTexts["image-range-clipboard"].label
        XCTAssertTrue(copied.contains("Before"), copied)
        XCTAssertTrue(copied.contains("After"), copied)
        XCTAssertFalse(copied.contains("Bundled vector"), copied)
    }

    func testImageTapAndLongPressRangeCopy() {
        let app = XCUIApplication()
        app.launchArguments = ["--reader-image-range-fixture"]
        app.launch()

        let image = app.buttons["Bundled vector"]
        XCTAssertTrue(image.waitForExistence(timeout: 10))
        image.tap()
        XCTAssertTrue(app.staticTexts["Image taps: 1"].exists)

        image.press(forDuration: 1)
        let select = app.buttons["Select surrounding content"]
        XCTAssertTrue(select.waitForExistence(timeout: 5))
        select.tap()

        let first = app.buttons["reader-image-range-block-0"]
        let last = app.buttons["reader-image-range-block-2"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        first.tap()
        last.tap()
        let copy = app.buttons["reader-image-range-copy"]
        XCTAssertTrue(copy.isEnabled)
        copy.tap()
        app.buttons["Show clipboard"].tap()
        XCTAssertTrue(app.staticTexts["Copied: Before image.\nAfter image."].exists)
    }

    func testImageRangeCopiesCharacterEndpointsInAdjacentText() {
        let app = XCUIApplication()
        app.launchArguments = ["--reader-image-range-fixture"]
        app.launch()

        let image = app.buttons["Bundled vector"]
        XCTAssertTrue(image.waitForExistence(timeout: 10))
        image.press(forDuration: 1)
        let select = app.buttons["Select surrounding content"]
        XCTAssertTrue(select.waitForExistence(timeout: 5))
        select.tap()

        let textSegments = app.textViews.matching(identifier: "reader-character-endpoint-text")
        XCTAssertTrue(textSegments.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(textSegments.count, 2)
        textSegments.element(boundBy: 0).coordinate(withNormalizedOffset: CGVector(dx: 0.10, dy: 0.5)).tap()
        textSegments.element(boundBy: 1).coordinate(withNormalizedOffset: CGVector(dx: 0.10, dy: 0.5)).tap()

        let copy = app.buttons["reader-image-range-copy"]
        XCTAssertTrue(copy.isEnabled)
        copy.tap()
        app.buttons["Show clipboard"].tap()
        let copied = app.staticTexts["image-range-clipboard"].label
        XCTAssertTrue(copied.hasPrefix("Copied: "))
        XCTAssertTrue(copied.contains("image.\n"), copied)
        XCTAssertFalse(copied.contains("Before image."), copied)
        XCTAssertFalse(copied.contains("After image."), copied)
        XCTAssertFalse(copied.contains("Bundled vector"), copied)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Reader image character endpoints and copied text"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
