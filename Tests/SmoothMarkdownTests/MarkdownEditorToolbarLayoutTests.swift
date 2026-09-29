import XCTest
@testable import SmoothMarkdown

final class MarkdownEditorToolbarLayoutTests: XCTestCase {
    func testHostSlotsSurroundNativeControlsInSuppliedOrder() {
        let layout = MarkdownEditorToolbarLayout(showToolbar: true, focusMode: false,
                                                 leadingCount: 2, trailingCount: 2)
        XCTAssertEqual(layout.sections, [.leading(0), .leading(1), .history,
                                         .commands, .trailing(0), .trailing(1)])
    }

    func testFocusModeAndHostVisibilityHideEntireToolbar() {
        XCTAssertTrue(MarkdownEditorToolbarLayout(showToolbar: false, focusMode: false,
                                                  leadingCount: 1, trailingCount: 1).sections.isEmpty)
        XCTAssertTrue(MarkdownEditorToolbarLayout(showToolbar: true, focusMode: true,
                                                  leadingCount: 1, trailingCount: 1).sections.isEmpty)
    }
}
