import SwiftUI

/// Appends incoming chunks and renders the accumulated Markdown document.
public struct StreamMarkdownView<Chunks: AsyncSequence>: View where Chunks.Element == String {
    public let chunks: Chunks
    public let onLinkTap: ((URL) -> Void)?
    public let onImageTap: ((URL) -> Void)?
    public let onError: ((Error) -> Void)?
    public let streamID: String?
    public let throttleMillis: Int64

    @StateObject private var accumulator: StreamMarkdownAccumulator

    public init(
        chunks: Chunks,
        streamID: String? = nil,
        throttleMillis: Int64 = 50,
        onLinkTap: ((URL) -> Void)? = nil,
        onImageTap: ((URL) -> Void)? = nil,
        onError: ((Error) -> Void)? = nil
    ) {
        self.chunks = chunks
        self.streamID = streamID
        self.throttleMillis = throttleMillis
        self.onLinkTap = onLinkTap
        self.onImageTap = onImageTap
        self.onError = onError
        _accumulator = StateObject(wrappedValue: StreamMarkdownAccumulator(throttleMillis: throttleMillis))
    }

    public var body: some View {
        SmoothMarkdownView(markdown: accumulator.visibleText, onLinkTap: onLinkTap, onImageTap: onImageTap)
            .task(id: StreamTaskIdentity(streamID: streamID, throttleMillis: throttleMillis)) {
                accumulator.reset(throttleMillis: throttleMillis)
                do {
                    for try await chunk in chunks {
                        if Task.isCancelled { break }
                        accumulator.append(chunk)
                    }
                    if !Task.isCancelled { accumulator.finish() }
                } catch is CancellationError {
                    accumulator.cancel()
                } catch {
                    accumulator.cancel()
                    onError?(error)
                }
            }
            .onDisappear { accumulator.cancel() }
    }
}

private struct StreamTaskIdentity: Hashable {
    let streamID: String?
    let throttleMillis: Int64
}
