import SwiftUI

/// Appends incoming chunks and renders the accumulated Markdown document.
public struct StreamMarkdownView<Chunks: AsyncSequence>: View where Chunks.Element == String {
    @Environment(\.markdownResources) private var inheritedResources
    @Environment(\.markdownStrings) private var inheritedStrings
    private let configuredResources: MarkdownResourceOptions?
    private let configuredStrings: MarkdownStrings?
    /// Effective values inherit the host environment unless an explicit override was supplied.
    public var resourceOptions: MarkdownResourceOptions { configuredResources ?? inheritedResources }
    public var strings: MarkdownStrings { configuredStrings ?? inheritedStrings }
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
    public let useEnhancedComponents: Bool
    public let codeBlockOptions: CodeBlockOptions
    public let codeBuilder: ((String, String?) -> AnyView)?
    public let onCodeCopy: ((String, String?) -> Void)?
    public let onTextLongPress: ((@escaping () -> Void) -> Void)?
    public let styleSheet: MarkdownStyleSheet
    public let plugins: ParserPluginRegistry?
    public let builderRegistry: BuilderRegistry?
    /// Enables native selection, as in `SmoothMarkdownView`.
    public let selectable: Bool
    public let selectionController: SmoothSelectionController?
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
        useEnhancedComponents: Bool = false,
        onLinkTap: ((URL) -> Void)? = nil,
        /// Flutter-style link callback. Receives the link as a string; both callbacks run when supplied.
        onTapLink: ((String) -> Void)? = nil,
        onImageTap: ((URL) -> Void)? = nil,
        onImageTapWithMetadata: ((String, String?, String?) -> Void)? = nil,
        /// Flutter-style image callback. Receives the original source, alt text, and title.
        onTapImage: ((String, String?, String?) -> Void)? = nil,
        imageBuilder: ((String, String?, String?) -> AnyView)? = nil,
        codeBlockOptions: CodeBlockOptions? = nil,
        codeBuilder: ((String, String?) -> AnyView)? = nil,
        onCodeCopy: ((String, String?) -> Void)? = nil,
        onTextLongPress: ((@escaping () -> Void) -> Void)? = nil,
        onError: ((Error) -> Void)? = nil,
        onComplete: ((String) -> Void)? = nil,
        styleSheet: MarkdownStyleSheet = .default(),
        plugins: ParserPluginRegistry? = nil,
        builderRegistry: BuilderRegistry? = nil,
        selectable: Bool = false,
        selectionController: SmoothSelectionController? = nil,
        enableCrossBlockSelection: Bool = true,
        scrollable: Bool = true,
        loadingView: AnyView? = nil,
        errorBuilder: ((Error) -> AnyView)? = nil,
        resourceOptions: MarkdownResourceOptions? = nil,
        strings: MarkdownStrings? = nil
    ) {
        self.configuredResources = resourceOptions
        self.configuredStrings = strings
        self.chunks = chunks
        self.streamID = streamID
        self.throttleMillis = throttleMillis
        self.enableHTML = enableHTML
        self.useEnhancedComponents = useEnhancedComponents
        self.onLinkTap = onLinkTap == nil && onTapLink == nil ? nil : { url in
            onLinkTap?(url)
            onTapLink?(url.absoluteString)
        }
        self.onImageTap = onImageTap
        self.onImageTapWithMetadata = onImageTapWithMetadata == nil && onTapImage == nil ? nil : { source, alt, title in
            onImageTapWithMetadata?(source, alt, title)
            onTapImage?(source, alt, title)
        }
        self.imageBuilder = imageBuilder
        self.onError = onError
        self.onComplete = onComplete
        self.codeBlockOptions = codeBlockOptions ?? CodeBlockOptions(showCopyButton: useEnhancedComponents, showLanguageTag: useEnhancedComponents, enableSyntaxHighlighting: useEnhancedComponents)
        self.codeBuilder = codeBuilder
        self.onCodeCopy = onCodeCopy
        self.onTextLongPress = onTextLongPress
        self.styleSheet = styleSheet
        self.plugins = plugins
        self.builderRegistry = builderRegistry
        self.selectable = selectable
        self.selectionController = selectionController
        self.enableCrossBlockSelection = enableCrossBlockSelection
        self.scrollable = scrollable
        self.loadingView = loadingView
        self.errorBuilder = errorBuilder
        _accumulator = StateObject(wrappedValue: StreamMarkdownAccumulator(throttleMillis: throttleMillis, enableHTML: enableHTML))
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if activeIdentity == taskIdentity, let streamError, let errorBuilder {
                errorBuilder(streamError)
            } else if activeIdentity != taskIdentity || accumulator.visibleText.isEmpty {
                loadingView ?? AnyView(EmptyView())
            } else {
                SmoothMarkdownView(markdown: accumulator.visibleText, onLinkTap: onLinkTap, onImageTap: onImageTap,
                                   onImageTapWithMetadata: onImageTapWithMetadata,
                                   imageBuilder: imageBuilder,
                                   enableHTML: enableHTML, useEnhancedComponents: useEnhancedComponents,
                                   codeBlockOptions: codeBlockOptions, codeBuilder: codeBuilder,
                                   onCodeCopy: onCodeCopy, onTextLongPress: onTextLongPress,
                                   styleSheet: styleSheet, plugins: plugins, builderRegistry: builderRegistry,
                                   enableCache: false,
                                   selectable: selectable,
                                   selectionController: selectionController,
                                   enableCrossBlockSelection: enableCrossBlockSelection,
                                   scrollable: scrollable, resourceOptions: resourceOptions, strings: strings)
            }
        }
        .environment(\.markdownStreamSnapshot, accumulator.renderSnapshot)
        .environment(\.markdownResources, resourceOptions)
        .environment(\.markdownStrings, strings)
        .task(id: taskIdentity) {
            guard !Task.isCancelled else { return }
            accumulator.reset(throttleMillis: throttleMillis, enableHTML: enableHTML)
            accumulator.prepareRenderer(plugins: plugins, enableHTML: enableHTML, background: true)
            let generation = accumulator.generation
            streamError = nil
            activeIdentity = taskIdentity
            do {
                for try await chunk in chunks {
                    if Task.isCancelled { break }
                    accumulator.append(chunk, for: generation)
                }
                if !Task.isCancelled && accumulator.isCurrent(generation) {
                    let published = await accumulator.finishAndWait(for: generation)
                    if published && !Task.isCancelled && accumulator.isCurrent(generation) {
                        onComplete?(accumulator.visibleText)
                    }
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
        .onChange(of: plugins.map(ObjectIdentifier.init)) { _, _ in
            accumulator.prepareRenderer(plugins: plugins, enableHTML: enableHTML, background: true)
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
