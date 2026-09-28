import XCTest

final class DemoAIChatUITests: XCTestCase {
    func testFlutterMockPromptStreamsWithThinkingPluginAndNewChatResets() {
        let app = XCUIApplication()
        app.launch()
        app.buttons["open-examples"].tap()
        let entry = app.buttons["feature-aiChat"]
        for _ in 0..<15 where !entry.isHittable { app.swipeUp() }
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.tap()

        let status = app.staticTexts["ai-chat-status"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertEqual(status.label, "模拟模式")
        XCTAssertTrue(app.buttons["ai-chat-prompt-thinking"].exists)
        XCTAssertTrue(app.buttons["ai-chat-prompt-artifact"].exists)
        XCTAssertTrue(app.buttons["ai-chat-prompt-toolCall"].exists)
        XCTAssertTrue(app.buttons["ai-chat-prompt-allInOne"].exists)
        XCTAssertTrue(app.buttons["ai-chat-prompt-code"].exists)
        XCTAssertTrue(app.buttons["ai-chat-prompt-table"].exists)

        // The initial source is the exact welcome Markdown from Flutter's example.
        let welcomeSource = app.buttons["ai-chat-source"]
        XCTAssertTrue(welcomeSource.waitForExistence(timeout: 5))
        welcomeSource.tap()
        let sourceContent = app.staticTexts["ai-chat-source-content"]
        XCTAssertTrue(sourceContent.waitForExistence(timeout: 5))
        XCTAssertTrue(sourceContent.label.contains("# 🤖 AI Chat Demo"))
        app.buttons["关闭"].tap()

        let thinkingPrompt = app.buttons["ai-chat-prompt-thinking"]
        thinkingPrompt.tap()
        let typing = NSPredicate(format: "label == %@", "正在输入...")
        expectation(for: typing, evaluatedWith: status)
        waitForExpectations(timeout: 5)
        let ready = NSPredicate(format: "label == %@", "模拟模式")
        expectation(for: ready, evaluatedWith: status)
        waitForExpectations(timeout: 15)
        XCTAssertTrue(thinkingPrompt.isEnabled)

        // The renderer must expose the Thinking plugin, not only its raw XML.
        let thinkingCard = app.buttons["Thinking..."]
        let chatScroll = app.scrollViews.element(boundBy: 1)
        XCTAssertTrue(chatScroll.exists)
        for _ in 0..<6 where !thinkingCard.isHittable { chatScroll.swipeDown() }
        XCTAssertTrue(thinkingCard.waitForExistence(timeout: 5))

        // The complete simulated response, including the closing tag, survives streaming.
        for _ in 0..<6 { chatScroll.swipeUp() }
        let sourceButtons = app.buttons.matching(identifier: "ai-chat-source")
        XCTAssertGreaterThan(sourceButtons.count, 0)
        let replySource = sourceButtons.element(boundBy: sourceButtons.count - 1)
        XCTAssertTrue(replySource.waitForExistence(timeout: 5))
        replySource.tap()
        XCTAssertTrue(sourceContent.waitForExistence(timeout: 5))
        XCTAssertTrue(sourceContent.label.contains("# Thinking Block 演示"))
        XCTAssertTrue(sourceContent.label.contains("</thinking>"))
        XCTAssertTrue(sourceContent.label.contains("上面的折叠块就是一个 thinking block 示例"))
        app.buttons["关闭"].tap()

        app.buttons["ai-chat-new"].tap()
        XCTAssertEqual(status.label, "模拟模式")
        let resetSourceButtons = app.buttons.matching(identifier: "ai-chat-source")
        XCTAssertEqual(resetSourceButtons.count, 1)
        resetSourceButtons.firstMatch.tap()
        XCTAssertTrue(sourceContent.waitForExistence(timeout: 5))
        XCTAssertTrue(sourceContent.label.contains("# 🤖 AI Chat Demo"))
    }
}
