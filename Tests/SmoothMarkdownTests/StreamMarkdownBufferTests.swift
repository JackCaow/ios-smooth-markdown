import SmoothMarkdown
import XCTest

final class StreamMarkdownBufferTests: XCTestCase {
    func testBatchesRapidChunksAndFlushesOnCompletion() {
        var buffer = StreamMarkdownBuffer(startMillis: 100)
        XCTAssertEqual(buffer.append("Hello", nowMillis: 110), 40)
        XCTAssertEqual(buffer.visibleText, "")
        XCTAssertEqual(buffer.append(" world", nowMillis: 130), 20)
        buffer.flush(nowMillis: 150)
        XCTAssertEqual(buffer.visibleText, "Hello world")
        XCTAssertEqual(buffer.append("!", nowMillis: 160), 40)
        buffer.finish(nowMillis: 161)
        XCTAssertEqual(buffer.visibleText, "Hello world!")
    }

    func testPublishesImmediatelyAfterIntervalAndResetsForNewStream() {
        var buffer = StreamMarkdownBuffer(startMillis: 0)
        XCTAssertNil(buffer.append("A", nowMillis: 50))
        XCTAssertEqual(buffer.visibleText, "A")
        buffer.reset(nowMillis: 200)
        XCTAssertEqual(buffer.fullText, "")
        XCTAssertEqual(buffer.append("B", nowMillis: 210), 40)
        XCTAssertEqual(buffer.visibleText, "")
    }

    func testKeepsPartialHTMLLookingTextVisibleByDefault() {
        var buffer = StreamMarkdownBuffer(startMillis: 0)
        XCTAssertNil(buffer.append("lead <font colo", nowMillis: 50))
        XCTAssertEqual(buffer.visibleText, "lead <font colo")
    }

    func testHTMLModeWithholdsPartialTagThenFlushesOnCompletion() {
        var buffer = StreamMarkdownBuffer(startMillis: 0, enableHTML: true)
        XCTAssertNil(buffer.append("lead <font colo", nowMillis: 50))
        XCTAssertEqual(buffer.visibleText, "lead ")
        buffer.finish(nowMillis: 51)
        XCTAssertEqual(buffer.visibleText, "lead <font colo")
    }
}
