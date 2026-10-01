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
    private var renderSession: StreamMarkdownRenderSession?
    var renderSnapshot: StreamMarkdownRenderSession.Snapshot?
    private var worker: StreamMarkdownParserWorker?
    private var backgroundRendering = false
    private var rendererIdentity: ObjectIdentifier?
    private var rendererHTML = false
    private var requestVersion: UInt64 = 0
    private var configurationEpoch: UInt64 = 0
    private var pendingFinish: CheckedContinuation<Bool, Never>?
    private var pendingFinishGeneration: UInt64?
    private var completedGeneration: UInt64?
    var isWaitingForFinalPublication: Bool { pendingFinish != nil }
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
        invalidateRenderer(cancelFinish: true)
        completedGeneration = nil
        renderSnapshot = nil
        visibleText = ""
    }

    func prepareRenderer(plugins: ParserPluginRegistry?, enableHTML: Bool,
                         background: Bool = false, worker injectedWorker: StreamMarkdownParserWorker? = nil) {
        let identity = plugins.map(ObjectIdentifier.init)
        if identity != rendererIdentity || rendererHTML != enableHTML || background != backgroundRendering {
            invalidateRenderer(cancelFinish: false)
        }
        rendererIdentity = identity
        rendererHTML = enableHTML
        backgroundRendering = background
        if background, worker == nil { worker = injectedWorker ?? StreamMarkdownParserWorker() }
        if renderSession == nil { renderSession = StreamMarkdownRenderSession() }
        renderSession?.configure(plugins: plugins, enableHTML: enableHTML)
        if buffer.visibleText.isEmpty { renderSnapshot = nil }
        else { publish() }
    }

    private func invalidateRenderer(cancelFinish: Bool) {
        configurationEpoch &+= 1
        worker?.invalidate()
        // In-flight work retains its own owner until queue-confined reset/free.
        // Drop idle native source/cache storage on cancel or configuration reset.
        worker = nil
        renderSession?.reset()
        if cancelFinish { resolveFinish(false) }
    }

    private func publish() {
        let source = buffer.visibleText
        requestVersion &+= 1
        if backgroundRendering, renderSession?.isBackgroundEligible(source) == true {
            if worker == nil { worker = StreamMarkdownParserWorker() }
            guard let worker else { return }
            let version = requestVersion
            let epoch = configurationEpoch
            worker.submit(source: source, generation: generation, version: version, configuration: epoch) { [weak self] result in
                Task { @MainActor in self?.accept(result) }
            }
        } else {
            // An extension/configuration switch invalidates any in-flight pure AST.
            configurationEpoch &+= 1
            worker?.invalidate()
            worker = nil
            renderSnapshot = renderSession?.update(source)
            visibleText = source
            completeFinalPublication()
        }
    }

    private func accept(_ result: StreamMarkdownWorkerResult) {
        guard result.generation == generation, result.version == requestVersion,
              result.epoch.configuration == configurationEpoch,
              result.source.utf16.elementsEqual(buffer.visibleText.utf16),
              renderSession?.isBackgroundEligible(result.source) == true else { return }
        renderSnapshot = renderSession?.accept(result)
        visibleText = result.source
        completeFinalPublication()
    }

    private func completeFinalPublication() {
        if pendingFinishGeneration == generation,
           visibleText.utf16.elementsEqual(buffer.fullText.utf16) {
            completedGeneration = generation
            // Completed readers retain Markup, not a duplicate native session/source cache.
            worker = nil
            resolveFinish(true)
        }
    }

    private func resolveFinish(_ completed: Bool) {
        let continuation = pendingFinish
        pendingFinish = nil
        pendingFinishGeneration = nil
        continuation?.resume(returning: completed)
    }

    public func append(_ chunk: String) {
        let wait = buffer.append(chunk, nowMillis: Self.nowMillis())
        if let wait {
            // The deadline is anchored to the last publish. Reuse its timer
            // rather than cancelling and allocating a task for every chunk.
            guard pending == nil else { return }
            pending = Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(wait) * 1_000_000)
                guard !Task.isCancelled else { return }
                self.buffer.flush(nowMillis: Self.nowMillis())
                self.publish()
                self.pending = nil
            }
        } else {
            pending?.cancel()
            pending = nil
            publish()
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
        publish()
    }

    func finish(for generation: UInt64) {
        guard self.generation == generation else { return }
        finish()
    }

    func finishAndWait(for expectedGeneration: UInt64) async -> Bool {
        guard generation == expectedGeneration, completedGeneration != expectedGeneration,
              pendingFinish == nil, !Task.isCancelled else { return false }
        pending?.cancel()
        pending = nil
        buffer.finish(nowMillis: Self.nowMillis())
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                pendingFinish = continuation
                pendingFinishGeneration = expectedGeneration
                publish()
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancel(for: expectedGeneration) }
        }
    }

    public func setHTML(_ enabled: Bool) {
        enableHTML = enabled
        buffer.setHTML(enabled)
        rendererHTML = enabled
        invalidateRenderer(cancelFinish: false)
        renderSession?.setHTML(enabled)
        publish()
    }

    public func cancel() {
        pending?.cancel()
        pending = nil
        invalidateRenderer(cancelFinish: true)
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
