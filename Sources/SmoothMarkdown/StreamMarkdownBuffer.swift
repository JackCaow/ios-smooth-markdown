import Combine
import Foundation

/// Accumulates streaming source and limits visible document updates to one per interval.
public struct StreamMarkdownBuffer {
    public private(set) var fullText = ""
    public private(set) var visibleText = ""
    private let intervalMillis: Int64
    private var enableHTML: Bool
    private var isFinished = false
    private var lastUpdateMillis: Int64

    public init(intervalMillis: Int64 = 50, startMillis: Int64 = 0, enableHTML: Bool = false) {
        self.intervalMillis = max(0, intervalMillis)
        self.enableHTML = enableHTML
        self.lastUpdateMillis = startMillis
    }

    /// Returns milliseconds until a pending update, or nil when this chunk was published.
    public mutating func append(_ chunk: String, nowMillis: Int64) -> Int64? {
        fullText.append(chunk)
        let remaining = intervalMillis - (nowMillis - lastUpdateMillis)
        if remaining <= 0 {
            flush(nowMillis: nowMillis)
            return nil
        }
        return remaining
    }

    public mutating func flush(nowMillis: Int64) {
        visibleText = enableHTML ? SafeHTML.safeRenderPrefix(fullText) : fullText
        lastUpdateMillis = nowMillis
    }

    public mutating func finish(nowMillis: Int64) {
        isFinished = true
        visibleText = fullText
        lastUpdateMillis = nowMillis
    }

    /// Re-render the accumulated prefix without losing chunks or restarting the stream.
    public mutating func setHTML(_ enabled: Bool) {
        guard enableHTML != enabled else { return }
        enableHTML = enabled
        visibleText = isFinished ? fullText : (enabled ? SafeHTML.safeRenderPrefix(fullText) : fullText)
    }

    public mutating func reset(nowMillis: Int64) {
        fullText = ""
        visibleText = ""
        isFinished = false
        lastUpdateMillis = nowMillis
    }
}

@MainActor
public final class StreamMarkdownAccumulator: ObservableObject {
    @Published public private(set) var visibleText = ""
    private var buffer: StreamMarkdownBuffer
    private var pending: Task<Void, Never>?
    private var throttleMillis: Int64
    private var enableHTML: Bool
    /// Invalidates callbacks from a previous stream when a view starts another one.
    var generation: UInt64 = 0

    public init(throttleMillis: Int64 = 50, enableHTML: Bool = false) {
        self.throttleMillis = max(0, throttleMillis)
        self.enableHTML = enableHTML
        buffer = StreamMarkdownBuffer(intervalMillis: self.throttleMillis, startMillis: Self.nowMillis(), enableHTML: enableHTML)
    }

    public func reset(throttleMillis: Int64? = nil, enableHTML: Bool? = nil) {
        generation &+= 1
        pending?.cancel()
        pending = nil
        if let throttleMillis { self.throttleMillis = max(0, throttleMillis) }
        if let enableHTML { self.enableHTML = enableHTML }
        buffer = StreamMarkdownBuffer(intervalMillis: self.throttleMillis, startMillis: Self.nowMillis(), enableHTML: self.enableHTML)
        visibleText = ""
    }

    public func append(_ chunk: String) {
        let wait = buffer.append(chunk, nowMillis: Self.nowMillis())
        pending?.cancel()
        pending = nil
        if let wait {
            pending = Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(wait) * 1_000_000)
                guard !Task.isCancelled else { return }
                self.buffer.flush(nowMillis: Self.nowMillis())
                self.visibleText = self.buffer.visibleText
                self.pending = nil
            }
        } else {
            visibleText = buffer.visibleText
        }
    }

    func append(_ chunk: String, for generation: UInt64) {
        guard self.generation == generation else { return }
        append(chunk)
    }

    public func finish() {
        pending?.cancel()
        pending = nil
        buffer.finish(nowMillis: Self.nowMillis())
        visibleText = buffer.visibleText
    }

    func finish(for generation: UInt64) {
        guard self.generation == generation else { return }
        finish()
    }

    public func setHTML(_ enabled: Bool) {
        enableHTML = enabled
        buffer.setHTML(enabled)
        visibleText = buffer.visibleText
    }

    public func cancel() {
        pending?.cancel()
        pending = nil
    }

    func cancel(for generation: UInt64) {
        guard self.generation == generation else { return }
        cancel()
    }

    func isCurrent(_ generation: UInt64) -> Bool { self.generation == generation }

    private static func nowMillis() -> Int64 {
        Int64(ProcessInfo.processInfo.systemUptime * 1000)
    }
}
