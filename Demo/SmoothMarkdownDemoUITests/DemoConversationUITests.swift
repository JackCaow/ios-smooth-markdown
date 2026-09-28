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
        XCTAssertTrue(app.staticTexts["conversation-copy-feedback"].waitForExistence(timeout: 5))

        let bubble = app.descendants(matching: .any).matching(identifier: "conversation-bubble-0").firstMatch
        XCTAssertTrue(bubble.exists)
        let actions = app.buttons["conversation-actions-0"]
        XCTAssertTrue(actions.exists)
        actions.tap()
        app.buttons["复制"].tap()
        XCTAssertTrue(app.staticTexts["conversation-copy-feedback"].waitForExistence(timeout: 5))

        let renderedText = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "SmoothMarkdown 缓存策略更新了吗")
        ).firstMatch
        XCTAssertTrue(renderedText.exists)
        renderedText.press(forDuration: 1)
        let nativeCopy = app.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@ OR label == %@", "Copy", "复制")
        ).firstMatch
        XCTAssertTrue(nativeCopy.waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Flutter Dev Team"].exists)
        XCTAssertFalse(app.navigationBars["选择文字"].exists)
    }
}
