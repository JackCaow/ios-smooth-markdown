import XCTest

final class DemoChatListUITests: XCTestCase {
    func testFlutterChatWelcomeSendStreamThemeAndCacheControl() {
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

        let field = app.descendants(matching: .any).matching(identifier: "chat-message-input").firstMatch
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
        // LazyVStack can recycle the welcome bubble after scrolling to the completed reply.
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "chat-assistant-bubble").firstMatch.exists)

        app.buttons["chat-toggle-theme"].tap()
        XCTAssertTrue(app.buttons["chat-toggle-theme"].exists)
        app.buttons["chat-cache-statistics"].tap()
        let cache = app.alerts["Cache Statistics"]
        XCTAssertTrue(cache.waitForExistence(timeout: 5))
        let values = cache.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Cached Entries:")).firstMatch
        XCTAssertTrue(values.waitForExistence(timeout: 5))
        XCTAssertTrue(values.label.contains("Cached Entries:"))
        XCTAssertTrue(values.label.contains("Max Capacity: 200"))
        XCTAssertTrue(values.label.contains("Utilization:"))
        cache.buttons["Clear Cache"].tap()
        XCTAssertTrue(app.staticTexts["chat-cache-cleared"].waitForExistence(timeout: 5))
    }
}
