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
    /// Change this identifier when replacing `chunks` to clear the previous reply immediately.
    public let streamID: String?
    public let throttleMillis: Int64
    public let enableHTML: Bool
    public let codeBlockOptions: CodeBlockOptions
    public let codeBuilder: ((String, String?) -> AnyView)?
    public let onCodeCopy: ((String, String?) -> Void)?
    public let onTextLongPress: ((@escaping () -> Void) -> Void)?
    public let styleSheet: MarkdownStyleSheet
    public let plugins: ParserPluginRegistry?
    public let builderRegistry: BuilderRegistry?
    /// Enables native selection, as in `SmoothMarkdownView`.
    public let selectable: Bool
    public let enableCrossBlockSelection: Bool
    public let scrollable: Bool
    /// Shown until the first text is published; defaults to an empty view.
    public let loadingView: AnyView?
    /// Replaces the reader when the stream throws. `onError` is still called.
    public let errorBuilder: ((Error) -> AnyView)?

    @StateObject private var accumulator: StreamMarkdownAccumulator
    @State private var activeIdentity: StreamTaskIdentity? = nil
    @State private var streamError: Error? = nil

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
        onTextLongPress: ((@escaping () -> Void) -> Void)? = nil,
        onError: ((Error) -> Void)? = nil,
        onComplete: ((String) -> Void)? = nil,
        styleSheet: MarkdownStyleSheet = .default(),
        plugins: ParserPluginRegistry? = nil,
        builderRegistry: BuilderRegistry? = nil,
        selectable: Bool = false,
        enableCrossBlockSelection: Bool = true,
        scrollable: Bool = true,
        loadingView: AnyView? = nil,
        errorBuilder: ((Error) -> AnyView)? = nil
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
        self.onTextLongPress = onTextLongPress
        self.styleSheet = styleSheet
        self.plugins = plugins
        self.builderRegistry = builderRegistry
        self.selectable = selectable
        self.enableCrossBlockSelection = enableCrossBlockSelection
        self.scrollable = scrollable
        self.loadingView = loadingView
        self.errorBuilder = errorBuilder
        _accumulator = StateObject(wrappedValue: StreamMarkdownAccumulator(throttleMillis: throttleMillis, enableHTML: enableHTML))
    }

    public var body: some View {
        Group {
            if activeIdentity == taskIdentity, let streamError, let errorBuilder {
                errorBuilder(streamError)
            } else if activeIdentity != taskIdentity || accumulator.visibleText.isEmpty {
                loadingView ?? AnyView(EmptyView())
            } else {
                SmoothMarkdownView(markdown: accumulator.visibleText, onLinkTap: onLinkTap, onImageTap: onImageTap,
                                   onImageTapWithMetadata: onImageTapWithMetadata,
                                   imageBuilder: imageBuilder,
                                   enableHTML: enableHTML, codeBlockOptions: codeBlockOptions, codeBuilder: codeBuilder,
                                   onCodeCopy: onCodeCopy, onTextLongPress: onTextLongPress,
                                   styleSheet: styleSheet, plugins: plugins, builderRegistry: builderRegistry,
                                   enableCache: false,
                                   selectable: selectable, enableCrossBlockSelection: enableCrossBlockSelection,
                                   scrollable: scrollable)
            }
        }
        .task(id: taskIdentity) {
            guard !Task.isCancelled else { return }
            accumulator.reset(throttleMillis: throttleMillis, enableHTML: enableHTML)
            let generation = accumulator.generation
            streamError = nil
            activeIdentity = taskIdentity
            do {
                for try await chunk in chunks {
                    if Task.isCancelled { break }
                    accumulator.append(chunk, for: generation)
                }
                if !Task.isCancelled && accumulator.isCurrent(generation) {
                    accumulator.finish(for: generation)
                    onComplete?(accumulator.visibleText)
                }
            } catch is CancellationError {
                accumulator.cancel(for: generation)
            } catch {
                accumulator.cancel(for: generation)
                if !Task.isCancelled && accumulator.isCurrent(generation) {
                    streamError = error
                    onError?(error)
                }
            }
        }
        .onChange(of: enableHTML) { _, enabled in accumulator.setHTML(enabled) }
        .onDisappear { accumulator.cancel() }
    }

    private var taskIdentity: StreamTaskIdentity {
        StreamTaskIdentity(streamID: streamID, throttleMillis: throttleMillis)
    }
}

private struct StreamTaskIdentity: Hashable {
    let streamID: String?
    let throttleMillis: Int64
}
