import XCTest

final class EditorHostIOUITests: XCTestCase {
    func testFileMenuReachesPickerImportAndExportCallbacks() {
        let app = XCUIApplication()
        app.launchArguments = ["--host-io-fixture"]
        app.launch()

        let source = app.textViews["markdown-source"]
        XCTAssertTrue(source.waitForExistence(timeout: 10))
        XCTAssertEqual(source.value as? String, "Intro")

        choose("Insert Image", in: app)
        XCTAssertEqual(source.value as? String, "Intro\n\n![Picked](assets/fixture.png)")
        XCTAssertTrue(app.staticTexts["Host IO: imagePick-completed"].exists)
        app.buttons["Undo"].tap()
        XCTAssertEqual(source.value as? String, "Intro")

        choose("Import Markdown", in: app)
        XCTAssertEqual(source.value as? String, "Intro\n\n# Imported")
        XCTAssertTrue(app.staticTexts["Host IO: markdownImport-completed"].exists)
        app.buttons["Undo"].tap()
        XCTAssertEqual(source.value as? String, "Intro")

        choose("Export Markdown", in: app)
        XCTAssertTrue(app.staticTexts["Exported: Intro"].exists)
        XCTAssertEqual(source.value as? String, "Intro")
    }

    private func choose(_ title: String, in app: XCUIApplication) {
        app.buttons["File"].tap()
        let action = app.buttons[title]
        XCTAssertTrue(action.waitForExistence(timeout: 5))
        action.tap()
    }
}
