import XCTest

final class CrossBlockEditorUITests: XCTestCase {
    func testSelectCopyDeleteAndUndoInBlocks() {
        let app = XCUIApplication()
        app.launchArguments = ["--cross-block-editor-fixture"]
        app.launch()

        let start = app.buttons["block-range-block-0"]
        let end = app.buttons["block-range-block-1"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        start.tap()
        end.tap()

        let copy = app.buttons["block-range-copy"]
        XCTAssertTrue(copy.waitForExistence(timeout: 5))
        copy.tap()
        XCTAssertTrue(app.staticTexts["block-range-copy-feedback"].exists)

        let delete = app.buttons["block-range-delete"]
        XCTAssertTrue(delete.isEnabled)
        delete.tap()
        app.segmentedControls.buttons["Source"].tap()
        let source = app.textViews["markdown-source"]
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        XCTAssertEqual(source.value as? String, "Third")

        app.buttons["Undo"].tap()
        XCTAssertEqual(source.value as? String, "First\n\nSecond\n\nThird")
    }
}
