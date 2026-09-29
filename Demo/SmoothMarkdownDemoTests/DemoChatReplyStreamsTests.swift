import Foundation
@testable import SmoothMarkdownDemo
import XCTest

@MainActor
final class DemoChatReplyStreamsTests: XCTestCase {
    func testMockAIChatScheduleKeepsExactUTF16AndCatchesUpAfterLayoutDelay() {
        let response = "abcd😀ef✨gh"
        let chunks = MockAIChatSchedule.chunks(response, sizeUTF16: 5)
        XCTAssertEqual(chunks.first, "abcd😀")
        XCTAssertEqual(chunks.joined(), response)
        XCTAssertEqual(MockAIChatSchedule.dueChunkCount(elapsedMillis: 0, delayMillis: 20,
                                                        totalChunks: chunks.count), 1)
        XCTAssertEqual(MockAIChatSchedule.dueChunkCount(elapsedMillis: 20, delayMillis: 20,
                                                        totalChunks: chunks.count), 2)
        XCTAssertEqual(MockAIChatSchedule.dueChunkCount(elapsedMillis: 200, delayMillis: 20,
                                                        totalChunks: chunks.count), chunks.count)
    }

    func testCompletionPublishesFullReplyAndRecycledBubbleCanReadSameStream() {
        let store = DemoChatReplyStreams()
        let id = UUID()
        let run = store.start(messageID: id)
        let bubbleStream = store.stream(for: id)
        XCTAssertNotNil(bubbleStream)
        XCTAssertTrue(store.append("**hel", to: id, in: run))
        XCTAssertTrue(store.stream(for: id) === bubbleStream)
        XCTAssertTrue(store.append("lo**", to: id, in: run))
        XCTAssertEqual(store.finish(messageID: id, in: run), "**hello**")
        XCTAssertNil(store.stream(for: id))
        XCTAssertEqual(bubbleStream?.visibleText, "**hello**")
    }

    func testNewConversationRejectsLateChunksAndKeepsNextReplyIsolated() {
        let store = DemoChatReplyStreams()
        let oldID = UUID()
        let oldRun = store.start(messageID: oldID)
        XCTAssertTrue(store.append("old", to: oldID, in: oldRun))
        XCTAssertEqual(store.cancelAll()[oldID], "old")

        let nextID = UUID()
        let nextRun = store.start(messageID: nextID)
        XCTAssertNotEqual(oldRun, nextRun)
        XCTAssertFalse(store.append(" stale", to: oldID, in: oldRun))
        XCTAssertNil(store.finish(messageID: oldID, in: oldRun))
        XCTAssertTrue(store.append("new", to: nextID, in: nextRun))
        XCTAssertEqual(store.finish(messageID: nextID, in: nextRun), "new")
    }
}
