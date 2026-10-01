@testable import SmoothMarkdown
#if canImport(SmoothMarkdownCore)
@_spi(ReaderInternals) import SmoothMarkdownCore
#endif
import XCTest

private final class WorkerProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [StreamMarkdownWorkerResult] = []
    private var sources: [String] = []
    private var main = false
    func parsing(_ source: String) {
        lock.lock(); sources.append(source); main = main || Thread.isMainThread; lock.unlock()
    }
    func append(_ result: StreamMarkdownWorkerResult) { lock.lock(); stored.append(result); lock.unlock() }
    var results: [StreamMarkdownWorkerResult] { lock.lock(); defer { lock.unlock() }; return stored }
    var parsedSources: [String] { lock.lock(); defer { lock.unlock() }; return sources }
    var parsedOnMain: Bool { lock.lock(); defer { lock.unlock() }; return main }
}

@MainActor
final class StreamMarkdownBackgroundTests: XCTestCase {
    private func requireRust() throws {
        guard NativeMarkdownExtensionProjection.isAvailable else { throw XCTSkip("Packaged Rust backend required") }
    }

    private func waitForFinishRegistration(_ accumulator: StreamMarkdownAccumulator) async {
        for _ in 0..<1000 {
            if accumulator.isWaitingForFinalPublication { return }
            await Task.yield()
        }
        XCTFail("Finish did not register its final publication waiter")
    }

    func testWorkerKeepsLatestPrefixCommitsSkippedStateAndDoesNotParseOnMain() throws {
        try requireRust()
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let done = DispatchSemaphore(value: 0)
        let probe = WorkerProbe()
        let initial = "# Head\n\nOne\n\nTwo\n\nTail"
        let worker = StreamMarkdownParserWorker { source in
            probe.parsing(source)
            if source == initial { entered.signal(); _ = release.wait(timeout: .now() + 5) }
        }
        worker.submit(source: initial, generation: 1, version: 1, configuration: 1) { probe.append($0) }
        XCTAssertEqual(entered.wait(timeout: .now() + 2), .success)
        worker.submit(source: initial + " x", generation: 1, version: 2, configuration: 1) { probe.append($0) }
        worker.submit(source: initial + " xy\n\nFinal", generation: 1, version: 3, configuration: 1) {
            probe.append($0); done.signal()
        }
        release.signal()
        XCTAssertEqual(done.wait(timeout: .now() + 2), .success)
        let results = probe.results
        XCTAssertEqual(results.map(\.version), [1, 3])
        XCTAssertEqual(results[1].baseVersion, 1)
        XCTAssertFalse(probe.parsedOnMain)
        XCTAssertEqual(probe.parsedSources.count, 2)
        XCTAssertEqual(results[1].tree, NativeMarkdownExtensionProjection.parse(results[1].source))
        let renderer = StreamMarkdownRenderSession()
        // UI intentionally skips version 1; complete immutable tree restores parity.
        let adapted = renderer.accept(results[1])
        XCTAssertEqual(renderer.reusedBlocks, 0)
        XCTAssertEqual(adapted.document.children.count, results[1].tree?.children.count)
        XCTAssertEqual(adapted.document.format(), results[1].source)
    }

    func testReplacementEpochAndExactUTF16Identity() throws {
        try requireRust()
        let probe = WorkerProbe()
        let done = DispatchSemaphore(value: 0)
        let worker = StreamMarkdownParserWorker()
        let first = "e\u{301}\n\nOne\n\nTwo\n\nTail"
        worker.submit(source: first, generation: 1, version: 1, configuration: 1) { probe.append($0); done.signal() }
        XCTAssertEqual(done.wait(timeout: .now() + 2), .success)
        let second = "é\n\nOne\n\nTwo\n\nTail"
        XCTAssertEqual(first, second)
        worker.submit(source: second, generation: 1, version: 2, configuration: 1) { probe.append($0); done.signal() }
        XCTAssertEqual(done.wait(timeout: .now() + 2), .success)
        XCTAssertNotEqual(probe.results[0].epoch, probe.results[1].epoch)
        XCTAssertEqual(probe.results[1].baseVersion, 0)
        XCTAssertEqual(probe.results[1].retainedBlocks, 0)
        XCTAssertEqual(Array(probe.results[1].tree!.source.utf16), Array(second.utf16))
    }

