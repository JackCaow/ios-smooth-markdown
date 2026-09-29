import Foundation
import XCTest
@testable import SmoothMarkdown

@MainActor
final class MarkdownEditorPerformanceTests: XCTestCase {
    func testSnapshotUsesUTF16AndReportsOnlyAvailableNativeMetrics() {
        let controller = MarkdownEditorController(text: "# 😀\n\nfind find")
        controller.mode = .formatted
        let now = Date(timeIntervalSince1970: 123)
        let snapshot = MarkdownEditorPerformanceSnapshot.capture(
            controller: controller, searchQuery: "find", isComposing: true, timestamp: now)

        XCTAssertEqual(snapshot.sourceLength, (controller.text as NSString).length)
        XCTAssertEqual(snapshot.blockCount, 2)
        XCTAssertNil(snapshot.formattedSegmentCount)
        XCTAssertEqual(snapshot.mode, .formatted)
        XCTAssertTrue(snapshot.isComposing)
        XCTAssertEqual(snapshot.searchMatchCount, 2)
        XCTAssertEqual(snapshot.timestamp, now)
        XCTAssertNil(snapshot.formattedSegmentCacheHit)
        XCTAssertNil(snapshot.retainedFormattedSegmentKeyCount)
        XCTAssertNil(snapshot.slashSuggestionsVisible)
        XCTAssertNil(snapshot.wikilinkSuggestionsVisible)
    }

    func testReporterCoalescesSynchronousChangesAndDropsCancelledSnapshot() {
        let controller = MarkdownEditorController(text: "a")
        var queued: [@MainActor () -> Void] = []
        let reporter = MarkdownEditorPerformanceReporter { queued.append($0) }
        var emitted: [MarkdownEditorPerformanceSnapshot] = []
        reporter.schedule(snapshot: {
            MarkdownEditorPerformanceSnapshot.capture(controller: controller,
                                                      searchQuery: "", isComposing: false)
        }, callback: { emitted.append($0) })
        controller.replaceSelection("b")
        controller.replaceSelection("c")
        reporter.schedule(snapshot: {
            MarkdownEditorPerformanceSnapshot.capture(controller: controller,
                                                      searchQuery: "bc", isComposing: false)
        }, callback: { emitted.append($0) })
        XCTAssertEqual(queued.count, 1)
        queued.removeFirst()()
        XCTAssertEqual(emitted.map(\.sourceLength), [3])
        XCTAssertEqual(emitted.map(\.searchMatchCount), [1])

        reporter.schedule(snapshot: {
            MarkdownEditorPerformanceSnapshot.capture(controller: controller,
                                                      searchQuery: "", isComposing: false)
        }, callback: { emitted.append($0) })
        reporter.cancel()
        queued.removeFirst()()
        XCTAssertEqual(emitted.count, 1)
    }

    func testSourceFocusTrackerEmitsOnlyTransitions() {
        let tracker = MarkdownEditorSourceFocusTracker()
        var transitions: [Bool] = []
        tracker.setFocused(false) { transitions.append($0) }
        tracker.setFocused(true) { transitions.append($0) }
        tracker.setFocused(true) { transitions.append($0) }
        tracker.setFocused(false) { transitions.append($0) }
        tracker.setFocused(false) { transitions.append($0) }
        XCTAssertEqual(transitions, [true, false])
    }
}
