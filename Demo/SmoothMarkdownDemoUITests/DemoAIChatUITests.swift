import XCTest

final class DemoAIChatUITests: XCTestCase {
    /// Run explicitly after tools/run_demo_on_device_with_deepseek.sh has launched the app.
    func testPrelaunchedDeepSeekDevelopmentKeyOnPhysicalDevice() throws {
        let app = XCUIApplication()
        app.activate()
        if !app.buttons["ai-chat-settings"].exists {
            XCTAssertTrue(app.buttons["open-examples"].waitForExistence(timeout: 10))
            app.buttons["open-examples"].tap()
            let navigationList = app.descendants(matching: .any)["demo-navigation-list"]
            XCTAssertTrue(navigationList.waitForExistence(timeout: 5))
            let entry = app.buttons["feature-aiChat"]
            for _ in 0..<15 where !entry.isHittable { navigationList.swipeUp() }
            XCTAssertTrue(entry.isHittable)
            entry.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }

        let status = app.staticTexts["ai-chat-status"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        if status.label == "模拟模式" {
            throw XCTSkip("Launch the installed Demo with the local Keychain script before this optional live test")
        }
        XCTAssertEqual(status.label, "deepseek-flash")

        let input = app.textFields["ai-chat-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText("Reply with exactly OK.")
        app.buttons["ai-chat-send"].tap()
        let replySource = app.buttons["ai-chat-source"]
        XCTAssertTrue(replySource.waitForExistence(timeout: 90))
        XCTAssertEqual(status.label, "deepseek-flash")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "iPhone DeepSeek live reply with development Key"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        replySource.tap()
        let response = app.staticTexts["ai-chat-source-content"]
        XCTAssertTrue(response.waitForExistence(timeout: 5))
        XCTAssertFalse(response.label.contains("⚠️"))
        XCTAssertFalse(response.label.isEmpty)
    }

    func testCompactDeepSeekChatOnPhysicalDevice() {
        let app = XCUIApplication()
        app.launchEnvironment["DEEPSEEK_API_KEY"] = ""
        app.launch()
        app.buttons["open-examples"].tap()
        let navigationList = app.descendants(matching: .any)["demo-navigation-list"]
        XCTAssertTrue(navigationList.waitForExistence(timeout: 5))
        let entry = app.buttons["feature-aiChat"]
        for _ in 0..<15 where !entry.isHittable { navigationList.swipeUp() }
        XCTAssertTrue(entry.isHittable)
        entry.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        XCTAssertTrue(app.staticTexts["ai-chat-status"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["ai-chat-settings"].exists)
        XCTAssertTrue(app.buttons["ai-chat-actions"].exists)
        XCTAssertTrue(app.scrollViews["ai-chat-message-list"].exists)
        XCTAssertTrue(app.staticTexts["ai-chat-empty-hint"].exists)
        XCTAssertFalse(app.buttons["ai-chat-prompt-thinking"].exists)
        XCTAssertEqual(app.buttons.matching(identifier: "ai-chat-source").count, 0)
        Thread.sleep(forTimeInterval: 2)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "iPhone DeepSeek chat compact layout"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

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
        XCTAssertTrue(app.secureTextFields["ai-chat-deepseek-api-key"].waitForExistence(timeout: 5))
        let model = app.descendants(matching: .any)["ai-chat-deepseek-model"]
        XCTAssertTrue(model.exists)
        model.tap()
        XCTAssertTrue(app.buttons["DeepSeek Flash"].exists)
        XCTAssertTrue(app.buttons["DeepSeek V4 Pro"].exists)
        app.buttons["DeepSeek Flash"].tap()
        let settingsForm = app.descendants(matching: .any)["ai-chat-settings-form"]
        let thinking = app.switches["ai-chat-deepseek-thinking"]
        for _ in 0..<4 where !thinking.exists { settingsForm.swipeUp() }
        XCTAssertTrue(thinking.exists)
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

        let provider = app.descendants(matching: .any)["ai-chat-provider"]
        XCTAssertTrue(provider.waitForExistence(timeout: 5))
        provider.tap()
        app.buttons["Qwen"].tap()
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
        let actions = app.buttons["ai-chat-actions"]
        XCTAssertTrue(actions.exists)
        XCTAssertEqual(app.buttons.matching(identifier: "ai-chat-source").count, 0)
        actions.tap()
        XCTAssertTrue(app.buttons["ai-chat-prompt-thinking"].exists)
        XCTAssertTrue(app.buttons["ai-chat-prompt-artifact"].exists)
        XCTAssertTrue(app.buttons["ai-chat-prompt-toolCall"].exists)
        XCTAssertTrue(app.buttons["ai-chat-prompt-allInOne"].exists)
        XCTAssertTrue(app.buttons["ai-chat-prompt-code"].exists)
        XCTAssertTrue(app.buttons["ai-chat-prompt-table"].exists)

        let thinkingPrompt = app.buttons["ai-chat-prompt-thinking"]
        thinkingPrompt.tap()
        let ready = NSPredicate(format: "label == %@", "模拟模式")
        expectation(for: ready, evaluatedWith: status)
        waitForExpectations(timeout: 15)
        XCTAssertTrue(actions.isEnabled)

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
        let replyScreenshot = XCTAttachment(screenshot: app.screenshot())
        replyScreenshot.name = "iPhone DeepSeek chat with mock reply"
        replyScreenshot.lifetime = .keepAlways
        add(replyScreenshot)

        // The complete simulated response, including the closing tag, survives streaming.
        for _ in 0..<6 { chatScroll.swipeUp() }
        let sourceButtons = app.buttons.matching(identifier: "ai-chat-source")
        XCTAssertGreaterThan(sourceButtons.count, 0)
        let replySource = sourceButtons.element(boundBy: sourceButtons.count - 1)
        XCTAssertTrue(replySource.waitForExistence(timeout: 5))
        replySource.tap()
        let sourceContent = app.staticTexts["ai-chat-source-content"]
        XCTAssertTrue(sourceContent.waitForExistence(timeout: 5))
        XCTAssertTrue(sourceContent.label.contains("# Thinking Block 演示"))
        XCTAssertTrue(sourceContent.label.contains("</thinking>"))
        XCTAssertTrue(sourceContent.label.contains("上面的折叠块就是一个 thinking block 示例"))
        app.buttons["关闭"].tap()

        actions.tap()
        app.buttons["ai-chat-new"].tap()
        XCTAssertEqual(status.label, "模拟模式")
        let resetSourceButtons = app.buttons.matching(identifier: "ai-chat-source")
        XCTAssertEqual(resetSourceButtons.count, 0)
        actions.tap()
        app.buttons["ai-chat-help"].tap()
        XCTAssertTrue(app.navigationBars["使用说明"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["ai-chat-help-content"].exists)
    }
}
