import Markdown
import SwiftDraw
import SwiftUI
#if os(iOS)
import UIKit
#endif

enum MarkdownEnhancedComponents {
    static func usesBuiltInAICard(for pluginID: String, enabled: Bool) -> Bool {
        enabled || !["thinking", "artifact", "tool_call"].contains(pluginID)
    }

    static func isExternalLink(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "https" || scheme == "http"
    }
}

/// Renders the currently supported CommonMark and GFM blocks with SwiftUI.
public struct SmoothMarkdownView: View {
    /// Statistics for the document parse cache used by reader views.
    public static var cacheStatistics: MarkdownCacheStatistics { MarkdownParseCache.shared.statistics }

    /// Drops parsed documents so subsequent renders parse their source again.
    public static func clearCache() { MarkdownParseCache.shared.clear() }

    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    #if os(iOS)
    @Environment(\.readerTextSelectionMenuBuilder) private var textSelectionMenuBuilder
    #endif
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var inlineFontScale: CGFloat = 1
    public let markdown: String
    public let onLinkTap: ((URL) -> Void)?
    public let onImageTap: ((URL) -> Void)?
    /// Receives the original image source, alt text, and title, matching Flutter's image callback.
    public let onImageTapWithMetadata: ((String, String?, String?) -> Void)?
    /// Replaces the content of a safe image while retaining native tap and accessibility handling.
    public let imageBuilder: ((String, String?, String?) -> AnyView)?
    public let enableHTML: Bool
    /// Flutter-compatible visual variants for code, headings, blockquotes, and links.
    /// Standard components are used unless this is explicitly enabled.
    public let useEnhancedComponents: Bool
    public let codeBlockOptions: CodeBlockOptions
    public let codeBuilder: ((String, String?) -> AnyView)?
    public let onCodeCopy: ((String, String?) -> Void)?
    /// When provided, intercepts a rendered-text long press and supplies an action that
    /// selects the paragraph under the press in the native text view.
    public let onTextLongPress: ((@escaping () -> Void) -> Void)?
    public let styleSheet: MarkdownStyleSheet
    public let plugins: ParserPluginRegistry?
    /// Overrides parsed block/inline nodes and parser-plugin results by type or `canBuild`.
    public let builderRegistry: BuilderRegistry?
    /// Reuses parsed documents for repeated source when no parser plugins are installed.
    /// Disable for rapidly changing content such as a live stream.
    public let enableCache: Bool
    /// Enables native text selection in the reader. Defaults to false, like Flutter.
    public let selectable: Bool
    /// Programmatic selection for a complete native TextKit reader host.
    public let selectionController: SmoothSelectionController?
    public let enableCrossBlockSelection: Bool
    /// Set to false when a host scroll view owns vertical scrolling, such as a chat list.
    public let scrollable: Bool

    public init(
        markdown: String,
        onLinkTap: ((URL) -> Void)? = nil,
        /// Flutter-style link callback. Receives the link as a string; both callbacks run when supplied.
        onTapLink: ((String) -> Void)? = nil,
        onImageTap: ((URL) -> Void)? = nil,
        onImageTapWithMetadata: ((String, String?, String?) -> Void)? = nil,
        /// Flutter-style image callback. Receives the original source, alt text, and title.
        onTapImage: ((String, String?, String?) -> Void)? = nil,
        imageBuilder: ((String, String?, String?) -> AnyView)? = nil,
        enableHTML: Bool = false,
        useEnhancedComponents: Bool = false,
        codeBlockOptions: CodeBlockOptions = CodeBlockOptions(),
        codeBuilder: ((String, String?) -> AnyView)? = nil,
        onCodeCopy: ((String, String?) -> Void)? = nil,
        onTextLongPress: ((@escaping () -> Void) -> Void)? = nil,
        styleSheet: MarkdownStyleSheet = .default(),
        plugins: ParserPluginRegistry? = nil,
        builderRegistry: BuilderRegistry? = nil,
        enableCache: Bool = true,
        selectable: Bool = false,
        selectionController: SmoothSelectionController? = nil,
        enableCrossBlockSelection: Bool = true,
        scrollable: Bool = true
    ) {
        self.markdown = markdown
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
        self.enableHTML = enableHTML
        self.useEnhancedComponents = useEnhancedComponents
        self.codeBlockOptions = codeBlockOptions
        self.codeBuilder = codeBuilder
        self.onCodeCopy = onCodeCopy
        self.onTextLongPress = onTextLongPress
        self.styleSheet = styleSheet
        self.plugins = plugins
        self.builderRegistry = builderRegistry
        self.enableCache = enableCache
        self.selectable = selectable
        self.selectionController = selectionController
        self.enableCrossBlockSelection = enableCrossBlockSelection
        self.scrollable = scrollable
    }

    public var body: some View {
        Group {
            if scrollable {
                ScrollView { renderedBlocks }
            } else {
                renderedBlocks
            }
        }
        .foregroundColor(styleSheet.textColor)
        .background(styleSheet.backgroundColor ?? Color.clear)
        .environment(\.openURL, OpenURLAction { url in
            guard MarkdownSyntax.isSafeLink(url) else { return .discarded }
            if let onLinkTap {
                onLinkTap(url)
                return .handled
            }
            return .systemAction
        })
    }

    @ViewBuilder
    private var renderedBlocks: some View {
        #if os(iOS)
        if let unified = wholeDocumentSelection {
            ReaderWholeDocumentSelectionContainer(selectionDocument: unified.selection,
                                                  projection: unified.projection,
                                                  styleSheet: styleSheet, onLinkTap: onLinkTap,
                                                  sourceView: self,
                                                  selectionController: selectionController)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(styleSheet.contentPadding)
        } else {
            legacyRenderedBlocks
        }
        #else
        legacyRenderedBlocks
        #endif
    }

