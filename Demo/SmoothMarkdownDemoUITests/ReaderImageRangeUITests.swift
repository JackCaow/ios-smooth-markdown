import XCTest

final class ReaderImageRangeUITests: XCTestCase {
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
}
