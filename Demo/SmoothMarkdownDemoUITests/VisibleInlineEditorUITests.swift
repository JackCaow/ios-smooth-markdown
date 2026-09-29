import XCTest

final class VisibleInlineEditorUITests: XCTestCase {
    private let original = "Start **bold** end\n\n# Next [link](https://example.com) end"

    func testRenderedWordSelectionFormatsInsideExistingBoldAndUndoes() {
        let app = launchFixture()
        let rendered = app.textViews["rendered-paragraph-block-0"]
        XCTAssertTrue(rendered.waitForExistence(timeout: 10))
        XCTAssertEqual(rendered.value as? String, "Start bold end")
        rendered.coordinate(withNormalizedOffset: CGVector(dx: 0.19, dy: 0.5)).doubleTap()

        let format = app.buttons["visible-range-format"]
        XCTAssertTrue(format.waitForExistence(timeout: 5), "A native rendered-text selection should enable formatting")
        format.tap()
        app.buttons["Italic"].tap()

        app.segmentedControls.buttons["Source"].tap()
        let source = app.textViews["markdown-source"]
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        XCTAssertNotEqual(source.value as? String, original)
        XCTAssertTrue((source.value as? String ?? "").contains("https://example.com"))
        app.buttons["Undo"].tap()
        XCTAssertEqual(source.value as? String, original)
    }

    func testNaturalRenderedDragAcrossAdjacentBlocksFormatsInOneUndo() {
        let app = launchFixture()
        let first = app.textViews["rendered-paragraph-block-0"]
        let second = app.textViews["rendered-heading-block-1"]
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        XCTAssertTrue(second.exists)
        XCTAssertEqual(second.value as? String, "Next link end")

        let anchor = first.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.5))
        let focus = second.coordinate(withNormalizedOffset: CGVector(dx: 0.13, dy: 0.5))
        anchor.press(forDuration: 0.6, thenDragTo: focus)

        let format = app.buttons["visible-range-format"]
        XCTAssertTrue(format.waitForExistence(timeout: 5), "Dragging across rendered prose should create a real character range")
        format.tap()
        app.buttons["Italic"].tap()
        app.segmentedControls.buttons["Source"].tap()
        let source = app.textViews["markdown-source"]
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        let changed = source.value as? String ?? ""
        XCTAssertNotEqual(changed, original)
        XCTAssertTrue(changed.contains("https://example.com"))
        app.buttons["Undo"].tap()
        XCTAssertEqual(source.value as? String, original)
    }

    func testRenderedSelectionOffersInlineCodeAndUndoes() {
        assertRenderedFormat("Inline code", sourceMarker: "`")
    }

    func testRenderedSelectionOffersStrikethroughAndUndoes() {
        assertRenderedFormat("Strikethrough", sourceMarker: "~~")
    }

    private func assertRenderedFormat(_ action: String, sourceMarker: String) {
        let app = launchFixture()
        let rendered = app.textViews["rendered-paragraph-block-0"]
        XCTAssertTrue(rendered.waitForExistence(timeout: 10))
        rendered.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5)).doubleTap()

        let format = app.buttons["visible-range-format"]
        XCTAssertTrue(format.waitForExistence(timeout: 5))
        format.tap()
        let menuAction = app.buttons[action]
        XCTAssertTrue(menuAction.waitForExistence(timeout: 5))
        menuAction.tap()

        app.segmentedControls.buttons["Source"].tap()
        let source = app.textViews["markdown-source"]
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        XCTAssertTrue((source.value as? String ?? "").contains(sourceMarker))
        app.buttons["Undo"].tap()
        XCTAssertEqual(source.value as? String, original)
    }

    private func launchFixture() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--visible-inline-editor-fixture"]
        app.launch()
        return app
    }
}