    func testFinishWaitsForFinalParseAndPublishesOnceOnMainActor() async throws {
        try requireRust()
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let worker = StreamMarkdownParserWorker { _ in entered.signal(); _ = release.wait(timeout: .now() + 5) }
        let accumulator = StreamMarkdownAccumulator(throttleMillis: 0)
        accumulator.prepareRenderer(plugins: nil, enableHTML: false, background: true, worker: worker)
        accumulator.append("# Final\n\nBody")
        XCTAssertEqual(entered.wait(timeout: .now() + 2), .success)
        XCTAssertEqual(accumulator.visibleText, "")
        let generation = accumulator.generation
        let finished = Task { @MainActor in
            let result = await accumulator.finishAndWait(for: generation)
            XCTAssertTrue(Thread.isMainThread)
            return result
        }
        await waitForFinishRegistration(accumulator)
        XCTAssertEqual(accumulator.visibleText, "")
        release.signal()
        // The coalesced final request may have its own parse; let it run as well.
        release.signal()
        let completed = await finished.value
        XCTAssertTrue(completed)
        XCTAssertEqual(accumulator.visibleText, "# Final\n\nBody")
        XCTAssertEqual(accumulator.renderSnapshot?.document.format(), accumulator.visibleText)
        let duplicate = await accumulator.finishAndWait(for: generation)
        XCTAssertFalse(duplicate)
    }

    func testResetAndCancelResolveBlockedFinishAndIgnoreLateOldResult() async throws {
        try requireRust()
        for reset in [false, true] {
            let entered = DispatchSemaphore(value: 0)
            let release = DispatchSemaphore(value: 0)
            let worker = StreamMarkdownParserWorker { _ in entered.signal(); _ = release.wait(timeout: .now() + 5) }
            let accumulator = StreamMarkdownAccumulator(throttleMillis: 0)
            accumulator.prepareRenderer(plugins: nil, enableHTML: false, background: true, worker: worker)
            accumulator.append("old")
            XCTAssertEqual(entered.wait(timeout: .now() + 2), .success)
            let generation = accumulator.generation
            let finished = Task { @MainActor in await accumulator.finishAndWait(for: generation) }
            await waitForFinishRegistration(accumulator)
            if reset { accumulator.reset() } else { accumulator.cancel() }
            let cancelled = await finished.value
            XCTAssertFalse(cancelled)
            release.signal()
            accumulator.reset()
            accumulator.prepareRenderer(plugins: nil, enableHTML: false, background: true)
            accumulator.append("new")
            let completed = await accumulator.finishAndWait(for: accumulator.generation)
            XCTAssertTrue(completed)
            XCTAssertEqual(accumulator.visibleText, "new")
            for _ in 0..<10 { await Task.yield() }
            XCTAssertEqual(accumulator.visibleText, "new")
        }
    }

    func testCancellingFinishTaskReleasesWaiterWithoutPublishingOldResult() async throws {
        try requireRust()
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let worker = StreamMarkdownParserWorker { _ in entered.signal(); _ = release.wait(timeout: .now() + 5) }
        let accumulator = StreamMarkdownAccumulator(throttleMillis: 0)
        accumulator.prepareRenderer(plugins: nil, enableHTML: false, background: true, worker: worker)
        accumulator.append("cancelled")
        XCTAssertEqual(entered.wait(timeout: .now() + 2), .success)
        let generation = accumulator.generation
        let finished = Task { @MainActor in await accumulator.finishAndWait(for: generation) }
        await waitForFinishRegistration(accumulator)
        finished.cancel()
        let cancelled = await finished.value
        XCTAssertFalse(cancelled)
        XCTAssertFalse(accumulator.isWaitingForFinalPublication)
        release.signal()
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(accumulator.visibleText, "")
    }

    func testConfigurationSwitchFinishesLatestSourceAndDropsOldNativeResult() async throws {
        try requireRust()
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let worker = StreamMarkdownParserWorker { _ in entered.signal(); _ = release.wait(timeout: .now() + 5) }
        let accumulator = StreamMarkdownAccumulator(throttleMillis: 0)
        accumulator.prepareRenderer(plugins: nil, enableHTML: false, background: true, worker: worker)
        accumulator.append("@alice")
        XCTAssertEqual(entered.wait(timeout: .now() + 2), .success)
        let finished = Task { @MainActor in await accumulator.finishAndWait(for: accumulator.generation) }
        await waitForFinishRegistration(accumulator)
        let plugins = ParserPluginRegistry()
        try plugins.register(MentionPlugin())
        accumulator.prepareRenderer(plugins: plugins, enableHTML: false, background: true)
        let completed = await finished.value
        XCTAssertTrue(completed)
        XCTAssertTrue(accumulator.renderSnapshot!.document.children.first!.children.contains { $0 is SharedInlinePluginMarkup })
        release.signal()
        for _ in 0..<10 { await Task.yield() }
        XCTAssertTrue(accumulator.renderSnapshot!.matches("@alice", plugins: plugins, enableHTML: false))
    }

    func testRejectedNativeSnapshotKeepsOwnedParserFallback() throws {
        let source = "# Heading\n\n[link](https://example.com)"
        let renderer = StreamMarkdownRenderSession()
        let result = StreamMarkdownWorkerResult(source: source, generation: 1, version: 1, baseVersion: 0,
            epoch: .init(configuration: 1, replacement: 1), tree: nil, retainedBlocks: 0)
        let snapshot = renderer.accept(result)
        XCTAssertTrue(snapshot.document.children.first is Heading)
        XCTAssertEqual((snapshot.document.children.last?.children.first as? Markdown.Link)?.destination, "https://example.com")
    }
}
