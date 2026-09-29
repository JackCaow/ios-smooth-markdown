import XCTest

/// Compiled with the generic iOS Demo gate. Runtime acceptance requires a
/// separately recorded physical-device run.
final class QuoteEditorUITests: XCTestCase {
    func testQuoteRowsExposeCharacterSelectionActionsInBlocksMode() {
        let app = XCUIApplication()
        app.launch()
        app.buttons["open-demo-editor"].tap()
        let row = app.textViews.matching(NSPredicate(format: "identifier BEGINSWITH 'quote-line-'"))
            .firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH 'quote-range-start-'"))
            .firstMatch.exists)
        XCTAssertTrue(app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH 'quote-range-end-'"))
            .firstMatch.exists)
    }
}
