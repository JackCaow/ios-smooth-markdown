import XCTest

final class ReaderTableRangeUITests: XCTestCase {
    func testLongPressTableSelectsAcrossProseAndCopiesCells() {
        let app = XCUIApplication()
        app.launchArguments = ["--reader-table-range-fixture"]
        app.launch()

        let header = app.staticTexts["Name"]
        XCTAssertTrue(header.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["42"].exists)
        XCTAssertTrue(app.staticTexts["Before table."].exists)
        XCTAssertTrue(app.staticTexts["After table."].exists)
        header.press(forDuration: 1)
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
        XCTAssertTrue(app.staticTexts["Copied: Before table.\nName\tValue\nAlpha\t42\nAfter table."].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Reader table range and copied cells"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
