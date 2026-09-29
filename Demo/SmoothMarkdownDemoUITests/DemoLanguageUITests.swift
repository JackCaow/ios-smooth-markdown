import XCTest

final class DemoLanguageUITests: XCTestCase {
    func testSixLanguagesKeepSelectedPageThemeAndMarkdownSource() {
        let app = XCUIApplication()
        app.launch()

        let title = app.buttons["open-examples"]
        let status = app.buttons["theme-menu"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertEqual(title.value as? String, "Basic Formatting")
        XCTAssertTrue((status.value as? String ?? "").contains("默认亮色"))
        XCTAssertFalse(app.staticTexts["demo-current-title"].exists)

        app.buttons["view-markdown-source"].tap()
        XCTAssertTrue(app.staticTexts["markdown-source-content"].label.contains("# Basic Text Formatting"))
        app.buttons["关闭"].tap()

        chooseLanguage("en", app: app)
        XCTAssertEqual(title.value as? String, "Basic Formatting")
        app.buttons["theme-menu"].tap()
        app.buttons["Default Dark"].tap()
        XCTAssertTrue((status.value as? String ?? "").contains("Default Dark"))

        let translated: [(String, String)] = [
            ("ja", "デフォルトダーク"),
            ("es", "Oscuro Predeterminado"),
            ("fr", "Sombre Par Défaut"),
            ("ko", "기본 다크"),
            ("zh", "默认暗色"),
        ]
        for (code, expectedTheme) in translated {
            chooseLanguage(code, app: app)
            XCTAssertEqual(title.value as? String, "Basic Formatting")
            XCTAssertTrue((status.value as? String ?? "").contains(expectedTheme))
        }

        choosePage("feature-math", app: app)
        XCTAssertTrue(app.navigationBars["Math Formula Demo"].waitForExistence(timeout: 5))
        app.buttons["demo-feature-back"].tap()
        choosePage("example-headers", app: app)
        XCTAssertEqual(title.value as? String, "Headers")
        XCTAssertTrue((status.value as? String ?? "").contains("默认暗色"))

        app.buttons["view-markdown-source"].tap()
        XCTAssertTrue(app.staticTexts["markdown-source-content"].label.contains("# Header 1"))
    }

    private func chooseLanguage(_ code: String, app: XCUIApplication) {
        choosePage("language-\(code)", app: app)
    }

    private func choosePage(_ identifier: String, app: XCUIApplication) {
        app.buttons["open-examples"].tap()
        let navigationList = app.descendants(matching: .any)["demo-navigation-list"]
        XCTAssertTrue(navigationList.waitForExistence(timeout: 5))
        let entry = app.buttons[identifier]
        for _ in 0..<18 where !entry.isHittable { navigationList.swipeUp() }
        XCTAssertTrue(entry.isHittable, "Missing navigation entry: \(identifier)")
        entry.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }
}
