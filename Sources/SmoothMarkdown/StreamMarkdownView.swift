import SwiftUI

/// Appends incoming chunks and renders the accumulated Markdown document.
public struct StreamMarkdownView<Chunks: AsyncSequence>: View where Chunks.Element == String {
    public let chunks: Chunks
    public let onLinkTap: ((URL) -> Void)?
    public let onImageTap: ((URL) -> Void)?
    public let onImageTapWithMetadata: ((String, String?, String?) -> Void)?
    public let imageBuilder: ((String, String?, String?) -> AnyView)?
    public let onError: ((Error) -> Void)?
    /// Called after the final chunk has been published to the reader.
    public let onComplete: ((String) -> Void)?
    public let streamID: String?
    public let throttleMillis: Int64
    public let enableHTML: Bool
    public let codeBlockOptions: CodeBlockOptions
    public let codeBuilder: ((String, String?) -> AnyView)?
    public let onCodeCopy: ((String, String?) -> Void)?
    public let styleSheet: MarkdownStyleSheet
    public let plugins: ParserPluginRegistry?

    @StateObject private var accumulator: StreamMarkdownAccumulator

    public init(
        chunks: Chunks,
        streamID: String? = nil,
        throttleMillis: Int64 = 50,
        enableHTML: Bool = false,
        onLinkTap: ((URL) -> Void)? = nil,
        onImageTap: ((URL) -> Void)? = nil,
        onImageTapWithMetadata: ((String, String?, String?) -> Void)? = nil,
        imageBuilder: ((String, String?, String?) -> AnyView)? = nil,
        codeBlockOptions: CodeBlockOptions = CodeBlockOptions(),
        codeBuilder: ((String, String?) -> AnyView)? = nil,
        onCodeCopy: ((String, String?) -> Void)? = nil,
        onError: ((Error) -> Void)? = nil,
        onComplete: ((String) -> Void)? = nil,
        styleSheet: MarkdownStyleSheet = .default(),
        plugins: ParserPluginRegistry? = nil
    ) {
        self.chunks = chunks
        self.streamID = streamID
        self.throttleMillis = throttleMillis
        self.enableHTML = enableHTML
        self.onLinkTap = onLinkTap
        self.onImageTap = onImageTap
        self.onImageTapWithMetadata = onImageTapWithMetadata
        self.imageBuilder = imageBuilder
        self.onError = onError
        self.onComplete = onComplete
        self.codeBlockOptions = codeBlockOptions
        self.codeBuilder = codeBuilder
        self.onCodeCopy = onCodeCopy
        self.styleSheet = styleSheet
        self.plugins = plugins
        _accumulator = StateObject(wrappedValue: StreamMarkdownAccumulator(throttleMillis: throttleMillis, enableHTML: enableHTML))
    }

    public var body: some View {
        SmoothMarkdownView(markdown: accumulator.visibleText, onLinkTap: onLinkTap, onImageTap: onImageTap,
                           onImageTapWithMetadata: onImageTapWithMetadata,
                           imageBuilder: imageBuilder,
                           enableHTML: enableHTML, codeBlockOptions: codeBlockOptions, codeBuilder: codeBuilder,
                           onCodeCopy: onCodeCopy, styleSheet: styleSheet, plugins: plugins)
            .task(id: StreamTaskIdentity(streamID: streamID, throttleMillis: throttleMillis)) {
                accumulator.reset(throttleMillis: throttleMillis, enableHTML: enableHTML)
                do {
                    for try await chunk in chunks {
                        if Task.isCancelled { break }
                        accumulator.append(chunk)
                    }
                    if !Task.isCancelled {
                        accumulator.finish()
                        onComplete?(accumulator.visibleText)
                    }
                } catch is CancellationError {
                    accumulator.cancel()
                } catch {
                    accumulator.cancel()
                    onError?(error)
                }
            }
            .onChange(of: enableHTML) { _, enabled in accumulator.setHTML(enabled) }
            .onDisappear { accumulator.cancel() }
    }
}

private struct StreamTaskIdentity: Hashable {
    let streamID: String?
    let throttleMillis: Int64
}
