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

        let bubble = app.descendants(matching: .any).matching(identifier: "conversation-bubble-0").firstMatch
        XCTAssertTrue(bubble.exists)
        bubble.press(forDuration: 1)
        XCTAssertTrue(app.buttons["选择文字"].waitForExistence(timeout: 5))
        app.buttons["选择文字"].tap()
        XCTAssertTrue(app.staticTexts["conversation-selectable-text"].waitForExistence(timeout: 5))
    }
}
