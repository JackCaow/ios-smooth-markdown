import XCTest
import UIKit

/// Screenshot inventory for visual review on a physical iPhone. Run this class explicitly;
/// each attachment is retained in the xcresult for export to the review folder.
final class DemoVisualAuditUITests: XCTestCase {
    private let examples = [
        "basic-formatting", "headers", "lists", "code-blocks", "quotes-rules",
        "links-images", "enhanced-ui", "theme-showcase", "details-summary", "complex-example"
    ]

    private let features = [
        "math", "streaming", "footnotes", "html", "chatList", "aiChat",
        "conversationList", "plugins", "mermaid", "structured", "selection", "performance"
    ]

    func test01HomeExamplesAndSource() {
        let app = launchDemo()
        XCTAssertEqual(app.buttons["open-examples"].value as? String, "Basic Formatting")
        captureLongScreen("home-01-basic-formatting", in: app)

        app.buttons["open-examples"].tap()
        XCTAssertTrue(navigationList(in: app).waitForExistence(timeout: 5))
        capture("home-00-navigation-drawer", in: app)
        app.buttons["navigation-scrim"].tap()

        choose("language-en", in: app)

        app.buttons["view-markdown-source"].tap()
        XCTAssertTrue(app.navigationBars["Markdown Source"].waitForExistence(timeout: 5))
        capture("home-01-source-sheet", in: app)
        app.buttons["Close"].tap()

        // The default page is already selected. Do not reselect it via the drawer:
        // that can close the drawer before XCTest's coordinate tap completes.
        for (offset, id) in examples.enumerated() where offset > 0 {
            choose("example-\(id)", in: app)
            XCTAssertTrue(app.buttons["view-markdown-source"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.staticTexts["Examples unavailable"].exists)
            captureLongScreen(String(format: "home-%02d-%@", offset + 1, id), in: app)
        }

        app.buttons["theme-menu"].tap()
        app.buttons["VS Code Dark"].tap()
        XCTAssertTrue((app.buttons["theme-menu"].value as? String ?? "").contains("VS Code Dark"))
        capture("home-11-complex-example-dark", in: app)
        app.buttons["view-markdown-source"].tap()
        XCTAssertTrue(app.navigationBars["Markdown Source"].waitForExistence(timeout: 5))
        capture("home-12-source-sheet-dark", in: app)
    }

    func test02StandaloneFeatures() {
        let app = launchDemo()
        for (offset, id) in features.enumerated() {
            choose("feature-\(id)", in: app)
            XCTAssertTrue(app.buttons["demo-feature-back"].waitForExistence(timeout: 8), id)
            XCTAssertFalse(app.staticTexts["demo-current-title"].exists)
            captureLongScreen(String(format: "feature-%02d-%@", offset + 1, id), in: app)
            app.buttons["demo-feature-back"].tap()
            XCTAssertTrue(app.buttons["open-examples"].waitForExistence(timeout: 5))
        }
    }

    func test03EditorModes() {
        let app = launchDemo()
        app.buttons["open-demo-editor"].tap()
        XCTAssertTrue(app.segmentedControls.buttons["Blocks"].waitForExistence(timeout: 10))
        capture("editor-01-blocks", in: app)

        app.segmentedControls.buttons["Preview"].tap()
        XCTAssertTrue(app.segmentedControls.buttons["Preview"].isSelected)
        capture("editor-02-preview", in: app)

        app.segmentedControls.buttons["Split"].tap()
        XCTAssertTrue(app.segmentedControls.buttons["Split"].isSelected)
        capture("editor-03-split", in: app)

        app.segmentedControls.buttons["Source"].tap()
        XCTAssertTrue(app.textViews["markdown-source"].waitForExistence(timeout: 5))
        capture("editor-04-source", in: app)

        app.segmentedControls.buttons["Blocks"].tap()
        app.buttons["editor-find-open"].tap()
        XCTAssertTrue(app.textFields["editor-find-field"].waitForExistence(timeout: 5))
        capture("editor-05-find", in: app)
        app.buttons["editor-find-close"].tap()

        app.buttons["editor-focus-toggle"].tap()
        XCTAssertFalse(app.segmentedControls.buttons["Blocks"].exists)
        capture("editor-06-focus", in: app)
    }

    func test03SixReaderThemes() {
        let app = launchDemo()
        choose("language-en", in: app)
        let themes = ["Default Light", "Default Dark", "GitHub", "GitHub Dark", "VS Code", "VS Code Dark"]
        for (offset, theme) in themes.enumerated() {
            app.buttons["theme-menu"].tap()
            let option = app.buttons[theme]
            XCTAssertTrue(option.waitForExistence(timeout: 5), theme)
            option.tap()
            capture(String(format: "theme-%02d-%@", offset + 1,
                           theme.lowercased().replacingOccurrences(of: " ", with: "-")), in: app)
        }
    }

    func test04ChatAndConversationSurfaces() {
        let app = launchDemo()
        choose("feature-chatList", in: app)
        XCTAssertTrue(app.buttons["chat-cache-statistics"].waitForExistence(timeout: 5))
        capture("chat-01-list-light", in: app)
        app.buttons["chat-toggle-theme"].tap()
        capture("chat-02-list-dark", in: app)
        app.buttons["chat-cache-statistics"].tap()
        XCTAssertTrue(app.alerts["Cache Statistics"].waitForExistence(timeout: 5))
        capture("chat-03-cache-statistics", in: app)
        app.buttons["Close"].tap()
        app.buttons["demo-feature-back"].tap()

        choose("feature-aiChat", in: app)
        XCTAssertTrue(app.buttons["ai-chat-settings"].waitForExistence(timeout: 5))
        capture("chat-04-ai-chat", in: app)
        app.buttons["ai-chat-settings"].tap()
        XCTAssertTrue(app.navigationBars["API 设置"].waitForExistence(timeout: 5))
        captureRedacted("chat-05-ai-settings", in: app,
                        redacting: app.secureTextFields.matching(identifier: "ai-chat-deepseek-api-key").allElementsBoundByIndex)
        app.buttons["关闭"].tap()
        app.buttons["ai-chat-actions"].tap()
        XCTAssertTrue(app.buttons["ai-chat-help"].waitForExistence(timeout: 5))
        app.buttons["ai-chat-help"].tap()
        XCTAssertTrue(app.navigationBars["使用说明"].waitForExistence(timeout: 5))
        capture("chat-06-ai-help", in: app)
        app.buttons["关闭"].tap()

        // Both API keys are empty, so quick prompts use the bundled mock stream.
        app.buttons["ai-chat-actions"].tap()
        let prompt = app.buttons["ai-chat-prompt-code"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 5))
        prompt.tap()
        let replySource = app.buttons["ai-chat-source"]
        XCTAssertTrue(replySource.waitForExistence(timeout: 30))
        capture("chat-07-ai-mock-reply", in: app)
        replySource.tap()
        XCTAssertTrue(app.navigationBars["Markdown 源码"].waitForExistence(timeout: 5))
        capture("chat-08-ai-reply-source", in: app)
        app.buttons["关闭"].tap()
        app.buttons["demo-feature-back"].tap()

        choose("feature-conversationList", in: app)
        XCTAssertTrue(app.buttons["conversation-1"].waitForExistence(timeout: 5))
        capture("conversation-01-list-light", in: app)
        app.buttons["conversation-theme"].tap()
        capture("conversation-02-list-dark", in: app)
        app.buttons["conversation-1"].tap()
        XCTAssertTrue(app.buttons["conversation-copy-all"].waitForExistence(timeout: 5))
        capture("conversation-03-first-detail-dark", in: app)
    }

