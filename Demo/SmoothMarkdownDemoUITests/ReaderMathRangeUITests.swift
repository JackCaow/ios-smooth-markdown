import XCTest

final class ReaderMathRangeUITests: XCTestCase {
    func testLongPressFormulaCopiesSurroundingProseAndLatex() {
        let app = XCUIApplication()
        app.launchArguments = ["--reader-math-range-fixture"]
        app.launch()

        let formula = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "E=mc^2")).firstMatch
        XCTAssertTrue(formula.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Before formula."].exists)
        XCTAssertTrue(app.staticTexts["After formula."].exists)
        formula.press(forDuration: 1)
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
        XCTAssertTrue(app.staticTexts["Copied: Before formula.\nE=mc^2\nAfter formula."].exists)

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Reader math range and copied LaTeX"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testStandaloneFormulaHasCopyActionAndAccessibilityLabel() {
        let app = XCUIApplication()
        app.launchArguments = ["--reader-math-standalone-fixture"]
        app.launch()

        let formula = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "E=mc^2")).firstMatch
        XCTAssertTrue(formula.waitForExistence(timeout: 10))
        formula.press(forDuration: 1)
        let copy = app.buttons["Copy formula"]
        XCTAssertTrue(copy.waitForExistence(timeout: 5))
        copy.tap()
        app.buttons["Show clipboard"].tap()
        XCTAssertTrue(app.staticTexts["Copied: E=mc^2"].exists)
    }
}
