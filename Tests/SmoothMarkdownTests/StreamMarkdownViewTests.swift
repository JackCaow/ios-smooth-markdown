import SmoothMarkdown
import SwiftUI
import XCTest

final class StreamMarkdownViewTests: XCTestCase {
    func testReaderAndPlaceholderOptionsAreExposedByStreamView() {
        let options = CodeBlockOptions(showCopyButton: false, showLanguageTag: false,
                                       enableSyntaxHighlighting: false)
        let stream = StreamMarkdownView(
            chunks: AsyncStream<String> { $0.finish() },
            streamID: "reply-2",
            codeBlockOptions: options,
            onTextLongPress: { _ in },
            selectable: true,
            enableCrossBlockSelection: false,
            scrollable: false,
            loadingView: AnyView(Text("Waiting")),
            errorBuilder: { _ in AnyView(Text("Failed")) }
        )

        XCTAssertEqual(stream.streamID, "reply-2")
        XCTAssertEqual(stream.codeBlockOptions, options)
        XCTAssertTrue(stream.selectable)
        XCTAssertFalse(stream.enableCrossBlockSelection)
        XCTAssertFalse(stream.scrollable)
        XCTAssertNotNil(stream.onTextLongPress)
        XCTAssertNotNil(stream.loadingView)
        XCTAssertNotNil(stream.errorBuilder)
    }

    func testDefaultsKeepLoadingViewEmptyAndReaderUnselectable() {
        let stream = StreamMarkdownView(chunks: AsyncStream<String> { $0.finish() })
        XCTAssertFalse(stream.selectable)
        XCTAssertTrue(stream.enableCrossBlockSelection)
        XCTAssertTrue(stream.scrollable)
        XCTAssertNil(stream.loadingView)
        XCTAssertNil(stream.errorBuilder)
    }
}
