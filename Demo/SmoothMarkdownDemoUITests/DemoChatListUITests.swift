import XCTest

final class DemoChatListUITests: XCTestCase {
    func testFlutterChatWelcomeSendStreamThemeAndCacheExplanation() {
        let app = XCUIApplication()
        app.launch()
        app.buttons["open-examples"].tap()
        let entry = app.buttons["feature-chatList"]
        for _ in 0..<15 where !entry.isHittable { app.swipeUp() }
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.tap()

        XCTAssertTrue(app.staticTexts["chat-assistant-status"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["chat-assistant-status"].label, "Online")
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "chat-assistant-bubble").count, 1)

        let field = app.textFields["chat-message-input"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("Show me a code example")
        app.buttons["chat-send"].tap()
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "chat-user-bubble").count, 1)

        let typing = NSPredicate(format: "label == %@", "Typing...")
        expectation(for: typing, evaluatedWith: app.staticTexts["chat-assistant-status"])
        waitForExpectations(timeout: 5)
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "chat-assistant-bubble").count, 2)
        let online = NSPredicate(format: "label == %@", "Online")
        expectation(for: online, evaluatedWith: app.staticTexts["chat-assistant-status"])
        waitForExpectations(timeout: 20)
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "chat-assistant-bubble").count, 2)

        app.buttons["chat-toggle-theme"].tap()
        XCTAssertTrue(app.buttons["chat-toggle-theme"].exists)
        app.buttons["chat-cache-statistics"].tap()
        XCTAssertTrue(app.alerts["Cache Statistics Unavailable"].waitForExistence(timeout: 5))
        app.alerts.buttons["Close"].tap()
    }
}
