@testable import SmoothMarkdown
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

    func testStreamingHTMLScriptsRemainTaggedAcrossChunkBoundaries() {
        var buffer = StreamMarkdownBuffer(startMillis: 0, enableHTML: true)
        XCTAssertNil(buffer.append("H<su", nowMillis: 50))
        XCTAssertEqual(buffer.visibleText, "H")
        XCTAssertNil(buffer.append("b>2", nowMillis: 100))
        XCTAssertEqual(buffer.visibleText, "H<sub>2")
        let partial = MarkdownSyntax.parse(buffer.visibleText, enableHTML: true).child(at: 0)!
        let subRun = InlineContent.runs(in: partial, enableHTML: true).compactMap { run -> [SafeHTML.Tag]? in
            if case let .text("2", _, tags, _) = run { return tags }
            return nil
        }.first
        XCTAssertEqual(subRun?.last?.name, "sub")

        XCTAssertNil(buffer.append("</sub>O e=mc<sup>2</sup>", nowMillis: 150))
        let complete = MarkdownSyntax.parse(buffer.visibleText, enableHTML: true).child(at: 0)!
        let scripts = InlineContent.runs(in: complete, enableHTML: true).compactMap { run -> String? in
            if case let .text("2", _, tags, _) = run { return tags.last?.name }
            return nil
        }
        XCTAssertEqual(scripts, ["sub", "sup"])
    }

    func testHTMLToggleReRendersAccumulatedPrefixAndPreservesStream() {
        var buffer = StreamMarkdownBuffer(startMillis: 0, enableHTML: true)
        XCTAssertNil(buffer.append("lead <font colo", nowMillis: 50))
        XCTAssertEqual(buffer.visibleText, "lead ")
        buffer.setHTML(false)
        XCTAssertEqual(buffer.visibleText, "lead <font colo")
        buffer.setHTML(true)
        XCTAssertEqual(buffer.visibleText, "lead ")
        XCTAssertEqual(buffer.fullText, "lead <font colo")
        buffer.append("r=red>red</font>", nowMillis: 100)
        XCTAssertEqual(buffer.visibleText, "lead <font color=red>red</font>")
        buffer.finish(nowMillis: 101)
        buffer.setHTML(false)
        XCTAssertEqual(buffer.visibleText, buffer.fullText)
    }

    @MainActor
    func testOldStreamCallbacksCannotChangeNewStream() {
        let accumulator = StreamMarkdownAccumulator(throttleMillis: 0)
        accumulator.reset()
        let oldGeneration = accumulator.generation
        accumulator.append("old", for: oldGeneration)
        XCTAssertEqual(accumulator.visibleText, "old")

        accumulator.reset()
        let newGeneration = accumulator.generation
        XCTAssertNotEqual(oldGeneration, newGeneration)
        XCTAssertEqual(accumulator.visibleText, "")

        accumulator.append(" late", for: oldGeneration)
        accumulator.finish(for: oldGeneration)
        accumulator.cancel(for: oldGeneration)
        XCTAssertEqual(accumulator.visibleText, "")

        accumulator.append("new", for: newGeneration)
        accumulator.finish(for: newGeneration)
        XCTAssertEqual(accumulator.visibleText, "new")
    }
}
