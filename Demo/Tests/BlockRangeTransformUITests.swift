import XCTest

/// Compiled in CI; run on a physical iPhone for menu and touch acceptance.
final class BlockRangeTransformUITests: XCTestCase {
    func testFormattedBlockRangeCanTransformIntoOneList() {
        let app = XCUIApplication()
        app.launch()
        app.buttons["open-demo-editor"].tap()
        let start = app.buttons["block-range-block-0"]
        let end = app.buttons["block-range-block-1"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        start.tap()
        XCTAssertTrue(end.waitForExistence(timeout: 10))
        end.tap()
        let transform = app.buttons["block-range-transform"]
        XCTAssertTrue(transform.waitForExistence(timeout: 10))
        transform.tap()
        app.buttons["Bullet list"].tap()
        XCTAssertFalse(transform.exists)
    }
}
