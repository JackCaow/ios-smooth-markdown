import XCTest

final class DemoAIChatUITests: XCTestCase {
    func testDeepSeekSettingsExposeRuntimeKeyAndBothModels() {
        let app = XCUIApplication()
        app.launchEnvironment["QWEN_API_KEY"] = ""
        app.launchEnvironment["DEEPSEEK_API_KEY"] = ""
        app.launch()
        app.buttons["open-examples"].tap()
        let navigationList = app.descendants(matching: .any)["demo-navigation-list"]
        XCTAssertTrue(navigationList.waitForExistence(timeout: 5))
        let entry = app.buttons["feature-aiChat"]
        for _ in 0..<15 where !entry.isHittable { navigationList.swipeUp() }
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        app.buttons["ai-chat-settings"].tap()

        let provider = app.descendants(matching: .any)["ai-chat-provider"]
        XCTAssertTrue(provider.waitForExistence(timeout: 5))
        provider.tap()
        app.buttons["DeepSeek"].tap()
        XCTAssertTrue(app.secureTextFields["ai-chat-deepseek-api-key"].waitForExistence(timeout: 5))
        let model = app.descendants(matching: .any)["ai-chat-deepseek-model"]
        XCTAssertTrue(model.exists)
        model.tap()
        XCTAssertTrue(app.buttons["DeepSeek Flash"].exists)
        XCTAssertTrue(app.buttons["DeepSeek V4 Pro"].exists)
    }

    func testQwenSettingsExposeRuntimeKeyModelAndMockSwitch() {
        let app = XCUIApplication()
        app.launchEnvironment["QWEN_API_KEY"] = ""
        app.launch()
        app.buttons["open-examples"].tap()
        let navigationList = app.descendants(matching: .any)["demo-navigation-list"]
        XCTAssertTrue(navigationList.waitForExistence(timeout: 5))
        let entry = app.buttons["feature-aiChat"]
        for _ in 0..<15 where !entry.isHittable { navigationList.swipeUp() }
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        app.buttons["ai-chat-settings"].tap()

        XCTAssertTrue(app.secureTextFields["ai-chat-api-key"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["ai-chat-model"].exists)
        let settingsForm = app.descendants(matching: .any)["ai-chat-settings-form"]
        let thinking = app.switches["ai-chat-thinking"]
        for _ in 0..<4 where !thinking.exists { settingsForm.swipeUp() }
        XCTAssertTrue(thinking.exists)
        let realAPI = app.switches["ai-chat-real-api"]
        for _ in 0..<4 where !realAPI.isHittable { settingsForm.swipeUp() }
        XCTAssertTrue(realAPI.exists)
        realAPI.tap()
        app.buttons["关闭"].tap()
        XCTAssertEqual(app.staticTexts["ai-chat-status"].label, "模拟模式")
    }

    func testFlutterMockPromptStreamsWithThinkingPluginAndNewChatResets() {
        let app = XCUIApplication()
        app.launchEnvironment["QWEN_API_KEY"] = ""
        app.launch()
        app.buttons["open-examples"].tap()
        let navigationList = app.descendants(matching: .any)["demo-navigation-list"]
        XCTAssertTrue(navigationList.waitForExistence(timeout: 5))
        let entry = app.buttons["feature-aiChat"]
        for _ in 0..<15 where !entry.isHittable { navigationList.swipeUp() }
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

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
        let thinkingCard = app.buttons["thinking-card-toggle"]
        let chatScroll = app.scrollViews["ai-chat-message-list"]
        XCTAssertTrue(chatScroll.exists)
        // Depending on Dynamic Type and the current scroll anchor, the card can
        // start above or below the visible portion of the lazy message list.
        for _ in 0..<12 where !thinkingCard.exists { chatScroll.swipeUp() }
        for _ in 0..<12 where !thinkingCard.exists { chatScroll.swipeDown() }
        XCTAssertTrue(thinkingCard.waitForExistence(timeout: 5))
        XCTAssertEqual(thinkingCard.label, "Thinking...")

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