    func test05AllConversationDetails() {
        let app = launchDemo()
        choose("feature-conversationList", in: app)
        let list = app.tables.firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 5))
        for number in 1...12 {
            let row = app.buttons["conversation-\(number)"]
            reveal(row, bySwiping: list, direction: .up)
            XCTAssertTrue(row.isHittable, "Conversation \(number) should be reachable")
            row.tap()
            XCTAssertTrue(app.buttons["conversation-copy-all"].waitForExistence(timeout: 5))
            captureLongScreen(String(format: "conversation-%02d-detail", number), in: app)
            let back = app.navigationBars.buttons.firstMatch
            XCTAssertTrue(back.isHittable)
            back.tap()
            XCTAssertTrue(row.waitForExistence(timeout: 5))
        }
        capture("conversation-13-list-bottom", in: app)
    }

    func test06MermaidGalleryAllForty() {
        let app = launchDemo()
        choose("feature-mermaid", in: app)
        let position = app.staticTexts["mermaid-position"]
        XCTAssertTrue(position.waitForExistence(timeout: 10))
        let gallery = app.scrollViews.firstMatch
        XCTAssertTrue(gallery.exists)

        for number in 1...40 {
            XCTAssertEqual(position.label, "\(number)/40")
            revealTop(of: gallery, title: app.staticTexts["mermaid-title"])
            XCTAssertTrue(app.staticTexts["mermaid-title"].isHittable)
            capture(String(format: "mermaid-%02d-gallery", number), in: app)
            // Many diagrams and their source panels extend below the first viewport.
            gallery.swipeUp()
            capture(String(format: "mermaid-%02d-lower", number), in: app)
            if number == 40 { break }
            let next = app.buttons["mermaid-next"]
            reveal(next, bySwiping: gallery, direction: .up)
            XCTAssertTrue(next.isHittable, "Next button for Mermaid \(number)")
            next.tap()
            XCTAssertTrue(position.waitForExistence(timeout: 5))
        }

        // Include the gallery's alternate theme and source sheet as distinct UI states.
        app.buttons["mermaid-theme"].tap()
        revealTop(of: gallery, title: app.staticTexts["mermaid-title"])
        capture("mermaid-41-gallery-dark", in: app)
        let viewSource = app.buttons["View source"]
        reveal(viewSource, bySwiping: gallery, direction: .up)
        viewSource.tap()
        XCTAssertTrue(app.navigationBars["Mermaid Source"].waitForExistence(timeout: 5))
        capture("mermaid-42-source-sheet", in: app)
    }

    func test07DynamicStates() {
        let app = launchDemo()

        choose("feature-streaming", in: app)
        let streamStatus = app.staticTexts["stream-demo-status"]
        let start = app.buttons["stream-demo-start"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        XCTAssertEqual(streamStatus.label, "Ready")
        capture("state-01-stream-ready", in: app)
        start.tap()
        let streaming = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label BEGINSWITH %@", "Streaming "),
            object: streamStatus)
        XCTAssertEqual(XCTWaiter.wait(for: [streaming], timeout: 5), .completed)
        capture("state-02-stream-progress", in: app)
        let complete = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", "Complete 48/48 chunks"),
            object: streamStatus)
        XCTAssertEqual(XCTWaiter.wait(for: [complete], timeout: 15), .completed)
        capture("state-03-stream-complete", in: app)
        app.buttons["demo-feature-back"].tap()

        choose("feature-html", in: app)
        let htmlToggle = app.switches["html-demo-toggle"]
        let htmlStatus = app.staticTexts["html-demo-status"]
        XCTAssertTrue(htmlToggle.waitForExistence(timeout: 5))
        XCTAssertEqual(htmlStatus.label, "Ready · HTML on")
        capture("state-04-html-enabled", in: app)
        htmlToggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(htmlStatus.label, "Ready · HTML off")
        capture("state-05-html-disabled", in: app)
        app.buttons["demo-feature-back"].tap()

        choose("feature-chatList", in: app)
        let field = app.descendants(matching: .any).matching(identifier: "chat-message-input").firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("Show me a code example")
        let send = app.buttons["chat-send"]
        XCTAssertTrue(send.isEnabled)
        send.tap()
        XCTAssertTrue(app.descendants(matching: .any)
            .matching(identifier: "chat-user-bubble").firstMatch.waitForExistence(timeout: 5))
        let assistantStatus = app.staticTexts["chat-assistant-status"]
        let typing = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", "Typing..."),
            object: assistantStatus)
        XCTAssertEqual(XCTWaiter.wait(for: [typing], timeout: 5), .completed)
        capture("state-06-chat-reply-streaming", in: app)
        let online = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", "Online"),
            object: assistantStatus)
        XCTAssertEqual(XCTWaiter.wait(for: [online], timeout: 20), .completed)
        capture("state-07-chat-reply-complete", in: app)
    }

    private func launchDemo() -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment["QWEN_API_KEY"] = ""
        app.launchEnvironment["DEEPSEEK_API_KEY"] = ""
        app.launch()
        XCTAssertTrue(app.buttons["open-examples"].waitForExistence(timeout: 30))
        return app
    }

    private func capture(_ name: String, in app: XCUIApplication) {
        Thread.sleep(forTimeInterval: 0.35)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func captureLongScreen(_ name: String, in app: XCUIApplication) {
        capture("\(name)-top", in: app)
        app.swipeUp()
        capture("\(name)-middle", in: app)
        app.swipeUp()
        capture("\(name)-bottom", in: app)
    }

    private func captureRedacted(_ name: String, in app: XCUIApplication,
                                 redacting elements: [XCUIElement]) {
        let image = app.screenshot().image
        let renderer = UIGraphicsImageRenderer(size: image.size)
        let redacted = renderer.image { context in
            image.draw(at: .zero)
            for element in elements where element.exists {
                let rect = element.frame.insetBy(dx: -6, dy: -4)
                UIColor.systemGray3.setFill()
                context.fill(rect)
            }
        }
        let attachment = XCTAttachment(image: redacted)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func navigationList(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["demo-navigation-list"]
    }

    private func choose(_ identifier: String, in app: XCUIApplication) {
        let open = app.buttons["open-examples"]
        XCTAssertTrue(open.waitForExistence(timeout: 10))
        open.tap()
        let list = navigationList(in: app)
        XCTAssertTrue(list.waitForExistence(timeout: 5))
        let entry = app.buttons[identifier]
        // The drawer preserves its scroll position. Search toward the bottom,
        // then back toward the top when revisiting an earlier entry.
        for _ in 0..<18 where !entry.isHittable { list.swipeUp() }
        for _ in 0..<18 where !entry.isHittable { list.swipeDown() }
        XCTAssertTrue(entry.isHittable, "Missing navigation entry: \(identifier)")
        entry.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        if identifier.hasPrefix("feature-") {
            XCTAssertTrue(app.buttons["demo-feature-back"].waitForExistence(timeout: 8))
        } else {
            XCTAssertTrue(open.waitForExistence(timeout: 5))
        }
    }

    private enum SwipeDirection { case up, down }

    private func reveal(_ element: XCUIElement, bySwiping scroll: XCUIElement,
                        direction: SwipeDirection) {
        for _ in 0..<12 where !element.isHittable {
            switch direction {
            case .up: scroll.swipeUp()
            case .down: scroll.swipeDown()
            }
        }
    }

    private func revealTop(of scroll: XCUIElement, title: XCUIElement) {
        reveal(title, bySwiping: scroll, direction: .down)
        // A title can already be visible halfway down the page. One final swipe
        // restores the diagram header and category controls to the top viewport.
        scroll.swipeDown()
    }
}
