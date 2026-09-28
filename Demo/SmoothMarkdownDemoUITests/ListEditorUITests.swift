import XCTest

final class ListEditorUITests: XCTestCase {
    func testTaskToggleSourceUndoAndOrderedTextEdit() {
        let app = XCUIApplication()
        app.launchArguments = ["--list-editor-fixture"]
        app.launch()

        let toggle = app.buttons["Mark item 1 complete"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        toggle.tap()
        app.segmentedControls.buttons["Source"].tap()
        let source = app.textViews["markdown-source"]
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        XCTAssertEqual(source.value as? String, "7. First\n8. Second\n\n- [x] Task")
        app.buttons["Undo"].tap()
        XCTAssertEqual(source.value as? String, "7. First\n8. Second\n\n- [ ] Task")

        app.segmentedControls.buttons["Blocks"].tap()
        let firstItem = app.textFields["list-block-0-item-0"]
        XCTAssertTrue(firstItem.waitForExistence(timeout: 5))
        firstItem.doubleTap()
        firstItem.typeText("Revised")
        app.segmentedControls.buttons["Source"].tap()
        XCTAssertEqual(source.value as? String, "7. Revised\n8. Second\n\n- [ ] Task")
    }
}