    private var legacyRenderedBlocks: some View {
        LazyVStack(alignment: .leading, spacing: styleSheet.blockSpacing) {
            ForEach(Array(DetailsSyntax.sections(markdown).enumerated()), id: \.offset) { _, section in
                detailsSection(section)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(styleSheet.contentPadding)
    }

    #if os(iOS)
    /// One native selection surface includes built-in visual blocks when every
    /// attachment has a measured host and a semantic Copy value.
    var wholeDocumentSelection: (selection: ReaderSelectionDocument,
                                 projection: ReaderTextKitProjection)? {
        wholeDocumentSelection(expansion: [:])
    }

    func wholeDocumentSelection(expansion: [String: Bool]) ->
        (selection: ReaderSelectionDocument, projection: ReaderTextKitProjection)? {
        wholeDocumentSelection(expansion: expansion, validateExpandedDetails: true)
    }

    private func wholeDocumentSelection(expansion: [String: Bool], validateExpandedDetails: Bool) ->
        (selection: ReaderSelectionDocument, projection: ReaderTextKitProjection)? {
        guard selectable, enableCrossBlockSelection, onTextLongPress == nil, !voiceOverEnabled else { return nil }
        let projection = ReaderTextKitProjection(document: ReaderVisibleDocumentProjection(
            markdown: markdown, enableHTML: enableHTML, plugins: plugins,
            builderRegistry: builderRegistry, expansion: expansion,
            hostBuiltInPlugins: true, hostBuiltInArtifacts: useEnhancedComponents))
        let details = DetailsSyntax.sections(markdown)
        let summaryIDs = projection.document.segments.filter { $0.kind == .detailsSummary }.map(\.id)
        var summaryIndex = 0
        var items: [ReaderBlockRangeDocument.Item] = []
        func appendMath(_ source: String) {
            for section in MathSyntax.sections(source) {
                switch section {
                case let .markdown(markdown):
                    items += Array(parse(markdown).children).map(ReaderBlockRangeDocument.Item.markup)
                case let .block(latex): items.append(.displayMath(latex))
                }
            }
        }
        func appendFootnotes(_ source: String) -> Bool {
            for section in FootnoteSyntax.sections(source) {
                switch section {
                case let .markdown(markdown): appendMath(markdown)
                case let .definition(definition):
                    let node = MarkdownExtensionNode.footnoteDefinition(label: definition.label,
                                                                         content: definition.content)
                    let parsed = parse(definition.content)
                    if extensionBuilder(node) != nil || !(parsed.child(at: 0) is Paragraph) { return false }
                    items.append(.footnoteDefinition(definition))
                }
            }
            return true
        }
        func appendPlugins(_ source: String) -> Bool {
            for section in PluginBlockSyntax.sections(source, registry: plugins) {
                switch section {
                case let .markdown(markdown):
                    if !appendFootnotes(markdown) { return false }
                case let .plugin(plugin, match):
                    guard plugin is AdmonitionPlugin || plugin is MermaidPlugin ||
                          (useEnhancedComponents && plugin is ArtifactPlugin),
                          builderRegistry?.findBuilder(MarkdownPluginNode(plugin: plugin, match: match)) == nil
                    else { return false }
                    items.append(.plugin(match))
                }
            }
            return true
        }
        func isCustom(_ item: ReaderBlockRangeDocument.Item) -> Bool {
            switch item {
            case let .markup(node):
                return containsCustomBlockBuilder(node) || (node is CodeBlock && codeBuilder != nil)
            case let .displayMath(latex): return extensionBuilder(.blockMath(latex)) != nil
            case let .detailsSummary(block):
                guard let summary = parse(block.summary).child(at: 0) else { return false }
                return containsCustomBlockBuilder(summary)
            case let .footnoteDefinition(definition):
                guard let content = parse(definition.content).child(at: 0) else { return false }
                return containsCustomBlockBuilder(content)
            case .plugin: return false
            }
        }
        for section in details {
            switch section {
            case let .markdown(source):
                guard appendPlugins(source) else { return nil }
            case let .details(block):
                let node = MarkdownExtensionNode.details(summary: block.summary,
                                                         content: block.content, isOpen: block.isOpen)
                guard extensionBuilder(node) == nil,
                      summaryIDs.indices.contains(summaryIndex) else { return nil }
                let id = summaryIDs[summaryIndex]
                summaryIndex += 1
                items.append(.detailsSummary(block))
                let bodyStart = items.count
                guard appendPlugins(block.content) else { return nil }
                let body = Array(items[bodyStart...])
                guard !body.contains(where: isCustom),
                      body.isEmpty || ReaderSelectionDocument.composeItems(
                        body, enableHTML: enableHTML, plugins: plugins,
                        visualBlockAnchors: true) != nil else { return nil }
                if !(expansion[id] ?? block.isOpen) {
                    items.removeSubrange(bodyStart..<items.count)
                }
            }
        }
        guard summaryIndex == summaryIDs.count else { return nil }
        // Single blocks keep their existing renderer unless the caller needs
        // a native host for programmatic selection or disclosure.
        guard !items.isEmpty, (items.count > 1 || selectionController != nil || !summaryIDs.isEmpty),
              !items.contains(where: isCustom),
              let selection = ReaderSelectionDocument.composeItems(items, enableHTML: enableHTML,
                                                                     plugins: plugins,
                                                                     visualBlockAnchors: true) else { return nil }
        let remoteImageCount = projection.attachments.filter { attachment in
            guard case let .image(spec) = attachment.content,
                  let source = ImageSource.parse(spec.source), case .remote = source else { return false }
            return true
        }.count
        guard projection.attachments.allSatisfy({ attachment in
            switch attachment.content {
            case .image, .code, .table, .formula, .plugin: true
            default: false
            }
        }),
              !(imageBuilder != nil && projection.attachments.contains(where: {
                  if case .image = $0.content { return true }
                  return false
              })),
              remoteImageCount <= ReaderRemoteImagePolicy.maxRemoteImages,
              projection.attributedText.string == selection.selectionText else { return nil }
        let styled = ReaderSelectionTextView(document: selection, styleSheet: styleSheet,
                                             onLinkTap: onLinkTap, onTextLongPress: nil,
                                             selectable: true, onCharacterTap: nil,
                                             useEnhancedComponents: useEnhancedComponents)
            .attributedContent(traits: MarkdownTypography.traits(for: dynamicTypeSize)).text
        guard styled.string == projection.attributedText.string else { return nil }
        if validateExpandedDetails, !summaryIDs.isEmpty {
            var allOpen = expansion
            for id in summaryIDs { allOpen[id] = true }
            if allOpen != expansion,
               wholeDocumentSelection(expansion: allOpen, validateExpandedDetails: false) == nil {
                return nil
            }
        }
        return (selection, projection)
    }

    func visualAttachmentView(for content: ReaderTextKitProjection.Attachment.Content,
                              remoteResolution: ReaderRemoteImageResolution? = nil,
                              inlineFormula: Bool = false) -> AnyView? {
        switch content {
        case let .image(image):
            if let source = ImageSource.parse(image.source), case .remote = source {
                return resolvedRemoteImageView(image, resolution: remoteResolution)
            }
            return imageView(image)
        case let .code(code, language):
            if useEnhancedComponents {
                return AnyView(EnhancedCodeBlockView(code: code, language: language,
                                                     options: codeBlockOptions, onCopy: onCodeCopy,
                                                     styleSheet: styleSheet, selectable: false,
                                                     onSelectSurroundingContent: nil))
            }
            return AnyView(StandardCodeBlockView(code: code, language: language,
                                                 styleSheet: styleSheet, selectable: false,
                                                 onCopy: onCodeCopy))
        case let .table(source):
            guard let table = parse(source).child(at: 0) as? Markdown.Table else { return nil }
            return AnyView(tableView(table, selectable: false))
        case let .formula(latex):
            if inlineFormula { return AnyView(inlineMath(latex)) }
            return AnyView(blockMath(latex))
        case let .plugin(id, match):
            guard let plugin = plugins?.blockPlugins.first(where: { $0.id == id }),
                  plugin is AdmonitionPlugin || plugin is MermaidPlugin ||
                  (useEnhancedComponents && plugin is ArtifactPlugin),
                  builderRegistry?.findBuilder(MarkdownPluginNode(plugin: plugin, match: match)) == nil
            else { return nil }
            return pluginView(plugin, match)
        default: return nil
        }
    }
    #endif

    var usesParseCache: Bool { enableCache && plugins == nil }

    private func parse(_ source: String) -> Document {
        // Plugin registries may change behavior without changing the source key.
        MarkdownSyntax.parse(source, useCache: usesParseCache, enableHTML: enableHTML)
    }

    private func block(_ node: Markup, alignment: TextAlignment? = nil,
                       onSelectSurroundingContent: (() -> Void)? = nil) -> AnyView {
        AnyView(blockContent(node, alignment: alignment,
                             onSelectSurroundingContent: onSelectSurroundingContent))
    }

    private func hasCustomBuilder(_ node: Markup) -> Bool {
        // InlineHTML nodes are stateful open/close tokens in InlineContent;
        // consuming one would corrupt styling of subsequent siblings.
        if node is InlineHTML { return false }
        return builderRegistry?.findBuilder(node) != nil
    }

    private func extensionBuilder(_ node: MarkdownExtensionNode) -> (any MarkdownWidgetBuilder)? {
        builderRegistry?.findBuilder(node)
    }

    private func htmlStyleNode(_ text: String, tags: [SafeHTML.Tag]) -> MarkdownExtensionNode? {
        guard enableHTML, builderRegistry != nil else { return nil }
        // An HTML opener/closer alone has no renderable content. Prefer the
        // innermost accepted style around the actual text run.
        for tag in tags.reversed() {
            let type: String? = switch tag.name {
            case "b", "strong": "bold"
            case "i", "em": "italic"
            case "s", "del", "strike": "strikethrough"
            case "u", "ins": "underline"
            case "mark": "highlight"
            case "sub": "subscript"
            case "sup": "superscript"
            case "kbd": "kbd"
            case "span", "font": "styled_span"
            default: nil
            }
            guard let type else { continue }
            let node = MarkdownExtensionNode.htmlStyle(type: type, tag: tag.name, text: text,
                                                       attributes: tag.attributes)
            if extensionBuilder(node) != nil { return node }
        }
        return nil
    }

    private func hasCustomExtension(in node: Markup) -> Bool {
        InlineContent.runs(in: node, enableHTML: enableHTML, plugins: plugins).contains { run in
            switch run {
            case let .math(latex): return extensionBuilder(.inlineMath(latex)) != nil
            case let .footnote(label): return extensionBuilder(.footnoteReference(label)) != nil
            case let .text(value, _, tags, _): return htmlStyleNode(value, tags: tags) != nil
            case let .plugin(plugin, match):
                return builderRegistry?.findBuilder(MarkdownPluginNode(plugin: plugin, match: match)) != nil
            default: return false
            }
        }
    }

    func containsCustomBlockBuilder(_ node: Markup) -> Bool {
        guard builderRegistry != nil else { return false }
        if hasCustomBuilder(node) { return true }
        if node is Paragraph || node is Heading || node is Markdown.Table.Cell {
            // Match the same post-plugin text pieces that inlineView will dispatch.
            // The raw swift-markdown Text node may contain a plugin token that
            // becomes a separate result before builders see ordinary text.
            return hasCustomExtension(in: node) || InlineContent.runs(in: node, enableHTML: enableHTML, plugins: plugins,
                                      hasCustomBuilder: hasCustomBuilder).contains {
                if case .custom = $0 { return true }
                return false
            }
        }
        // Image alt text and raw inline code are data inside one native element,
        // not independently dispatched child nodes.
        if node is Markdown.Image || node is InlineCode || node is InlineHTML { return false }
        return node.children.contains(where: containsCustomBlockBuilder)
    }

    private func renderContext(alignment: TextAlignment? = nil,
                               inlineStyle: InlineContent.Style? = nil) -> MarkdownRenderContext {
        MarkdownRenderContext(
            styleSheet: styleSheet, selectable: selectable,
            renderBlock: { child in block(child, alignment: alignment) },
            renderInline: { child in inlineView(child) },
            renderMarkdown: { source in
                AnyView(SmoothMarkdownView(markdown: source, onLinkTap: onLinkTap,
                                           onImageTap: onImageTap,
                                           onImageTapWithMetadata: onImageTapWithMetadata,
                                           imageBuilder: imageBuilder, enableHTML: enableHTML,
                                           useEnhancedComponents: useEnhancedComponents,
                                           codeBlockOptions: codeBlockOptions, codeBuilder: codeBuilder,
                                           onCodeCopy: onCodeCopy, onTextLongPress: onTextLongPress,
                                           styleSheet: styleSheet, plugins: plugins,
                                           builderRegistry: builderRegistry, enableCache: enableCache,
                                           selectable: selectable,
                                           enableCrossBlockSelection: enableCrossBlockSelection,
                                           scrollable: false))
            },
            inlineStyle: inlineStyle.map {
                MarkdownInlineStyle(bold: $0.bold, italic: $0.italic,
                                    strike: $0.strike, link: $0.link)
            }
        )
    }

    @ViewBuilder
    private func detailsSection(_ section: DetailsSyntax.Section) -> some View {
        switch section {
        case let .markdown(source):
            ForEach(Array(PluginBlockSyntax.sections(source, registry: plugins).enumerated()), id: \.offset) { _, item in
                pluginSection(item)
            }
        case let .details(details):
            let node = MarkdownExtensionNode.details(summary: details.summary, content: details.content,
                                                     isOpen: details.isOpen)
            if let builder = extensionBuilder(node) {
                builder.build(node, context: renderContext())
            } else {
                detailsBlock(details)
            }
        }
    }

    @ViewBuilder
    private func pluginSection(_ section: PluginBlockSyntax.Section) -> some View {
        switch section {
        case let .markdown(source):
            ForEach(Array(FootnoteSyntax.sections(source).enumerated()), id: \.offset) { _, item in
                footnoteSection(item)
            }
        case let .plugin(plugin, match): pluginView(plugin, match)
        }
    }

    @ViewBuilder
    private func footnoteSection(_ section: FootnoteSyntax.Section) -> some View {
        switch section {
        case let .markdown(source):
            #if os(iOS)
            if enableCrossBlockSelection && !voiceOverEnabled && (selectable || onTextLongPress != nil) {
                readerMathSection(source)
            } else {
                ForEach(Array(MathSyntax.sections(source).enumerated()), id: \.offset) { _, item in
                    mathSection(item)
                }
            }
            #else
            ForEach(Array(MathSyntax.sections(source).enumerated()), id: \.offset) { _, item in
                mathSection(item)
            }
            #endif
        case let .definition(definition):
            let node = MarkdownExtensionNode.footnoteDefinition(label: definition.label,
                                                                 content: definition.content)
            if let builder = extensionBuilder(node) {
                builder.build(node, context: renderContext())
            } else {
                footnoteDefinition(definition)
            }
        }
    }

    #if os(iOS)
    @ViewBuilder
    private func readerMathSection(_ source: String) -> some View {
        let items: [ReaderBlockRangeDocument.Item] = MathSyntax.sections(source).flatMap { section in
            switch section {
            case let .markdown(markdown): return Array(parse(markdown).children).map(ReaderBlockRangeDocument.Item.markup)
            case let .block(latex): return [.displayMath(latex)]
            }
        }
        ForEach(Array(ReaderMathSelectionGroup.group(items, enableHTML: enableHTML,
                                                     plugins: plugins,
                                                     allowCodeBlocks: codeBuilder == nil && codeBlockOptions.showCopyButton,
                                                     hasCustomBuilder: containsCustomBlockBuilder,
                                                     hasCustomDisplayMath: { extensionBuilder(.blockMath($0)) != nil }).enumerated()), id: \.offset) { _, group in
            switch group {
            case let .legacy(legacy): readerGroup(legacy)
            case let .math(latex): standaloneBlockMath(latex)
            case let .bridge(items):
                if let document = ReaderBlockRangeDocument(items, enableHTML: enableHTML, plugins: plugins) {
                    ReaderBlockRangeView(document: document, enableHTML: enableHTML, plugins: plugins,
                                         spacing: styleSheet.blockSpacing, startSelecting: false,
                                         onSelectionStarted: nil,
                                         onSelectionFinished: nil) { segment, beginSelection, onCharacterTap in
                        if case let .displayMath(latex) = segment.kind { return AnyView(blockMath(latex)) }
                        return renderReaderBlockSegment(segment, beginSelection: beginSelection,
                                                        onCharacterTap: onCharacterTap)
                    }
                }
            }
        }
    }
    #endif

    @ViewBuilder
    private func mathSection(_ section: MathSyntax.Section) -> some View {
        switch section {
        case let .markdown(source):
            #if os(iOS)
            ForEach(Array(ReaderSelectionGroup.group(Array(parse(source).children),
                                                      enableHTML: enableHTML, plugins: plugins,
                                                      enabled: enableCrossBlockSelection && !voiceOverEnabled &&
                                                          (selectable || onTextLongPress != nil),
                                                      allowCodeBlocks: codeBuilder == nil && codeBlockOptions.showCopyButton,
                                                      hasCustomBuilder: containsCustomBlockBuilder).enumerated()), id: \.offset) { _, group in
                readerGroup(group)
            }
            #else
            ForEach(Array(parse(source).children.enumerated()), id: \.offset) { _, node in block(node) }
            #endif
        case let .block(latex):
            #if os(iOS)
            if selectable || onTextLongPress != nil { standaloneBlockMath(latex) }
            else { blockMath(latex) }
            #else
            blockMath(latex)
            #endif
        }
    }

    #if os(iOS)
    @ViewBuilder
    private func readerGroup(_ group: ReaderSelectionGroup) -> some View {
        switch group {
        case let .selectable(nodes):
            if let document = ReaderSelectionDocument.compose(nodes, enableHTML: enableHTML, plugins: plugins) {
                ReaderSelectionTextView(document: document, styleSheet: styleSheet,
                                        onLinkTap: onLinkTap, onTextLongPress: onTextLongPress,
                                        selectable: selectable, onCharacterTap: nil,
                                        useEnhancedComponents: useEnhancedComponents)
            }
        case let .blockBridge(nodes):
            if let bridge = ReaderBlockRangeDocument(nodes, enableHTML: enableHTML, plugins: plugins) {
                if selectable && onTextLongPress == nil && imageBuilder == nil,
                   let imageItems = ReaderNativeImageSelectionView.imageItems(for: bridge,
                                                                             enableHTML: enableHTML,
                                                                             plugins: plugins) {
                    let imageContents = bridge.segments.filter(\.isImage).compactMap { $0.nodes.first }
                        .map { block($0) }
                    ReaderNativeImageSelectionContainer(document: bridge, styleSheet: styleSheet,
                                                        enableHTML: enableHTML, plugins: plugins,
                                                        onLinkTap: onLinkTap,
                                                        imageContents: imageContents,
                                                        imageItems: imageItems,
                                                        spacing: styleSheet.blockSpacing,
                                                        renderSegment: { segment, beginSelection, onCharacterTap in
                        renderReaderBlockSegment(segment, beginSelection: beginSelection,
                                                 onCharacterTap: onCharacterTap)
                    }, renderRemoteImage: { spec, resolution in
                        resolvedRemoteImageView(spec, resolution: resolution)
                    })
                } else {
                    ReaderBlockRangeView(document: bridge, enableHTML: enableHTML, plugins: plugins,
                                         spacing: styleSheet.blockSpacing, startSelecting: false,
                                         onSelectionStarted: nil,
                                         onSelectionFinished: nil) { segment, beginSelection, onCharacterTap in
                        renderReaderBlockSegment(segment, beginSelection: beginSelection,
                                                 onCharacterTap: onCharacterTap)
                    }
                }
            }
        case let .individual(node):
            if containsCustomBlockBuilder(node) {
                block(node)
            } else if let onTextLongPress,
               let document = ReaderSelectionDocument.compose([node], enableHTML: enableHTML, plugins: plugins) {
                ReaderSelectionTextView(document: document, styleSheet: styleSheet,
                                        onLinkTap: onLinkTap, onTextLongPress: onTextLongPress,
                                        selectable: selectable, onCharacterTap: nil,
                                        useEnhancedComponents: useEnhancedComponents)
            } else {
                block(node)
            }
        }
    }

    private func renderReaderBlockSegment(_ segment: ReaderBlockRangeDocument.Segment,
                                          beginSelection: @escaping () -> Void,
                                          onCharacterTap: ((Int) -> Void)?) -> AnyView {
        if segment.isCode, let node = segment.nodes.first {
            return block(node, onSelectSurroundingContent: beginSelection)
        }
        if segment.isBridge, let node = segment.nodes.first { return block(node) }
        guard let node = segment.nodes.first else { return AnyView(EmptyView()) }
        if let document = ReaderSelectionDocument.compose(segment.nodes,
                                                           enableHTML: enableHTML, plugins: plugins),
           (segment.nodes.count > 1 || document.lines.count > 1 || onTextLongPress != nil || onCharacterTap != nil) {
            // Only use native offsets when the UIKit text and clipboard text
            // have identical projections. Visual anchors can differ.
            let preciseTap = document.canMapNativeOffsets ? onCharacterTap : nil
            return AnyView(ReaderSelectionTextView(document: document, styleSheet: styleSheet,
                                                   onLinkTap: onLinkTap, onTextLongPress: onTextLongPress,
                                                   selectable: selectable, onCharacterTap: preciseTap,
                                                   useEnhancedComponents: useEnhancedComponents))
        }
        return block(node)
    }

    private func standaloneBlockMath(_ latex: String) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            blockMath(latex)
                .contextMenu {
                    Button("Copy formula") { UIPasteboard.general.string = latex }
                }
                .accessibilityAction(named: Text("Copy formula")) {
                    UIPasteboard.general.string = latex
                }
            if selectable, let textSelectionMenuBuilder, !latex.isEmpty {
                ReaderSelectionActionsButton(selectedText: latex, builder: textSelectionMenuBuilder,
                                             copy: { UIPasteboard.general.string = latex },
                                             accessibilityIdentifier: "reader-math-actions")
            }
        }
    }
    #endif

