#if os(iOS)
import XCTest
import UIKit
@testable import SmoothMarkdown

final class ReaderTextSelectionMenuTests: XCTestCase {
    func testNativeTextMenuReceivesSelectedUTF16RangeAndSuggestedActions() {
        let view = ReaderSelectionTextView.makeTextView()
        view.text = "Before 😀 selected after"
        let selectedRange = (view.text as NSString).range(of: "selected")
        let suggestion = UIAction(title: "Copy") { _ in }
        var receivedText: String?
        var receivedActions: [UIMenuElement] = []
        let coordinator = ReaderSelectionTextView.Coordinator(onLinkTap: nil,
                                                              onTextLongPress: nil,
                                                              onCharacterTap: nil)
        coordinator.textSelectionMenuBuilder = { text, actions in
            receivedText = text
            receivedActions = actions
            return UIMenu(children: actions)
        }

        let menu = coordinator.textView(view, editMenuForTextIn: selectedRange,
                                        suggestedActions: [suggestion])

        XCTAssertEqual(receivedText, "selected")
        XCTAssertEqual(receivedActions.count, 1)
        XCTAssertTrue(receivedActions.first === suggestion)
        XCTAssertEqual(menu?.children.count, 1)
        XCTAssertNil(coordinator.textView(view, editMenuForTextIn: NSRange(location: 0, length: 0),
                                          suggestedActions: [suggestion]))
    }

    func testAbsentBuilderLeavesSystemMenuInControl() {
        let view = ReaderSelectionTextView.makeTextView()
        view.text = "Reader"
        let coordinator = ReaderSelectionTextView.Coordinator(onLinkTap: nil,
                                                              onTextLongPress: nil,
                                                              onCharacterTap: nil)
        XCTAssertNil(coordinator.textView(view,
                                          editMenuForTextIn: NSRange(location: 0, length: 6),
                                          suggestedActions: []))
    }
}
#endif
