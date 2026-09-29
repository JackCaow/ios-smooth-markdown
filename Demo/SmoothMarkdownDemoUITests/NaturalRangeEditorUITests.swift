import XCTest

final class NaturalRangeEditorUITests: XCTestCase {
    func testLongPressDragSelectsSiblingItemsAndDeletesWithUndo() {
        let app = XCUIApplication()
        app.launchArguments = ["--selection-list-editor-fixture"]
        app.launch()

        let first = app.textFields["list-block-0-item-0"]
        let second = app.textFields["list-block-0-item-1"]
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        XCTAssertTrue(second.exists)
        first.press(forDuration: 0.6, thenDragTo: second)

        let delete = app.buttons["Delete items"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5), "Dragging across two sibling fields should create a range")
        XCTAssertTrue(delete.isEnabled)
        delete.tap()
        app.segmentedControls.buttons["Source"].tap()
        let source = app.textViews["markdown-source"]
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        XCTAssertEqual(source.value as? String, "- Third")
        app.buttons["Undo"].tap()
        XCTAssertEqual(source.value as? String, "- First\n- Second\n- Third")
    }
}
