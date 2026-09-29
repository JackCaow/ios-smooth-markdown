import XCTest

final class ReaderCodeRangeUITests: XCTestCase {
    func testBuiltinCopyCallbackAndCodeRangeCopy() {
        let app = XCUIApplication()
        app.launchArguments = ["--reader-code-range-fixture"]
        app.launch()

        let codeCopy = app.buttons["Copy code"]
        XCTAssertTrue(codeCopy.waitForExistence(timeout: 10))
        codeCopy.tap()
        XCTAssertTrue(app.staticTexts["Code callbacks: 1"].exists)
        XCTAssertEqual(app.staticTexts["code-copy-callback-payload"].label,
                       "Code callback payload: let answer = 42↵|swift")
        app.buttons["Show clipboard"].tap()
        XCTAssertEqual(app.staticTexts["code-range-clipboard"].label, "Copied: let answer = 42\n")

        XCTAssertTrue(codeCopy.waitForExistence(timeout: 5))
        codeCopy.press(forDuration: 1)
        let select = app.buttons["Select surrounding content"]
        XCTAssertTrue(select.waitForExistence(timeout: 5))
        select.tap()
        app.buttons["reader-image-range-block-0"].tap()
        app.buttons["reader-image-range-block-2"].tap()
        let rangeCopy = app.buttons["reader-image-range-copy"]
        XCTAssertTrue(rangeCopy.isEnabled)
        rangeCopy.tap()
        app.buttons["Show clipboard"].tap()
        XCTAssertTrue(app.staticTexts["Copied: Before code.\nlet answer = 42\nAfter code."].exists)
        XCTAssertTrue(app.staticTexts["Code callbacks: 1"].exists)

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Reader code range and callback"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testCodeTextStillSupportsNativePartialCopy() {
        let app = XCUIApplication()
        app.launchArguments = ["--reader-code-range-fixture"]
        app.launch()

        let codeText = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "let answer = 42")).firstMatch
        XCTAssertTrue(codeText.waitForExistence(timeout: 10))
        codeText.press(forDuration: 1)
        let copy = app.menuItems["Copy"]
        XCTAssertTrue(copy.waitForExistence(timeout: 5))
        copy.tap()
        app.buttons["Show clipboard"].tap()
        let selected = app.staticTexts["code-range-clipboard"].label
        XCTAssertTrue(selected.contains("answer"))
        XCTAssertFalse(selected.contains("Before code."))
        XCTAssertFalse(selected.contains("After code."))
    }

    func testHostCodeBuilderKeepsItsActionAndSeparateBoundary() {
        let app = XCUIApplication()
        app.launchArguments = ["--reader-code-custom-fixture"]
        app.launch()

        let hostAction = app.buttons["Host code action"]
        XCTAssertTrue(hostAction.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Host code: let answer = 42"].exists)
        hostAction.tap()
        XCTAssertTrue(app.staticTexts["Host taps: 1"].exists)
        XCTAssertFalse(app.buttons["Select surrounding content"].exists)
        XCTAssertFalse(app.buttons["reader-image-range-copy"].exists)
    }

    func testHiddenCopyButtonKeepsCodeOutsideRange() {
        let app = XCUIApplication()
        app.launchArguments = ["--reader-code-no-copy-fixture"]
        app.launch()

        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "let answer = 42"))
            .firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Copy code"].exists)
        XCTAssertFalse(app.buttons["Select surrounding content"].exists)
        XCTAssertFalse(app.buttons["reader-image-range-copy"].exists)
    }
}
