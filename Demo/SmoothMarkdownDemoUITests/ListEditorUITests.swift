import XCTest

final class ListEditorUITests: XCTestCase {
    func testIndentAndOutdentControlsChangeNestedListLevel() {
        let app = XCUIApplication()
        app.launchArguments = ["--nested-list-editor-fixture"]
        app.launch()

        let outdent = app.buttons["Outdent item 2"]
        XCTAssertTrue(outdent.waitForExistence(timeout: 10))
        outdent.tap()
        app.segmentedControls.buttons["Source"].tap()
        let source = app.textViews["markdown-source"]
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        XCTAssertEqual(source.value as? String, "- Parent\n- Child\n  continuation\n- Sibling")

        app.segmentedControls.buttons["Blocks"].tap()
        let indent = app.buttons["Indent item 2"]
        XCTAssertTrue(indent.waitForExistence(timeout: 5))
        indent.tap()
        app.segmentedControls.buttons["Source"].tap()
        XCTAssertEqual(source.value as? String, "- Parent\n  - Child\n    continuation\n- Sibling")
    }

    func testNestedListItemAndContinuationEditUndoRedoInBlocks() {
        let app = XCUIApplication()
        app.launchArguments = ["--nested-list-editor-fixture"]
        app.launch()

        let child = app.textFields["list-block-0-item-1"]
        let continuation = app.textFields["list-block-0-item-1-continuation-0"]
        XCTAssertTrue(child.waitForExistence(timeout: 10))
        XCTAssertTrue(continuation.exists)
        child.doubleTap()
        child.typeText("Changed")
        continuation.doubleTap()
        continuation.typeText("followup")

        app.segmentedControls.buttons["Source"].tap()
        let source = app.textViews["markdown-source"]
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        XCTAssertEqual(source.value as? String, "- Parent\n  - Changed\n    followup\n- Sibling")
        app.buttons["Undo"].tap()
        XCTAssertEqual(source.value as? String, "- Parent\n  - Changed\n    followu\n- Sibling")
        app.buttons["Redo"].tap()
        XCTAssertEqual(source.value as? String, "- Parent\n  - Changed\n    followup\n- Sibling")
    }

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
