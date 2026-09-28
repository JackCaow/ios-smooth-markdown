import XCTest

final class InlineMarkEditorUITests: XCTestCase {
    func testBlocksBoldLinkSourceAndUndo() {
        let app = XCUIApplication()
        app.launchArguments = ["--inline-editor-fixture"]
        app.launch()

        let paragraph = app.textViews["paragraph-block-0"]
        XCTAssertTrue(paragraph.waitForExistence(timeout: 10))

        selectFixtureWord(in: paragraph, app: app)
        let bold = app.buttons["Bold selection"]
        XCTAssertTrue(bold.isEnabled)
        bold.tap()
        assertSource("**Alpha**", in: app)

        app.buttons["Undo"].tap()
        assertSource("Alpha", in: app)

        app.segmentedControls.buttons["Blocks"].tap()
        selectFixtureWord(in: paragraph, app: app)
        let link = app.buttons["Link selection"]
        XCTAssertTrue(link.isEnabled)
        link.tap()

        let url = app.alerts["Link URL"].textFields.firstMatch
        XCTAssertTrue(url.waitForExistence(timeout: 5))
        url.tap()
        url.typeText("example.com")
        app.alerts["Link URL"].buttons["Apply"].tap()
        assertSource("[Alpha](https://example.com)", in: app)

        app.buttons["Undo"].tap()
        assertSource("Alpha", in: app)
    }

    private func selectFixtureWord(in paragraph: XCUIElement, app: XCUIApplication) {
        XCTAssertTrue(paragraph.waitForExistence(timeout: 5))
        paragraph.doubleTap()
        XCTAssertTrue(app.buttons["Bold selection"].isEnabled,
                      "Double-tapping the one-word fixture should select Alpha")
    }

    private func assertSource(_ expected: String, in app: XCUIApplication) {
        app.segmentedControls.buttons["Source"].tap()
        let source = app.textViews["markdown-source"]
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        XCTAssertEqual(source.value as? String, expected)
    }
}
