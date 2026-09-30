import SwiftUI

/// Rendering behavior. Visual values belong to MarkdownStyleSheet and its designTokens.
public struct MarkdownRenderOptions {
    public var enableHTML: Bool
    public var useEnhancedComponents: Bool
    public var enableCache: Bool
    public var scrollable: Bool
    public var codeBlockOptions: CodeBlockOptions?

    public init(enableHTML: Bool = false, useEnhancedComponents: Bool = false,
                enableCache: Bool = true, scrollable: Bool = true,
                codeBlockOptions: CodeBlockOptions? = nil) {
        self.enableHTML = enableHTML; self.useEnhancedComponents = useEnhancedComponents
        self.enableCache = enableCache; self.scrollable = scrollable
        self.codeBlockOptions = codeBlockOptions
    }
}

/// Selection mode is explicit rather than a combination of unrelated Boolean flags.
/// Native complete-document selection is available on iOS; other platforms use SwiftUI selection.
public struct MarkdownSelectionOptions {
    public enum Mode: Equatable, Sendable { case disabled, block, document }
    public var mode: Mode
    public var controller: SmoothSelectionController?
    public init(mode: Mode = .disabled, controller: SmoothSelectionController? = nil) {
        self.mode = mode; self.controller = controller
    }
}

/// One handler per event in the structured API. Image events retain the original source and metadata.
public struct MarkdownEvents {
    public var onLinkTap: ((URL) -> Void)?
    public var onImageTap: ((MarkdownImageEvent) -> Void)?
    public var onCodeCopy: ((String, String?) -> Void)?
    public var onTextLongPress: ((@escaping () -> Void) -> Void)?
    public var onError: ((Error) -> Void)?
    public var onComplete: ((String) -> Void)?
    public init(onLinkTap: ((URL) -> Void)? = nil,
                onImageTap: ((MarkdownImageEvent) -> Void)? = nil,
                onCodeCopy: ((String, String?) -> Void)? = nil,
                onTextLongPress: ((@escaping () -> Void) -> Void)? = nil,
                onError: ((Error) -> Void)? = nil, onComplete: ((String) -> Void)? = nil) {
        self.onLinkTap = onLinkTap; self.onImageTap = onImageTap
        self.onCodeCopy = onCodeCopy; self.onTextLongPress = onTextLongPress
        self.onError = onError; self.onComplete = onComplete
    }
}

public extension SmoothMarkdownView {
    /// Structured entry point. Existing flat initializers remain source compatible.
    init(markdown: String, renderOptions: MarkdownRenderOptions,
         selectionOptions: MarkdownSelectionOptions = .init(), events: MarkdownEvents = .init(),
         styleSheet: MarkdownStyleSheet = .default(), plugins: ParserPluginRegistry? = nil,
         builders: MarkdownBuilders = .init(), resourceOptions: MarkdownResourceOptions? = nil,
         strings: MarkdownStrings? = nil) {
        self.init(markdown: markdown, onLinkTap: events.onLinkTap,
                  onImageTapWithMetadata: events.onImageTap.map { handler in { source, alt, title in handler(.init(source: source, alt: alt, title: title)) } }, imageBuilder: builders.image,
                  enableHTML: renderOptions.enableHTML, useEnhancedComponents: renderOptions.useEnhancedComponents,
                  codeBlockOptions: renderOptions.codeBlockOptions, codeBuilder: builders.code,
                  onCodeCopy: events.onCodeCopy, onTextLongPress: events.onTextLongPress,
                  styleSheet: styleSheet, plugins: plugins, builderRegistry: builders.nodes,
                  enableCache: renderOptions.enableCache, selectable: selectionOptions.mode != .disabled,
                  selectionController: selectionOptions.controller,
                  enableCrossBlockSelection: selectionOptions.mode == .document,
                  scrollable: renderOptions.scrollable, resourceOptions: resourceOptions, strings: strings)
    }
}

public extension StreamMarkdownView {
    /// Streaming counterpart of the structured reader API. Live documents always bypass parse caching.
    init(chunks: Chunks, renderOptions: MarkdownRenderOptions,
         selectionOptions: MarkdownSelectionOptions = .init(), events: MarkdownEvents = .init(),
         streamOptions: MarkdownStreamOptions = .init(), streamID: String? = nil,
         styleSheet: MarkdownStyleSheet = .default(), plugins: ParserPluginRegistry? = nil,
         builders: MarkdownBuilders = .init(), resourceOptions: MarkdownResourceOptions? = nil,
         strings: MarkdownStrings? = nil) {
        self.init(chunks: chunks, streamID: streamID, throttleMillis: max(0, streamOptions.throttleMillis),
                  enableHTML: renderOptions.enableHTML, useEnhancedComponents: renderOptions.useEnhancedComponents,
                  onLinkTap: events.onLinkTap,
                  onImageTapWithMetadata: events.onImageTap.map { handler in { source, alt, title in handler(.init(source: source, alt: alt, title: title)) } },
                  imageBuilder: builders.image, codeBlockOptions: renderOptions.codeBlockOptions,
                  codeBuilder: builders.code, onCodeCopy: events.onCodeCopy,
                  onTextLongPress: events.onTextLongPress, onError: events.onError, onComplete: events.onComplete,
                  styleSheet: styleSheet, plugins: plugins, builderRegistry: builders.nodes,
                  selectable: selectionOptions.mode != .disabled, selectionController: selectionOptions.controller,
                  enableCrossBlockSelection: selectionOptions.mode == .document, scrollable: renderOptions.scrollable,
                  loadingView: streamOptions.loadingContent, errorBuilder: streamOptions.errorContent,
                  resourceOptions: resourceOptions, strings: strings)
    }
}

/// Original image source and metadata, shared by standard and selectable readers.
public struct MarkdownImageEvent: Equatable, Sendable {
    public let source: String
    public let alt: String?
    public let title: String?
    public init(source: String, alt: String? = nil, title: String? = nil) {
        self.source = source; self.alt = alt; self.title = title
    }
}

/// Custom node/code/image renderers, separate from behavior and visual configuration.
public struct MarkdownBuilders {
    public var nodes: BuilderRegistry?
    public var code: ((String, String?) -> AnyView)?
    public var image: ((String, String?, String?) -> AnyView)?
    public init(nodes: BuilderRegistry? = nil, code: ((String, String?) -> AnyView)? = nil,
                image: ((String, String?, String?) -> AnyView)? = nil) {
        self.nodes = nodes; self.code = code; self.image = image
    }
}

/// Stream scheduling and presentation. Completion/error events belong to MarkdownEvents.
public struct MarkdownStreamOptions {
    public var throttleMillis: Int64
    public var loadingContent: AnyView?
    public var errorContent: ((Error) -> AnyView)?
    public init(throttleMillis: Int64 = 50, loadingContent: AnyView? = nil,
                errorContent: ((Error) -> AnyView)? = nil) {
        self.throttleMillis = max(0, throttleMillis)
        self.loadingContent = loadingContent; self.errorContent = errorContent
    }
}