    private func detailsBlock(_ details: DetailsSyntax.Block) -> some View {
        let summary = parse(details.summary)
        let summaryNode = summary.child(at: 0)
        let summaryLabel = summaryNode.map(plainText).flatMap { $0.isEmpty ? nil : $0 } ?? "Details"
        return DetailsBlockView(details: details, summaryLabel: summaryLabel, styleSheet: styleSheet, summary: AnyView(Group {
            if let summaryNode { inlineView(summaryNode) }
        }), content: AnyView(VStack(alignment: .leading, spacing: styleSheet.blockSpacing) {
            ForEach(Array(PluginBlockSyntax.sections(details.content, registry: plugins).enumerated()), id: \.offset) { _, section in
                pluginSection(section)
            }
        }))
    }

    private func footnoteDefinition(_ definition: FootnoteSyntax.Definition) -> some View {
        HStack(alignment: .top, spacing: 0) {
            SwiftUI.Text("[\(definition.label)]: ").bold().foregroundColor(styleSheet.footnoteColor ?? .blue)
            if let content = parse(definition.content).child(at: 0) {
                inlineView(content).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.leading, 16)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func blockContent(_ node: Markup, alignment: TextAlignment? = nil,
                              onSelectSurroundingContent: (() -> Void)? = nil) -> some View {
        if let builder = builderRegistry?.findBuilder(node) {
            builder.build(node, context: renderContext(alignment: alignment))
        } else if let heading = node as? Heading {
            let decorated = useEnhancedComponents && heading.level <= 2
            let primary = Color.accentColor
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: decorated ? 12 : 0) {
                    if decorated {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(LinearGradient(colors: [primary, primary.opacity(0.3)],
                                                 startPoint: .top, endPoint: .bottom))
                            .frame(width: 4, height: headingBarHeight(heading.level))
                            .accessibilityHidden(true)
                    }
                    inlineView(heading)
                        .font(styleSheet.headingFonts?.indices.contains(heading.level - 1) == true
                              ? styleSheet.headingFonts![heading.level - 1]
                              : headingFont(heading.level))
                        .foregroundColor(styleSheet.headingColor ?? styleSheet.textColor)
                        .multilineTextAlignment(alignment ?? .leading)
                        .frame(maxWidth: .infinity, alignment: frameAlignment(alignment))
                        .markdownTextSelection(selectable)
                        .accessibilityAddTraits(.isHeader)
                }
                .padding(.vertical, useEnhancedComponents ? 8 : 0)
                if decorated {
                    Rectangle()
                        .fill(LinearGradient(colors: [primary.opacity(0.3), primary.opacity(0)],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(height: 2)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, alignment: frameAlignment(alignment))
        } else if let paragraph = node as? Paragraph {
            let meaningful = Array(paragraph.children).filter { child in
                guard let text = child as? Markdown.Text else { return true }
                return !text.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            let sole = meaningful.count == 1 ? meaningful.first : nil
            if let image = sole as? Markdown.Image {
                if hasCustomBuilder(image) { customInlineView(image, style: .init()) }
                else { imageView(image) }
            } else if enableHTML, let html = sole as? InlineHTML, let image = SafeHTML.imageTag(html.rawHTML) {
                imageView(image)
            } else {
                #if os(iOS)
                if !containsCustomBlockBuilder(paragraph), (alignment == nil || alignment == .leading),
                   let document = ReaderSelectionDocument.inlineCodeParagraph(
                       paragraph, enableHTML: enableHTML, plugins: plugins) {
                    ReaderSelectionTextView(document: document, styleSheet: styleSheet,
                                            onLinkTap: onLinkTap, onTextLongPress: onTextLongPress,
                                            selectable: selectable, onCharacterTap: nil,
                                            useEnhancedComponents: useEnhancedComponents)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    inlineView(paragraph).font(styleSheet.paragraphFont ?? .body)
                        .multilineTextAlignment(alignment ?? .leading)
                        .frame(maxWidth: .infinity, alignment: frameAlignment(alignment))
                        .markdownTextSelection(selectable)
                }
                #else
                inlineView(paragraph).font(styleSheet.paragraphFont ?? .body).multilineTextAlignment(alignment ?? .leading)
                    .frame(maxWidth: .infinity, alignment: frameAlignment(alignment))
                    .markdownTextSelection(selectable)
                #endif
            }
        } else if let code = node as? CodeBlock {
            if let codeBuilder {
                codeBuilder(code.code, code.language)
            } else if useEnhancedComponents {
                EnhancedCodeBlockView(code: code.code, language: code.language,
                                      options: codeBlockOptions, onCopy: onCodeCopy,
                                      styleSheet: styleSheet, selectable: selectable,
                                      onSelectSurroundingContent: onSelectSurroundingContent)
            } else {
                StandardCodeBlockView(code: code.code, language: code.language,
                                      styleSheet: styleSheet, selectable: selectable,
                                      onCopy: onCodeCopy)
            }
        } else if let quote = node as? BlockQuote {
            blockquote(enhanced: useEnhancedComponents) {
                ForEach(Array(quote.children.enumerated()), id: \.offset) { _, child in
                    block(child, alignment: alignment)
                }
            }
        } else if let ordered = node as? OrderedList {
            list(ordered, start: Int(ordered.startIndex))
        } else if let unordered = node as? UnorderedList {
            list(unordered, start: nil)
        } else if let table = node as? Markdown.Table {
            tableView(table)
        } else if node is ThematicBreak {
            horizontalRule()
        } else if let html = node as? HTMLBlock {
            htmlBlock(html, alignment: alignment)
        } else {
            SwiftUI.Text(plainText(node)).markdownTextSelection(selectable)
        }
    }

    private func headingFont(_ level: Int) -> Font {
        MarkdownTypography.heading(level)
    }

    private func headingBarHeight(_ level: Int) -> CGFloat {
        #if os(iOS)
        UIFont.preferredFont(forTextStyle: MarkdownTypography.textStyle(forHeading: level),
                             compatibleWith: MarkdownTypography.traits(for: dynamicTypeSize)).pointSize
        #else
        level == 1 ? 28 : 22
        #endif
    }

    @ViewBuilder
    private func htmlBlock(_ html: HTMLBlock, alignment: TextAlignment?) -> some View {
        if enableHTML, let image = SafeHTML.imageTag(html.rawHTML) {
            imageView(image)
        } else if enableHTML, let alt = SafeHTML.imageAlt(html.rawHTML) {
            SwiftUI.Text(alt).markdownTextSelection(selectable)
        } else if enableHTML, let parsed = SafeHTML.parseBlock(html.rawHTML) {
            switch parsed {
            case .rule:
                horizontalRule()
            case let .container(name, content, declared, trailing):
                let childAlignment: TextAlignment? = switch declared {
                case "left": .leading
                case "center": .center
                case "right": .trailing
                default: alignment
                }
                if name == "blockquote" {
                    blockquote {
                        ForEach(Array(parse(content).children.enumerated()), id: \.offset) { _, child in
                            block(child, alignment: childAlignment)
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: styleSheet.quoteSpacing) {
                        ForEach(Array(parse(content).children.enumerated()), id: \.offset) { _, child in
                            block(child, alignment: childAlignment)
                        }
                    }
                }
                if !trailing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ForEach(Array(parse(trailing).children.enumerated()), id: \.offset) { _, child in
                        block(child, alignment: alignment)
                    }
                }
            }
        } else {
            SwiftUI.Text(html.rawHTML).markdownTextSelection(selectable)
        }
    }

    private func blockquote<Content: View>(enhanced: Bool = false,
                                           @ViewBuilder content: () -> Content) -> some View {
        let decoration = styleSheet.resolvedBlockquoteDecoration
        return Group {
            if enhanced {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "text.quote")
                        .font(.system(size: 24))
                        .foregroundStyle(Color.accentColor.opacity(0.4))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: styleSheet.quoteSpacing, content: content)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(styleSheet.blockquotePadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(LinearGradient(colors: colorScheme == .dark
                    ? [Color(white: 0.10), Color(white: 0.15)]
                    : [Color(white: 0.98), Color(white: 0.95)],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(alignment: .leading) {
                    Rectangle().fill(Color.accentColor.opacity(0.6)).frame(width: 4)
                }
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0,
                                                   bottomTrailingRadius: 4, topTrailingRadius: 4))
                .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
            } else {
                VStack(alignment: .leading, spacing: styleSheet.quoteSpacing, content: content)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(styleSheet.blockquotePadding)
                    .background(decoration.backgroundColor ?? Color.clear)
                    .overlay(alignment: .leading) {
                        if decoration.borderWidth > 0 {
                            Rectangle().fill(decoration.borderColor ?? .accentColor)
                                .frame(width: decoration.borderWidth)
                        }
                    }
            }
        }
    }

    @ViewBuilder
    private func list(_ node: Markup, start: Int?) -> some View {
        VStack(alignment: .leading, spacing: styleSheet.listSpacing) {
            ForEach(Array(node.children.enumerated()), id: \.offset) { index, child in
                if let item = child as? Markdown.ListItem {
                    if hasCustomBuilder(item) {
                        block(item)
                    } else {
                        HStack(alignment: .top, spacing: 8) {
                            SwiftUI.Text(listMarker(item, index: index, start: start))
                                .font(styleSheet.listBulletFont)
                                .foregroundColor(styleSheet.listBulletColor)
                                .frame(width: styleSheet.listIndent, alignment: .leading)
                            VStack(alignment: .leading, spacing: styleSheet.listSpacing) {
                                ForEach(Array(item.children.enumerated()), id: \.offset) { _, blockNode in
                                    block(blockNode)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
    }

    private func listMarker(_ item: Markdown.ListItem, index: Int, start: Int?) -> String {
        if let checkbox = item.checkbox { return checkbox == .checked ? "☑" : "☐" }
        if let start { return "\(start + index)." }
        return "•"
    }

    @ViewBuilder
    private func tableView(_ table: Markdown.Table, selectable overrideSelectable: Bool? = nil) -> some View {
        let headers = Array(table.head.children)
        let rows = [headers] + table.body.children.map { Array($0.children) }
        let columnCount = max(1, rows.map(\.count).max() ?? 0)
        MarkdownTableViewport(columnCount: columnCount, padding: styleSheet.tableCellPadding) { cellWidth in
            ScrollView(.horizontal) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, cells in
                        HStack(spacing: 0) {
                            ForEach(0..<columnCount, id: \.self) { columnIndex in
                                let presentation = MarkdownTableColumnPresentation(
                                    table.columnAlignments.indices.contains(columnIndex)
                                        ? table.columnAlignments[columnIndex] : nil)
                                Group {
                                    if cells.indices.contains(columnIndex) {
                                        if hasCustomBuilder(cells[columnIndex]) {
                                            customInlineView(cells[columnIndex], style: .init())
                                        } else {
                                            inlineView(cells[columnIndex])
                                                .font(rowIndex == 0 ? (styleSheet.tableHeaderFont ?? .body)
                                                      : (styleSheet.tableCellFont ?? .body))
                                                .fontWeight(rowIndex == 0 ? .bold : .regular)
                                                .markdownTextSelection(overrideSelectable ?? selectable)
                                        }
                                    } else {
                                        SwiftUI.Text("")
                                    }
                                }
                                    .multilineTextAlignment(presentation.textAlignment)
                                    .frame(width: max(1, cellWidth - 2 * styleSheet.tableCellPadding),
                                           alignment: presentation.frameAlignment)
                                    .padding(styleSheet.tableCellPadding)
                                    .accessibilityAddTraits(rowIndex == 0 ? .isHeader : [])
                                    .accessibilityHint(rowIndex == 0 ? "Column header" :
                                        "Row \(rowIndex), column \(columnIndex + 1), \(headers.indices.contains(columnIndex) ? plainText(headers[columnIndex]) : "")")
                            }
                        }
                        .background(rowIndex == 0 ? (styleSheet.tableHeaderBackgroundColor ?? Color.clear) : Color.clear)
                        .overlay {
                            Canvas { context, size in
                                for segment in MarkdownTableGridLayout.segments(
                                    border: styleSheet.resolvedTableBorder, rowIndex: rowIndex,
                                    rowCount: rows.count, columnCount: columnCount,
                                    columnWidth: cellWidth, rowHeight: size.height) {
                                    var path = Path()
                                    path.move(to: segment.start)
                                    path.addLine(to: segment.end)
                                    context.stroke(path, with: .color(segment.side.color),
                                                   lineWidth: segment.side.width)
                                }
                            }
                            .allowsHitTesting(false)
                        }
                    }
                }
            }
        }
    }

    private func horizontalRule() -> some View {
        Rectangle()
            .fill(styleSheet.ruleColor ?? Color.secondary.opacity(0.4))
            .frame(height: styleSheet.horizontalRuleThickness)
            .frame(maxWidth: .infinity)
            .padding(.vertical, styleSheet.blockSpacing / 2)
    }

    @ViewBuilder
    private func imageView(_ image: Markdown.Image) -> some View {
        if let source = image.source {
            imageView(SafeHTML.ImageSpec(source: source, alt: plainText(image), title: image.title, width: nil, height: nil))
        } else {
            SwiftUI.Text(plainText(image))
        }
    }

    private func imageView(_ image: SafeHTML.ImageSpec, inline: Bool = false) -> AnyView {
        let label = image.alt.isEmpty ? (image.title ?? "Image") : image.alt
        let width: CGFloat? = image.width.map { CGFloat($0) }
        let height: CGFloat? = image.height.map { CGFloat($0) }
        guard let source = ImageSource.parse(image.source) else { return AnyView(SwiftUI.Text(label)) }
        let tapURL: URL? = switch source {
        case let .remote(url, _): url
        case let .bundled(name, _): URL(string: name)
        }
        if let imageBuilder {
            return accessibleImage(imageBuilder(image.source, image.alt, image.title)
                .frame(width: width, height: height),
                url: tapURL, image: image, label: label, inline: inline)
        }
        switch source {
        case let .remote(url, svg: true):
            return accessibleImage(
                AsyncSVGView(url: url) { phase in
                    switch phase {
                    case .success(let svg):
                        NaturalImageLayout(naturalSize: svg.size, explicitWidth: width, explicitHeight: height) {
                            SVGView(svg: svg).resizable().scaledToFit()
                        }
                    case .failure: SwiftUI.Text(label)
                    case .empty: ProgressView()
                    }
                }, url: url, image: image, label: label, inline: inline)
        case let .remote(url, svg: false):
            return accessibleImage(
                RemoteBitmapView(url: url, width: width, height: height, fallback: label),
                url: url, image: image, label: label, inline: inline)
        case let .bundled(name, svg: true):
            guard let svg = SVG(named: name, in: .main) else { return AnyView(SwiftUI.Text(label)) }
            return accessibleImage(
                NaturalImageLayout(naturalSize: svg.size, explicitWidth: width, explicitHeight: height) {
                    SVGView(svg: svg).resizable().scaledToFit()
                }, url: URL(string: name), image: image, label: label, inline: inline)
        case let .bundled(name, svg: false):
            return accessibleImage(
                BundledBitmapView(name: name, width: width, height: height, fallback: label),
                url: URL(string: name), image: image, label: label, inline: inline)
        }
    }

    #if os(iOS)
    /// Uses the bytes already decoded for native cross-image selection. The
    /// loading and failure branches match the standard iOS image renderer.
    private func resolvedRemoteImageView(_ image: SafeHTML.ImageSpec,
                                         resolution: ReaderRemoteImageResolution?) -> AnyView {
        let label = image.alt.isEmpty ? (image.title ?? "Image") : image.alt
        guard let source = ImageSource.parse(image.source),
              case let .remote(url, _) = source else {
            return AnyView(SwiftUI.Text(label))
        }
        let width = image.width.map { CGFloat($0) }
        let height = image.height.map { CGFloat($0) }
        let content: AnyView
        switch resolution {
        case let .svg(svg):
            content = AnyView(NaturalImageLayout(naturalSize: svg.size,
                                                 explicitWidth: width, explicitHeight: height) {
                SVGView(svg: svg).resizable().scaledToFit()
            })
        case let .bitmap(bitmap):
            content = AnyView(NaturalImageLayout(naturalSize: bitmap.size,
                                                 explicitWidth: width, explicitHeight: height) {
                SwiftUI.Image(uiImage: bitmap).resizable().scaledToFit()
            })
        case .failure, .rejected:
            if source.remoteFailurePresentation == .svgAltText {
                content = AnyView(SwiftUI.Text(label))
            } else {
                content = AnyView(RemoteBitmapFailureView(label: label))
            }
        case nil: content = AnyView(ProgressView())
        }
        return accessibleImage(content, url: url, image: image, label: label, inline: false)
    }
    #endif

    private func accessibleImage<Content: View>(_ content: Content, url: URL?, image: SafeHTML.ImageSpec, label: String, inline: Bool) -> AnyView {
        if onImageTapWithMetadata != nil || (url != nil && onImageTap != nil) {
            return AnyView(Button {
                onImageTapWithMetadata?(image.source, image.alt, image.title)
                if let url { onImageTap?(url) }
            } label: {
                content.padding(inline ? 10 : 0)
                    .contentShape(Rectangle())
            }
                .buttonStyle(.plain)
                .accessibilityLabel(label))
        }
        return AnyView(content.accessibilityLabel(label))
    }

    private func customInlineView(_ node: Markup, style: InlineContent.Style) -> AnyView {
        guard let builder = builderRegistry?.findBuilder(node) else { return inlineView(node) }
        return builder.build(node, context: renderContext(inlineStyle: style))
    }

    private func pluginView(_ plugin: any InlineParserPlugin, _ match: InlinePluginMatch) -> AnyView {
        let node = MarkdownPluginNode(plugin: plugin, match: match)
        guard let builder = builderRegistry?.findBuilder(node) else { return plugin.render(match) }
        return builder.build(node, context: renderContext())
    }

    private func pluginView(_ plugin: any BlockParserPlugin, _ match: BlockPluginMatch) -> AnyView {
        let node = MarkdownPluginNode(plugin: plugin, match: match)
        if let builder = builderRegistry?.findBuilder(node) {
            return builder.build(node, context: renderContext())
        }
        guard MarkdownEnhancedComponents.usesBuiltInAICard(for: plugin.id, enabled: useEnhancedComponents) else {
            return AnyView(Text("Unknown node type: \(plugin.id)"))
        }
        let rendered = plugin.render(match)
        #if os(iOS)
        if selectable, let textSelectionMenuBuilder,
           let copyText = ReaderPluginSelectionText.copyText(pluginID: plugin.id, content: match.content) {
            return AnyView(VStack(alignment: .trailing, spacing: 0) {
                rendered
                ReaderSelectionActionsButton(selectedText: copyText,
                                             builder: textSelectionMenuBuilder,
                                             copy: { UIPasteboard.general.string = copyText },
                                             accessibilityIdentifier: "reader-plugin-actions")
            })
        }
        #endif
        return rendered
    }

    private struct InlineStyle {
        var bold = false
        var italic = false
        var strike = false
        var link: URL?
    }

    private func inline(_ runs: [InlineContent.Run]) -> SwiftUI.Text {
        runs.enumerated().reduce(SwiftUI.Text("")) { output, element in
            let (index, run) = element
            if case let .text(value, sourceStyle, tags, code) = run {
                let rendered = output + segment(value, style: inlineStyle(sourceStyle), tags: tags, code: code)
                if useEnhancedComponents, !selectable, let link = sourceStyle.link,
                   MarkdownEnhancedComponents.isExternalLink(link),
                   (index + 1 == runs.count || !runs[index + 1].hasLink(link)) {
                    // A nonselectable SwiftUI text run can add the external-link cue
                    // directly. Native selectable text draws it without changing Copy.
                    return rendered + segment(" ↗", style: inlineStyle(sourceStyle), tags: tags, code: false)
                        .font(.system(size: 12))
                }
                return rendered
            }
            return output
        }
    }

    private enum FlowPiece {
        case text(SwiftUI.Text)
        case custom(Markup, InlineContent.Style)
        case extensionNode(MarkdownExtensionNode)
        case image(SafeHTML.ImageSpec)
        case math(String)
        case plugin(any InlineParserPlugin, InlinePluginMatch)
        case lineBreak
    }

    private func inlineView(_ node: Markup) -> AnyView {
        let runs = InlineContent.runs(in: node, enableHTML: enableHTML, plugins: plugins,
                                      hasCustomBuilder: builderRegistry == nil ? nil : hasCustomBuilder)
        let hasCustom = runs.contains { if case .custom = $0 { return true }; return false }
        #if os(iOS)
        if !hasCustom, runs.contains(where: { run in
            if case let .text(_, _, tags, _) = run { return tags.contains(where: { $0.name == "kbd" }) }
            return false
        }), let document = ReaderSelectionDocument.inline(node, enableHTML: enableHTML, plugins: plugins) {
            // TextKit keeps the label, surrounding prose, wrapping, and selection
            // in one native text range while drawing the keycap around its glyphs.
            return AnyView(ReaderSelectionTextView(document: document, styleSheet: styleSheet,
                                                   onLinkTap: onLinkTap, onTextLongPress: onTextLongPress,
                                                   selectable: selectable, onCharacterTap: nil,
                                                   useEnhancedComponents: useEnhancedComponents))
        }
        #endif
        let hasImage = runs.contains { if case .image = $0 { return true }; return false }
        let hasFootnote = runs.contains { if case .footnote = $0 { return true }; return false }
        let hasMath = runs.contains { if case .math = $0 { return true }; return false }
        let hasPlugin = runs.contains { if case .plugin = $0 { return true }; return false }
        let hasCustomFootnote = runs.contains { run in
            if case let .footnote(label) = run {
                return extensionBuilder(.footnoteReference(label)) != nil
            }
            return false
        }
        let hasCustomHTMLStyle = runs.contains { run in
            if case let .text(value, _, tags, _) = run { return htmlStyleNode(value, tags: tags) != nil }
            return false
        }
        if !hasImage && !hasFootnote && !hasMath && !hasPlugin && !hasCustom && !hasCustomHTMLStyle {
            return AnyView(inline(runs))
        }
        if !hasImage && !hasMath && !hasPlugin && !hasCustom && !hasCustomFootnote && !hasCustomHTMLStyle {
            var result = SwiftUI.Text("")
            for run in runs {
                switch run {
                case let .text(value, sourceStyle, tags, code):
                    result = result + segment(value, style: inlineStyle(sourceStyle), tags: tags, code: code)
                case let .footnote(label): result = result + footnoteReference(label)
                case .image, .math, .plugin, .custom: break
                }
            }
            return AnyView(result)
        }
        var pieces: [FlowPiece] = []
        for run in runs {
            switch run {
            case let .image(image):
                pieces.append(.image(image))
            case let .footnote(label):
                let node = MarkdownExtensionNode.footnoteReference(label)
                if extensionBuilder(node) != nil { pieces.append(.extensionNode(node)) }
                else { pieces.append(.text(footnoteReference(label))) }
            case let .math(latex):
                pieces.append(.math(latex))
            case let .plugin(plugin, match):
                pieces.append(.plugin(plugin, match))
            case let .custom(node, style):
                pieces.append(.custom(node, style))
            case let .text(value, sourceStyle, tags, code):
                if let node = htmlStyleNode(value, tags: tags) {
                    pieces.append(.extensionNode(node))
                    continue
                }
                let style = inlineStyle(sourceStyle)
                var word = ""
                for character in value {
                    if character == "\n" {
                        if !word.isEmpty { pieces.append(.text(segment(word, style: style, tags: tags, code: code))); word = "" }
                        pieces.append(.lineBreak)
                    } else {
                        word.append(character)
                        if character.isWhitespace {
                            pieces.append(.text(segment(word, style: style, tags: tags, code: code)))
                            word = ""
                        }
                    }
                }
                if !word.isEmpty { pieces.append(.text(segment(word, style: style, tags: tags, code: code))) }
            }
        }
        return AnyView(InlineFlowLayout {
            ForEach(Array(pieces.enumerated()), id: \.offset) { _, piece in
                switch piece {
                case let .text(text): text.fixedSize()
                case let .custom(node, style): customInlineView(node, style: style).fixedSize()
                case let .extensionNode(node):
                    extensionBuilder(node)?.build(node, context: renderContext()).fixedSize()
                case let .image(image):
                    imageView(image, inline: true)
                        .layoutValue(key: InlineImageKey.self, value: true)
                case let .math(latex):
                    inlineMath(latex)
                case let .plugin(plugin, match):
                    pluginView(plugin, match).fixedSize()
                case .lineBreak:
                    Color.clear.frame(width: 0, height: 0)
                        .layoutValue(key: InlineBreakKey.self, value: true)
                }
            }
        })
    }

    private func inlineStyle(_ source: InlineContent.Style) -> InlineStyle {
        InlineStyle(bold: source.bold, italic: source.italic, strike: source.strike, link: source.link)
    }

    private func footnoteReference(_ label: String) -> SwiftUI.Text {
        SwiftUI.Text("[\(label)]").font(.footnote).baselineOffset(5)
            .foregroundColor(styleSheet.footnoteColor ?? .blue)
    }

    @ViewBuilder
    private func inlineMath(_ latex: String) -> some View {
        let node = MarkdownExtensionNode.inlineMath(latex)
        if let builder = extensionBuilder(node) {
            builder.build(node, context: renderContext()).fixedSize()
        } else {
            NativeMathView(latex: latex, size: 16, display: false)
                .fixedSize()
                .accessibilityLabel(latex)
        }
    }

    private func blockMath(_ latex: String) -> some View {
        let node = MarkdownExtensionNode.blockMath(latex)
        return Group {
            if let builder = extensionBuilder(node) {
                builder.build(node, context: renderContext())
            } else {
                nativeBlockMath(latex)
            }
        }
    }

    private func nativeBlockMath(_ latex: String) -> some View {
        ScrollView(.horizontal) {
            NativeMathView(latex: latex, size: 20, display: true)
                .fixedSize()
                .accessibilityLabel(latex.isEmpty ? "Empty formula" : latex)
        }
        .defaultScrollAnchor(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private func segment(_ value: String, style: InlineStyle, tags: [SafeHTML.Tag], code: Bool = false) -> SwiftUI.Text {
        var bold = style.bold
        var italic = style.italic
        var strike = style.strike
        var htmlUnderline = false
        var htmlHighlight = false
        var htmlCode = false
        let script = enableHTML ? MarkdownHTMLScript.active(in: tags) : nil
        var htmlForeground: Color?
        var htmlBackground: Color?
        var htmlFontSize: CGFloat?
        var link = style.link
        if enableHTML {
            for tag in tags {
                switch tag.name {
                case "b", "strong": bold = true
                case "i", "em": italic = true
                case "s", "del", "strike": strike = true
                case "u", "ins": htmlUnderline = true
                case "mark": htmlHighlight = true
                case "code", "kbd":
                    htmlCode = true
                case "a":
                    if let href = tag.attributes["href"], SafeHTML.isSafeLink(href) { link = URL(string: href) }
                case "font", "span":
                    let css = tag.name == "span" ? SafeHTML.cssDeclarations(tag.attributes["style"] ?? "") : [:]
                    if let value = tag.name == "font" ? tag.attributes["color"] : css["color"],
                       let color = SafeHTML.color(value) { htmlForeground = colorFromARGB(color) }
                    if let value = css["background-color"], let color = SafeHTML.color(value) { htmlBackground = colorFromARGB(color) }
                    if let size = tag.name == "font" ? tag.attributes["size"].flatMap(SafeHTML.legacyFontSize)
                        : css["font-size"].flatMap(SafeHTML.fontSize) { htmlFontSize = CGFloat(size) }
                default: break
                }
            }
        }
        let inlineStyle = styleSheet.resolvedHTMLStyle(
            styleSheet.resolvedInlineStyle(bold: bold, italic: italic, strike: strike,
                                           link: link != nil, code: code || htmlCode,
                                           script: script),
            underline: htmlUnderline, highlight: htmlHighlight)
        var attributed = AttributedString(value)
        if let background = htmlBackground ?? inlineStyle.backgroundColor { attributed.backgroundColor = background }
        if let link { attributed.link = link }
        var result = SwiftUI.Text(attributed)
        let monospaced = inlineStyle.monospaced == true
        if monospaced { result = result.font(.system(.body, design: .monospaced)) }
        if let fontSize = htmlFontSize ?? inlineStyle.fontSize {
            result = result.font(.system(size: fontSize * inlineFontScale,
                                         design: monospaced ? .monospaced : .default))
        }
        if inlineStyle.bold == true { result = result.bold() }
        if inlineStyle.italic == true { result = result.italic() }
        if inlineStyle.strikethrough == true { result = result.strikethrough() }
        if inlineStyle.underline == true || (useEnhancedComponents && link != nil) {
            result = result.underline()
        }
        if let script { result = result.baselineOffset(script.baselineOffset(scale: inlineFontScale)) }
        if let foreground = htmlForeground ?? inlineStyle.textColor { result = result.foregroundColor(foreground) }
        return result
    }

    private func colorFromARGB(_ value: UInt32) -> Color {
        Color(.sRGB, red: Double((value >> 16) & 0xFF) / 255,
              green: Double((value >> 8) & 0xFF) / 255,
              blue: Double(value & 0xFF) / 255, opacity: 1)
    }

    private func frameAlignment(_ alignment: TextAlignment?) -> Alignment {
        switch alignment {
        case .center: .center
        case .trailing: .trailing
        default: .leading
        }
    }

    private func plainText(_ node: Markup) -> String {
        if let text = node as? Markdown.Text { return text.string }
        if let code = node as? InlineCode { return code.code }
        if let code = node as? CodeBlock { return code.code }
        if node is SoftBreak || node is LineBreak { return "\n" }
        return node.children.map(plainText).joined()
    }

}

private struct DetailsBlockView: View {
    let details: DetailsSyntax.Block
    let summaryLabel: String
    let styleSheet: MarkdownStyleSheet
    let summary: AnyView
    let content: AnyView
    @State private var isExpanded: Bool

    init(details: DetailsSyntax.Block, summaryLabel: String, styleSheet: MarkdownStyleSheet,
         summary: AnyView, content: AnyView) {
        self.details = details
        self.summaryLabel = summaryLabel
        self.styleSheet = styleSheet
        self.summary = summary
        self.content = content
        _isExpanded = State(initialValue: details.isOpen)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { isExpanded.toggle() } label: {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .frame(width: 20)
                    summary.frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(12)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(summaryLabel)
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            .accessibilityHint(isExpanded ? "Double tap to collapse" : "Double tap to expand")
            if isExpanded && !details.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Divider().overlay(styleSheet.ruleColor ?? Color.clear)
                content.padding(.horizontal, 12).padding(.bottom, 12)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(styleSheet.tableBorderColor ?? Color.gray.opacity(0.35)))
        .padding(.vertical, 8)
    }
}
