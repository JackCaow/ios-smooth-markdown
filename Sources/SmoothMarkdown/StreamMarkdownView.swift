import SwiftUI

/// Appends incoming chunks and renders the accumulated Markdown document.
public struct StreamMarkdownView<Chunks: AsyncSequence>: View where Chunks.Element == String {
    public let chunks: Chunks
    public let onLinkTap: ((URL) -> Void)?
    public let onImageTap: ((URL) -> Void)?
    public let onError: ((Error) -> Void)?
    public let streamID: String?
    public let throttleMillis: Int64
    public let enableHTML: Bool
    public let codeBlockOptions: CodeBlockOptions
    public let onCodeCopy: ((String, String?) -> Void)?
    public let styleSheet: MarkdownStyleSheet

    @StateObject private var accumulator: StreamMarkdownAccumulator

    public init(
        chunks: Chunks,
        streamID: String? = nil,
        throttleMillis: Int64 = 50,
        enableHTML: Bool = false,
        onLinkTap: ((URL) -> Void)? = nil,
        onImageTap: ((URL) -> Void)? = nil,
        codeBlockOptions: CodeBlockOptions = CodeBlockOptions(),
        onCodeCopy: ((String, String?) -> Void)? = nil,
        onError: ((Error) -> Void)? = nil,
        styleSheet: MarkdownStyleSheet = .default()
    ) {
        self.chunks = chunks
        self.streamID = streamID
        self.throttleMillis = throttleMillis
        self.enableHTML = enableHTML
        self.onLinkTap = onLinkTap
        self.onImageTap = onImageTap
        self.onError = onError
        self.codeBlockOptions = codeBlockOptions
        self.onCodeCopy = onCodeCopy
        self.styleSheet = styleSheet
        _accumulator = StateObject(wrappedValue: StreamMarkdownAccumulator(throttleMillis: throttleMillis, enableHTML: enableHTML))
    }

    public var body: some View {
        SmoothMarkdownView(markdown: accumulator.visibleText, onLinkTap: onLinkTap, onImageTap: onImageTap,
                           enableHTML: enableHTML, codeBlockOptions: codeBlockOptions,
                           onCodeCopy: onCodeCopy, styleSheet: styleSheet)
            .task(id: StreamTaskIdentity(streamID: streamID, throttleMillis: throttleMillis, enableHTML: enableHTML)) {
                accumulator.reset(throttleMillis: throttleMillis, enableHTML: enableHTML)
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
    let enableHTML: Bool
}
