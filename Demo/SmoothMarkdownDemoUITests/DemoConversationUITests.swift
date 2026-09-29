import XCTest

final class DemoConversationUITests: XCTestCase {
    func testFlutterConversationListDetailsAndSelection() {
        let app = XCUIApplication()
        app.launch()
        app.buttons["open-examples"].tap()
        let entry = app.buttons["feature-conversationList"]
        for _ in 0..<12 where !entry.isHittable { app.swipeUp() }
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.tap()

        XCTAssertTrue(app.buttons["conversation-theme"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["conversation-1"].exists)
        app.buttons["conversation-theme"].tap()
        app.buttons["conversation-1"].tap()

        XCTAssertTrue(app.navigationBars["Flutter Dev Team"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["conversation-copy-all"].exists)
        app.buttons["conversation-copy-all"].tap()

        let actions = app.buttons.matching(
            NSPredicate(format: "identifier == %@ OR identifier == %@", "conversation-actions-0", "conversation-bubble-0")
        ).firstMatch
        XCTAssertTrue(actions.waitForExistence(timeout: 5))
        actions.tap()
        app.buttons["复制"].tap()

        let renderedText = app.textViews.firstMatch
        XCTAssertTrue(renderedText.exists)
        renderedText.press(forDuration: 1)
        XCTAssertTrue(app.buttons["复制"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["选择文字"].exists)
        app.buttons["选择文字"].tap()
        let nativeCopy = app.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@ OR label == %@", "Copy", "复制")
        ).firstMatch
        XCTAssertTrue(nativeCopy.waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Flutter Dev Team"].exists)
        XCTAssertFalse(app.navigationBars["选择文字"].exists)
    }
}
