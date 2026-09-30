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

    func testNativeImageRangeMenuReceivesCopyTextWithoutImageAnchor() {
        let source = "Before 😀\n█\nAfter"
        let anchor = (source as NSString).range(of: "█").location
        let view = ReaderNativeImageTextView(usingTextLayoutManager: false)
        view.attributedText = NSAttributedString(string: source)
        view.imageAnchorsUTF16 = [anchor]
        let coordinator = ReaderNativeImageSelectionView.Coordinator(onLinkTap: nil)
        let suggestion = UIAction(title: "Copy") { _ in }
        var received: String?
        coordinator.textSelectionMenuBuilder = { text, actions in
            received = text
            XCTAssertTrue(actions.first === suggestion)
            return UIMenu(children: actions)
        }

        let menu = coordinator.textView(view,
                                        editMenuForTextIn: NSRange(location: 0,
                                                                   length: (source as NSString).length),
                                        suggestedActions: [suggestion])
        XCTAssertEqual(received, "Before 😀\nAfter")
        XCTAssertEqual(menu?.children.count, 1)
        XCTAssertNil(coordinator.textView(view,
                                          editMenuForTextIn: NSRange(location: anchor, length: 1),
                                          suggestedActions: [suggestion]))
        XCTAssertEqual(received, "Before 😀\nAfter")
    }

    func testBlockActionsOfferExactCopyTextToBuilderAndKeepCopySuggestion() {
        let before = MarkdownSyntax.parse("Before 😀").child(at: 0)!
        let code = MarkdownSyntax.parse("```swift\nlet answer = 42\n```").child(at: 0)!
        let document = ReaderBlockRangeDocument([.markup(before), .displayMath("x+y"), .markup(code)],
                                                enableHTML: false, plugins: nil)!
        let expected = document.copiedText(in: 0...2, enableHTML: false, plugins: nil)!
        XCTAssertEqual(expected, "Before 😀\nx+y\nlet answer = 42\n")
        var received: String?
        let menu = ReaderSelectionActionsButton.menu(selectedText: expected, builder: { text, actions in
            received = text
            XCTAssertEqual(actions.count, 1)
            XCTAssertEqual((actions.first as? UIAction)?.title, "Copy")
            return UIMenu(children: actions)
        }, copy: {})
        XCTAssertEqual(received, expected)
        XCTAssertEqual(menu.children.count, 1)
    }

    func testBundledPluginActionsUseParsedBodyAndSkipUnknownCustomViews() {
        let content = "line one\nline two"
        for id in ["thinking", "artifact", "tool_call", "admonition", "mermaid"] {
            let text = ReaderPluginSelectionText.copyText(pluginID: id, content: content)
            XCTAssertEqual(text, content)
            var received: String?
            _ = ReaderSelectionActionsButton.menu(selectedText: text!, builder: { selected, actions in
                received = selected
                return UIMenu(children: actions)
            }, copy: {})
            XCTAssertEqual(received, content)
        }
        XCTAssertNil(ReaderPluginSelectionText.copyText(pluginID: "custom", content: content))
        XCTAssertNil(ReaderPluginSelectionText.copyText(pluginID: "thinking", content: ""))
    }
}
#endif
