import XCTest

final class DemoLanguageUITests: XCTestCase {
    func testSixLanguagesKeepSelectedPageThemeAndMarkdownSource() {
        let app = XCUIApplication()
        app.launch()

        let title = app.staticTexts["demo-current-title"]
        let status = app.staticTexts["demo-current-theme"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertEqual(title.label, "基础格式")
        XCTAssertTrue(status.label.contains("默认亮色"))

        app.buttons["view-markdown-source"].tap()
        XCTAssertTrue(app.staticTexts["markdown-source-content"].label.contains("# Basic Text Formatting"))
        app.buttons["关闭"].tap()

        chooseLanguage("en", app: app)
        XCTAssertEqual(title.label, "Basic Formatting")
        app.buttons["theme-menu"].tap()
        app.buttons["Default Dark"].tap()
        XCTAssertTrue(status.label.contains("Default Dark"))

        let translated: [(String, String, String)] = [
            ("ja", "基本書式", "デフォルトダーク"),
            ("es", "Formato Básico", "Oscuro Predeterminado"),
            ("fr", "Formatage de Base", "Sombre Par Défaut"),
            ("ko", "기본 서식", "기본 다크"),
            ("zh", "基础格式", "默认暗色"),
        ]
        for (code, expectedTitle, expectedTheme) in translated {
            chooseLanguage(code, app: app)
            XCTAssertEqual(title.label, expectedTitle)
            XCTAssertTrue(status.label.contains(expectedTheme))
        }

        choosePage("feature-math", app: app)
        XCTAssertEqual(title.label, "数学公式")
        choosePage("example-headers", app: app)
        XCTAssertEqual(title.label, "标题")
        XCTAssertTrue(status.label.contains("默认暗色"))

        app.buttons["view-markdown-source"].tap()
        XCTAssertTrue(app.staticTexts["markdown-source-content"].label.contains("# Header 1"))
    }

    private func chooseLanguage(_ code: String, app: XCUIApplication) {
        choosePage("language-\(code)", app: app)
    }

    private func choosePage(_ identifier: String, app: XCUIApplication) {
        app.buttons["open-examples"].tap()
        let entry = app.buttons[identifier]
        for _ in 0..<18 where !entry.isHittable { app.swipeUp() }
        XCTAssertTrue(entry.waitForExistence(timeout: 5), "Missing navigation entry: \(identifier)")
        entry.tap()
    }
}
