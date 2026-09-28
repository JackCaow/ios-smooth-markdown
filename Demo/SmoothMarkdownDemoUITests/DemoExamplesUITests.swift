import XCTest

final class DemoExamplesUITests: XCTestCase {
    private let examples: [(String, String)] = [
        ("basic-formatting", "Basic Formatting"), ("headers", "Headers"),
        ("lists", "Lists"), ("code-blocks", "Code Blocks"),
        ("quotes-rules", "Quotes & Rules"), ("links-images", "Links & Images"),
        ("enhanced-ui", "Enhanced UI"), ("theme-showcase", "Theme Showcase"),
        ("details-summary", "Details & Summary"), ("complex-example", "Complex Example"),
    ]

    func testTenFlutterExamplesSourceThemeAndEditor() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["demo-current-title"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["demo-current-title"].label, "Basic Formatting")
        XCTAssertTrue(app.staticTexts["demo-current-theme"].label.contains("Default Light"))

        app.buttons["view-markdown-source"].tap()
        XCTAssertTrue(app.navigationBars["Markdown Source"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["markdown-source-content"].label.contains("# Basic Text Formatting"))
        app.buttons["Close"].tap()

        for (id, title) in examples {
            choose("example-\(id)", in: app)
            XCTAssertEqual(app.staticTexts["demo-current-title"].label, title)
            XCTAssertFalse(app.staticTexts["Examples unavailable"].exists)
            XCTAssertTrue(app.buttons["view-markdown-source"].exists)
        }

        app.buttons["theme-menu"].tap()
        app.buttons["VS Code Dark"].tap()
        XCTAssertTrue(app.staticTexts["demo-current-theme"].label.contains("VS Code Dark"))
        app.buttons["open-demo-editor"].tap()
        XCTAssertTrue(app.navigationBars["Markdown Editor"].waitForExistence(timeout: 5))
        app.buttons["Close"].tap()
        XCTAssertEqual(app.staticTexts["demo-current-title"].label, "Complex Example")
    }

    func testFlutterSpecialPagesAndNativeExtrasOpen() {
        let app = XCUIApplication()
        app.launch()
        let features: [(String, String)] = [
            ("math", "Math Formulas"), ("streaming", "Streaming Markdown"),
            ("footnotes", "Footnotes"), ("html", "HTML Tags"),
            ("chatList", "Chat List"), ("aiChat", "AI Chat"),
            ("conversationList", "Conversation List"), ("plugins", "Plugin System"),
            ("mermaid", "Mermaid Diagrams"), ("structured", "Structured Mermaid"),
            ("selection", "Selection"), ("performance", "Performance"),
        ]
        for (id, title) in features {
            choose("feature-\(id)", in: app)
            XCTAssertEqual(app.staticTexts["demo-current-title"].label, title)
        }
        choose("language-en", in: app)
        XCTAssertTrue(app.staticTexts["demo-current-theme"].label.contains("English"))
    }

    func testMermaidGalleryUsesFlutterFortyExamples() {
        let app = XCUIApplication()
        app.launch()
        choose("feature-mermaid", in: app)
        XCTAssertEqual(app.staticTexts["mermaid-position"].label, "1/40")
        XCTAssertEqual(app.staticTexts["mermaid-title"].label, "基础流程图 (TD)")
        XCTAssertFalse(app.buttons["mermaid-previous"].isEnabled)
        app.buttons["mermaid-next"].tap()
        XCTAssertEqual(app.staticTexts["mermaid-position"].label, "2/40")
        XCTAssertTrue(app.staticTexts["mermaid-source"].exists)
        app.buttons["mermaid-copy"].tap()
        app.buttons["mermaid-theme"].tap()
        XCTAssertEqual(app.staticTexts["mermaid-position"].label, "2/40")
    }

    private func choose(_ identifier: String, in app: XCUIApplication) {
        app.buttons["open-examples"].tap()
        let entry = app.buttons[identifier]
        for _ in 0..<15 where !entry.isHittable { app.swipeUp() }
        XCTAssertTrue(entry.exists, "Missing navigation entry: \(identifier)")
        entry.tap()
        XCTAssertTrue(app.staticTexts["demo-current-title"].waitForExistence(timeout: 5))
    }
}
