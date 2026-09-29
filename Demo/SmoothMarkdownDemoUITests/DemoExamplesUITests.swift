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
        choose("language-en", in: app)
        XCTAssertEqual(selectedExample(in: app), "Basic Formatting")
        XCTAssertTrue(selectedTheme(in: app).contains("Default Light"))
        XCTAssertFalse(app.staticTexts["demo-current-title"].exists)

        app.buttons["view-markdown-source"].tap()
        XCTAssertTrue(app.navigationBars["Markdown Source"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["markdown-source-content"].label.contains("# Basic Text Formatting"))
        app.buttons["Close"].tap()

        for (id, title) in examples {
            choose("example-\(id)", in: app)
            XCTAssertEqual(selectedExample(in: app), title)
            XCTAssertFalse(app.staticTexts["Examples unavailable"].exists)
            XCTAssertTrue(app.buttons["view-markdown-source"].exists)
        }

        app.buttons["theme-menu"].tap()
        app.buttons["VS Code Dark"].tap()
        XCTAssertTrue(selectedTheme(in: app).contains("VS Code Dark"))
        app.buttons["open-demo-editor"].tap()
        XCTAssertTrue(app.navigationBars["Markdown Editor"].waitForExistence(timeout: 5))
        app.buttons["demo-editor-back"].tap()
        XCTAssertEqual(selectedExample(in: app), "Complex Example")
    }

    func testSourceSheetClosesBeforeChangingThemeAndOpeningEditor() {
        let app = XCUIApplication()
        app.launch()
        choose("language-en", in: app)
        app.buttons["view-markdown-source"].tap()
        XCTAssertTrue(app.navigationBars["Markdown Source"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["markdown-source-content"].label.contains("# Basic Text Formatting"))
        let sourceScreenshot = XCTAttachment(screenshot: app.screenshot())
        sourceScreenshot.name = "Markdown Source Sheet"
        sourceScreenshot.lifetime = .keepAlways
        add(sourceScreenshot)
        app.buttons["Close"].tap()
        choose("example-complex-example", in: app)
        app.buttons["theme-menu"].tap()
        app.buttons["VS Code Dark"].tap()
        app.buttons["open-demo-editor"].tap()
        XCTAssertTrue(app.navigationBars["Markdown Editor"].waitForExistence(timeout: 5))
    }

    func testHomeAndFeatureHaveNoSecondaryHeader() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertEqual(selectedExample(in: app), "Basic Formatting")
        XCTAssertFalse(app.staticTexts["demo-current-title"].exists)
        // Let the physical device's app-launch transition finish before taking visual evidence.
        Thread.sleep(forTimeInterval: 2)
        let homeScreenshot = XCTAttachment(screenshot: app.screenshot())
        homeScreenshot.name = "iOS Demo home without secondary header"
        homeScreenshot.lifetime = .keepAlways
        add(homeScreenshot)

        choose("feature-math", in: app)
        XCTAssertTrue(app.navigationBars["Math Formula Demo"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["demo-current-title"].exists)
        let featureScreenshot = XCTAttachment(screenshot: app.screenshot())
        featureScreenshot.name = "iOS Demo feature without secondary header"
        featureScreenshot.lifetime = .keepAlways
        add(featureScreenshot)
    }

    func testBasicFormattingInlineCodeBackgroundScreenshotOnPhysicalDevice() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["open-examples"].waitForExistence(timeout: 10))
        XCTAssertEqual(selectedExample(in: app), "Basic Formatting")
        let code = app.textViews.matching(NSPredicate(
            format: "label CONTAINS %@ OR label CONTAINS %@",
            "var x = 42;", "var\u{00A0}x\u{00A0}=\u{00A0}42;"
        )).firstMatch
        XCTAssertTrue(code.waitForExistence(timeout: 5))
        XCTAssertTrue(code.isHittable, "Inline code must be visible before capturing layout")
        Thread.sleep(forTimeInterval: 1)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Physical iPhone Basic Formatting inline code background"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testReaderLayoutInPhysicalLandscape() {
        let device = XCUIDevice.shared
        device.orientation = .portrait
        defer { device.orientation = .portrait }

        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["open-examples"].waitForExistence(timeout: 10))
        device.orientation = .landscapeLeft

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        for _ in 0..<20 where window.frame.width <= window.frame.height {
            Thread.sleep(forTimeInterval: 0.5)
        }
        XCTAssertGreaterThan(window.frame.width, window.frame.height,
                             "The Demo must actually rotate before assessing landscape layout")

        let heading = app.staticTexts["Basic Text Formatting"]
        XCTAssertTrue(heading.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(heading.frame.minY,
                                    app.buttons["open-examples"].frame.maxY,
                                    "Reader heading must not overlap the navigation bar")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Physical iPhone reader in actual landscape orientation"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testDrawerEditorEntryOpensEditor() {
        let app = XCUIApplication()
        app.launch()
        choose("language-en", in: app)
        let openExamples = app.buttons["open-examples"]
        XCTAssertTrue(openExamples.waitForExistence(timeout: 30))
        openExamples.tap()
        let editor = app.buttons["navigation-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        let drawerScreenshot = XCTAttachment(screenshot: app.screenshot())
        drawerScreenshot.name = "Flutter-style iOS Demo drawer"
        drawerScreenshot.lifetime = .keepAlways
        add(drawerScreenshot)
        editor.tap()
        XCTAssertTrue(app.navigationBars["Markdown Editor"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["editor-find-open"].exists)
        app.buttons["demo-editor-back"].tap()
        XCTAssertEqual(selectedExample(in: app), "Basic Formatting")
    }

    func testFlutterSpecialPagesAndNativeExtrasOpen() {
        let app = XCUIApplication()
        app.launch()
        choose("language-en", in: app)
        let features: [(String, String)] = [
            ("math", "Math Formula Demo"), ("streaming", "Streaming Markdown Demo"),
            ("footnotes", "Footnotes Demo"), ("html", "HTML Tags Demo"),
            ("chatList", "Chat List"), ("aiChat", "AI Chat"),
            ("conversationList", "Conversation List"), ("plugins", "Plugin System Demo"),
            ("mermaid", "Mermaid 图表测试"), ("structured", "Structured Mermaid"),
            ("selection", "Selection"), ("performance", "Performance"),
        ]
        for (id, title) in features {
            choose("feature-\(id)", in: app)
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5))
            XCTAssertFalse(app.staticTexts["demo-current-title"].exists)
            XCTAssertTrue(app.buttons["demo-feature-back"].exists)
            app.buttons["demo-feature-back"].tap()
            XCTAssertEqual(selectedExample(in: app), "Basic Formatting")
        }
        choose("language-en", in: app)
        XCTAssertTrue(selectedTheme(in: app).contains("English"))
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

    func testMermaidGalleryReportsTappedNodeID() {
        let app = XCUIApplication()
        app.launch()
        choose("feature-mermaid", in: app)
        let node = app.buttons["mermaid-node-A"]
        XCTAssertTrue(node.waitForExistence(timeout: 5))
        node.tap()
        XCTAssertEqual(app.staticTexts["mermaid-position"].value as? String, "Last tapped node: A")
    }

    func testFeatureBackKeepsExampleThemeAndSource() {
        let app = XCUIApplication()
        app.launch()
        choose("language-en", in: app)
        choose("example-headers", in: app)
        app.buttons["theme-menu"].tap()
        app.buttons["VS Code Dark"].tap()

        choose("feature-math", in: app)
        XCTAssertTrue(app.navigationBars["Math Formula Demo"].waitForExistence(timeout: 5))
        app.buttons["demo-feature-back"].tap()

        XCTAssertEqual(selectedExample(in: app), "Headers")
        XCTAssertTrue(selectedTheme(in: app).contains("VS Code Dark"))
        app.buttons["view-markdown-source"].tap()
        XCTAssertTrue(app.staticTexts["markdown-source-content"].label.contains("# Header 1"))
    }

    private func choose(_ identifier: String, in app: XCUIApplication) {
        let openExamples = app.buttons["open-examples"]
        XCTAssertTrue(openExamples.waitForExistence(timeout: 30))
        openExamples.tap()
        let navigationList = app.descendants(matching: .any)["demo-navigation-list"]
        XCTAssertTrue(navigationList.waitForExistence(timeout: 5))
        let entry = app.buttons[identifier]
        for _ in 0..<15 where !entry.isHittable { navigationList.swipeUp() }
        XCTAssertTrue(entry.isHittable, "Missing navigation entry: \(identifier)")
        entry.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        if identifier.hasPrefix("feature-") {
            XCTAssertTrue(app.buttons["demo-feature-back"].waitForExistence(timeout: 5))
        } else {
            XCTAssertTrue(openExamples.waitForExistence(timeout: 5))
        }
    }

    private func selectedExample(in app: XCUIApplication) -> String {
        (app.buttons["open-examples"].value as? String) ?? ""
    }

    private func selectedTheme(in app: XCUIApplication) -> String {
        (app.buttons["theme-menu"].value as? String) ?? ""
    }
}
