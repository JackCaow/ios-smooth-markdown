import XCTest

final class DemoPluginUITests: XCTestCase {
    func testFlutterPluginSourceAndTapFeedback() {
        let app = XCUIApplication()
        app.launch()
        app.buttons["open-examples"].tap()
        let entry = app.buttons["feature-plugins"]
        for _ in 0..<15 where !entry.isHittable { app.swipeUp() }
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.tap()

        XCTAssertTrue(app.staticTexts["插件系统演示"].waitForExistence(timeout: 5))

        let mention = app.buttons["plugin-mention-john"]
        for _ in 0..<5 where !mention.isHittable { app.swipeUp() }
        XCTAssertTrue(mention.isHittable)
        mention.tap()
        XCTAssertEqual(app.staticTexts["plugin-demo-feedback"].label, "点击了用户: @john")

        let hashtag = app.buttons["plugin-hashtag-flutter"]
        for _ in 0..<5 where !hashtag.isHittable { app.swipeUp() }
        XCTAssertTrue(hashtag.isHittable)
        hashtag.tap()
        XCTAssertEqual(app.staticTexts["plugin-demo-feedback"].label, "点击了标签: #flutter")

        let source = app.buttons["plugin-demo-source-toggle"]
        for _ in 0..<15 where !source.isHittable { app.swipeUp() }
        XCTAssertTrue(source.isHittable)
        source.tap()
        let markdown = app.descendants(matching: .any).matching(identifier: "plugin-demo-source").firstMatch
        XCTAssertTrue(markdown.waitForExistence(timeout: 5))
        XCTAssertTrue(markdown.label.contains("::: danger 危险"))
    }
}
