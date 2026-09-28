import Combine
import Foundation

/// Accumulates streaming source and limits visible document updates to one per interval.
public struct StreamMarkdownBuffer {
    public private(set) var fullText = ""
    public private(set) var visibleText = ""
    private let intervalMillis: Int64
    private var lastUpdateMillis: Int64

    public init(intervalMillis: Int64 = 50, startMillis: Int64 = 0) {
        self.intervalMillis = max(0, intervalMillis)
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
        visibleText = fullText
        lastUpdateMillis = nowMillis
    }

    public mutating func finish(nowMillis: Int64) { flush(nowMillis: nowMillis) }

    public mutating func reset(nowMillis: Int64) {
        fullText = ""
        visibleText = ""
        lastUpdateMillis = nowMillis
    }
}

@MainActor
public final class StreamMarkdownAccumulator: ObservableObject {
    @Published public private(set) var visibleText = ""
    private var buffer: StreamMarkdownBuffer
    private var pending: Task<Void, Never>?
    private var throttleMillis: Int64

    public init(throttleMillis: Int64 = 50) {
        self.throttleMillis = max(0, throttleMillis)
        buffer = StreamMarkdownBuffer(intervalMillis: self.throttleMillis, startMillis: Self.nowMillis())
    }

    public func reset(throttleMillis: Int64? = nil) {
        pending?.cancel()
        pending = nil
        if let throttleMillis { self.throttleMillis = max(0, throttleMillis) }
        buffer = StreamMarkdownBuffer(intervalMillis: self.throttleMillis, startMillis: Self.nowMillis())
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

    public func finish() {
        pending?.cancel()
        pending = nil
        buffer.finish(nowMillis: Self.nowMillis())
        visibleText = buffer.visibleText
    }

    public func cancel() {
        pending?.cancel()
        pending = nil
    }

    private static func nowMillis() -> Int64 {
        Int64(ProcessInfo.processInfo.systemUptime * 1000)
    }
}
