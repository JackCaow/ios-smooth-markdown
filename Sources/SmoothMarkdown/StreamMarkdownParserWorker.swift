import Foundation
#if canImport(SmoothMarkdownCore)
@_spi(ReaderInternals) import SmoothMarkdownCore
#endif

/// The tree contains only owned String, NSRange, array and enum values. It never
/// contains Markup, registries, plugin payloads, borrowed memory or native handles.
struct StreamMarkdownWorkerResult: @unchecked Sendable {
    struct Epoch: Equatable, Sendable {
        let configuration: UInt64
        let replacement: UInt64
    }
    let source: String
    let generation: UInt64
    let version: UInt64
    let baseVersion: UInt64
    let epoch: Epoch
    let tree: NativeMarkdownNode?
    let retainedBlocks: Int
}

/// Pending requests are lock-protected; State and its native handle are accessed
/// exclusively on queue. This encapsulation is the reason for unchecked Sendable.
final class StreamMarkdownParserWorker: @unchecked Sendable {
    private struct Request: Sendable {
        let source: String
        let generation: UInt64
        let version: UInt64
        let configuration: UInt64
        let completion: @Sendable (StreamMarkdownWorkerResult) -> Void
    }
    // Queue-confined state; the only cross-context capture schedules its final reset on queue.
    private final class State: @unchecked Sendable {
        let native = NativeMarkdownStreamSession()
        var source = ""
        var configuration: UInt64?
        var replacement: UInt64 = 0
        var version: UInt64 = 0
    }
    private let queue = DispatchQueue(label: "SmoothMarkdown.stream-parser", qos: .userInitiated)
    private let lock = NSLock()
    private var pending: Request?
    private var draining = false
    private let state = State()
    /// Internal deterministic-test hook. Runs on the parser queue, before FFI.
    private let beforeParse: (@Sendable (String) -> Void)?

    init(beforeParse: (@Sendable (String) -> Void)? = nil) { self.beforeParse = beforeParse }

    deinit {
        let state = state
        // Retain the owner until reset/free finishes on the same queue as update.
        queue.async { state.native.reset() }
    }

    func submit(source: String, generation: UInt64, version: UInt64, configuration: UInt64,
                completion: @escaping @Sendable (StreamMarkdownWorkerResult) -> Void) {
        lock.lock()
        pending = Request(source: source, generation: generation, version: version,
                          configuration: configuration, completion: completion)
        let start = !draining
        draining = true
        lock.unlock()
        if start { queue.async { self.drain() } }
    }

    func invalidate() {
        lock.lock(); pending = nil; lock.unlock()
    }

    private func nextRequest() -> Request? {
        lock.lock(); defer { lock.unlock() }
        guard let request = pending else { draining = false; return nil }
        pending = nil
        return request
    }

    private func drain() {
        while let request = nextRequest() {
            beforeParse?(request.source)
            let replacing = state.configuration != request.configuration ||
                !request.source.utf16.starts(with: state.source.utf16)
            if replacing {
                state.native.reset()
                state.replacement &+= 1
                state.version = 0
            }
            let base = state.version
            let snapshot = state.native.update(request.source)
            // Commit worker state even when the UI later discards this result.
            state.source = request.source
            state.configuration = request.configuration
            state.version = request.version
            let result = StreamMarkdownWorkerResult(source: request.source, generation: request.generation,
                version: request.version, baseVersion: base,
                epoch: .init(configuration: request.configuration, replacement: state.replacement),
                tree: snapshot?.tree, retainedBlocks: snapshot?.retainedBlocks ?? 0)
            request.completion(result)
        }
    }
}
