import Markdown
import SwiftDraw
import SwiftUI
import SwiftUIMath
#if os(iOS)
import UIKit
#endif

/// Renders the currently supported CommonMark and GFM blocks with SwiftUI.
public struct SmoothMarkdownView: View {
    /// Statistics for the document parse cache used by reader views.
    public static var cacheStatistics: MarkdownCacheStatistics { MarkdownParseCache.shared.statistics }

    /// Drops parsed documents so subsequent renders parse their source again.
    public static func clearCache() { MarkdownParseCache.shared.clear() }

    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
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
    public let codeBlockOptions: CodeBlockOptions
    public let codeBuilder: ((String, String?) -> AnyView)?
    public let onCodeCopy: ((String, String?) -> Void)?
    /// When provided, intercepts a rendered-text long press and supplies an action that
    /// selects the paragraph under the press in the native text view.
    public let onTextLongPress: ((@escaping () -> Void) -> Void)?
    public let styleSheet: MarkdownStyleSheet
    public let plugins: ParserPluginRegistry?
    /// Reuses parsed documents for repeated source when no parser plugins are installed.
    /// Disable for rapidly changing content such as a live stream.
    public let enableCache: Bool
    /// Enables native text selection in the reader. Defaults to false, like Flutter.
    public let selectable: Bool
    public let enableCrossBlockSelection: Bool
    /// Set to false when a host scroll view owns vertical scrolling, such as a chat list.
    public let scrollable: Bool

    public init(
        markdown: String,
        onLinkTap: ((URL) -> Void)? = nil,
        onImageTap: ((URL) -> Void)? = nil,
        onImageTapWithMetadata: ((String, String?, String?) -> Void)? = nil,
        imageBuilder: ((String, String?, String?) -> AnyView)? = nil,
        enableHTML: Bool = false,
        codeBlockOptions: CodeBlockOptions = CodeBlockOptions(),
        codeBuilder: ((String, String?) -> AnyView)? = nil,
        onCodeCopy: ((String, String?) -> Void)? = nil,
        onTextLongPress: ((@escaping () -> Void) -> Void)? = nil,
        styleSheet: MarkdownStyleSheet = .default(),
        plugins: ParserPluginRegistry? = nil,
        enableCache: Bool = true,
        selectable: Bool = false,
        enableCrossBlockSelection: Bool = true,
        scrollable: Bool = true
    ) {
        self.markdown = markdown
        self.onLinkTap = onLinkTap
        self.onImageTap = onImageTap
        self.onImageTapWithMetadata = onImageTapWithMetadata
        self.imageBuilder = imageBuilder
        self.enableHTML = enableHTML
        self.codeBlockOptions = codeBlockOptions
        self.codeBuilder = codeBuilder
        self.onCodeCopy = onCodeCopy
        self.onTextLongPress = onTextLongPress
        self.styleSheet = styleSheet
        self.plugins = plugins
        self.enableCache = enableCache
        self.selectable = selectable
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

    private var renderedBlocks: some View {
        LazyVStack(alignment: .leading, spacing: styleSheet.blockSpacing) {
            ForEach(Array(DetailsSyntax.sections(markdown).enumerated()), id: \.offset) { _, section in
                detailsSection(section)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(styleSheet.contentPadding)
    }

    var usesParseCache: Bool { enableCache && plugins == nil }

    private func parse(_ source: String) -> Document {
        // Plugin registries may change behavior without changing the source key.
        MarkdownSyntax.parse(source, useCache: usesParseCache)
    }

    private func block(_ node: Markup, alignment: TextAlignment? = nil,
                       onSelectSurroundingContent: (() -> Void)? = nil) -> AnyView {
        AnyView(blockContent(node, alignment: alignment,
                             onSelectSurroundingContent: onSelectSurroundingContent))
    }

    @ViewBuilder
    private func detailsSection(_ section: DetailsSyntax.Section) -> some View {
        switch section {
        case let .markdown(source):
            ForEach(Array(PluginBlockSyntax.sections(source, registry: plugins).enumerated()), id: \.offset) { _, item in
                pluginSection(item)
            }
        case let .details(details): detailsBlock(details)
        }
    }

    @ViewBuilder
    private func pluginSection(_ section: PluginBlockSyntax.Section) -> some View {
        switch section {
        case let .markdown(source):
            ForEach(Array(FootnoteSyntax.sections(source).enumerated()), id: \.offset) { _, item in
                footnoteSection(item)
            }
        case let .plugin(plugin, match): plugin.render(match)
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
        case let .definition(definition): footnoteDefinition(definition)
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
                                                     allowCodeBlocks: codeBuilder == nil && codeBlockOptions.showCopyButton).enumerated()), id: \.offset) { _, group in
            switch group {
            case let .legacy(legacy): readerGroup(legacy)
            case let .math(latex): standaloneBlockMath(latex)
            case let .bridge(items):
                if let document = ReaderBlockRangeDocument(items, enableHTML: enableHTML, plugins: plugins) {
                    ReaderBlockRangeView(document: document, enableHTML: enableHTML, plugins: plugins,
                                         spacing: styleSheet.blockSpacing, startSelecting: false,
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
                                                      allowCodeBlocks: codeBuilder == nil && codeBlockOptions.showCopyButton).enumerated()), id: \.offset) { _, group in
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
                                        selectable: selectable, onCharacterTap: nil)
            }
        case let .blockBridge(nodes):
            if let bridge = ReaderBlockRangeDocument(nodes, enableHTML: enableHTML, plugins: plugins) {
                if selectable && onTextLongPress == nil && imageBuilder == nil,
                   let imageSizes = ReaderNativeImageSelectionView.imageSizes(for: bridge,
                                                                             enableHTML: enableHTML,
                                                                             plugins: plugins) {
                    let imageContents = bridge.segments.filter(\.isImage).compactMap { $0.nodes.first }
                        .map { block($0) }
                    ReaderNativeImageSelectionContainer(document: bridge, styleSheet: styleSheet,
                                                        enableHTML: enableHTML, plugins: plugins,
                                                        onLinkTap: onLinkTap,
                                                        imageContents: imageContents,
                                                        naturalImageSizes: imageSizes,
                                                        spacing: styleSheet.blockSpacing) { segment, beginSelection, onCharacterTap in
                        renderReaderBlockSegment(segment, beginSelection: beginSelection,
                                                 onCharacterTap: onCharacterTap)
                    }
                } else {
                    ReaderBlockRangeView(document: bridge, enableHTML: enableHTML, plugins: plugins,
                                         spacing: styleSheet.blockSpacing, startSelecting: false,
                                         onSelectionFinished: nil) { segment, beginSelection, onCharacterTap in
                        renderReaderBlockSegment(segment, beginSelection: beginSelection,
                                                 onCharacterTap: onCharacterTap)
                    }
                }
            }
        case let .individual(node):
            if let onTextLongPress,
               let document = ReaderSelectionDocument.compose([node], enableHTML: enableHTML, plugins: plugins) {
                ReaderSelectionTextView(document: document, styleSheet: styleSheet,
                                        onLinkTap: onLinkTap, onTextLongPress: onTextLongPress,
                                        selectable: selectable, onCharacterTap: nil)
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
            let preciseTap = document.selectionText == document.copiedText ? onCharacterTap : nil
            return AnyView(ReaderSelectionTextView(document: document, styleSheet: styleSheet,
                                                   onLinkTap: onLinkTap, onTextLongPress: onTextLongPress,
                                                   selectable: selectable, onCharacterTap: preciseTap))
        }
        return block(node)
    }

    private func standaloneBlockMath(_ latex: String) -> some View {
        blockMath(latex)
            .contextMenu {
                Button("Copy formula") { UIPasteboard.general.string = latex }
            }
            .accessibilityAction(named: Text("Copy formula")) {
                UIPasteboard.general.string = latex
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
        if let heading = node as? Heading {
            let decorated = heading.level <= 2
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
                .padding(.vertical, 8)
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
                imageView(image)
            } else if enableHTML, let html = sole as? InlineHTML, let image = SafeHTML.imageTag(html.rawHTML) {
                imageView(image)
            } else {
                inlineView(paragraph).font(styleSheet.paragraphFont ?? .body).multilineTextAlignment(alignment ?? .leading)
                    .frame(maxWidth: .infinity, alignment: frameAlignment(alignment))
                    .markdownTextSelection(selectable)
            }
        } else if let code = node as? CodeBlock {
            if let codeBuilder {
                codeBuilder(code.code, code.language)
            } else {
                EnhancedCodeBlockView(code: code.code, language: code.language,
                                      options: codeBlockOptions, onCopy: onCodeCopy,
                                      styleSheet: styleSheet, selectable: selectable,
                                      onSelectSurroundingContent: onSelectSurroundingContent)
            }
        } else if let quote = node as? BlockQuote {
            blockquote {
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

    private func blockquote<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        let decoration = styleSheet.resolvedBlockquoteDecoration
        return VStack(alignment: .leading, spacing: styleSheet.quoteSpacing, content: content)
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

    @ViewBuilder
    private func list(_ node: Markup, start: Int?) -> some View {
        VStack(alignment: .leading, spacing: styleSheet.listSpacing) {
            ForEach(Array(node.children.enumerated()), id: \.offset) { index, child in
                if let item = child as? Markdown.ListItem {
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

    private func listMarker(_ item: Markdown.ListItem, index: Int, start: Int?) -> String {
        if let checkbox = item.checkbox { return checkbox == .checked ? "☑" : "☐" }
        if let start { return "\(start + index)." }
        return "•"
    }

    @ViewBuilder
    private func tableView(_ table: Markdown.Table) -> some View {
        let headers = Array(table.head.children)
        let rows = [headers] + table.body.children.map { Array($0.children) }
        let columnCount = max(1, rows.map(\.count).max() ?? 0)
        let cellWidth: CGFloat = 150 + 2 * styleSheet.tableCellPadding
        ScrollView(.horizontal) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, cells in
                    HStack(spacing: 0) {
                        ForEach(0..<columnCount, id: \.self) { columnIndex in
                            Group {
                                if cells.indices.contains(columnIndex) {
                                    inlineView(cells[columnIndex])
                                        .font(rowIndex == 0 ? (styleSheet.tableHeaderFont ?? .body)
                                              : (styleSheet.tableCellFont ?? .body))
                                        .fontWeight(rowIndex == 0 ? .bold : .regular)
                                        .markdownTextSelection(selectable)
                                } else {
                                    SwiftUI.Text("")
                                }
                            }
                                .frame(width: 150, alignment: .leading)
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

    private struct InlineStyle {
        var bold = false
        var italic = false
        var strike = false
        var link: URL?
    }

    private func inline(_ node: Markup) -> SwiftUI.Text {
        var tags: [SafeHTML.Tag] = []
        return inlineChildren(node, style: InlineStyle(), tags: &tags)
    }

    private enum FlowPiece {
        case text(SwiftUI.Text)
        case image(SafeHTML.ImageSpec)
        case math(String)
        case plugin(any InlineParserPlugin, InlinePluginMatch)
        case lineBreak
    }

    private func inlineView(_ node: Markup) -> AnyView {
        let runs = InlineContent.runs(in: node, enableHTML: enableHTML, plugins: plugins)
        let hasImage = runs.contains { if case .image = $0 { return true }; return false }
        let hasFootnote = runs.contains { if case .footnote = $0 { return true }; return false }
        let hasMath = runs.contains { if case .math = $0 { return true }; return false }
        let hasPlugin = runs.contains { if case .plugin = $0 { return true }; return false }
        if !hasImage && !hasFootnote && !hasMath && !hasPlugin {
            return AnyView(inline(node))
        }
        if !hasImage && !hasMath && !hasPlugin {
            var result = SwiftUI.Text("")
            for run in runs {
                switch run {
                case let .text(value, sourceStyle, tags, code):
                    result = result + segment(value, style: inlineStyle(sourceStyle), tags: tags, code: code)
                case let .footnote(label): result = result + footnoteReference(label)
                case .image, .math, .plugin: break
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
                pieces.append(.text(footnoteReference(label)))
            case let .math(latex):
                pieces.append(.math(latex))
            case let .plugin(plugin, match):
                pieces.append(.plugin(plugin, match))
            case let .text(value, sourceStyle, tags, code):
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
                case let .image(image):
                    imageView(image, inline: true)
                        .layoutValue(key: InlineImageKey.self, value: true)
                case let .math(latex):
                    SwiftUIMath.Math(latex)
                        .mathTypesettingStyle(.text)
                        .mathFont(SwiftUIMath.Math.Font(name: .latinModern, size: 16))
                        .fixedSize()
                        .accessibilityLabel(latex)
                case let .plugin(plugin, match):
                    plugin.render(match).fixedSize()
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

    private func blockMath(_ latex: String) -> some View {
        ScrollView(.horizontal) {
            SwiftUIMath.Math(latex)
                .mathTypesettingStyle(.display)
                .mathFont(SwiftUIMath.Math.Font(name: .latinModern, size: 20))
                .fixedSize()
                .accessibilityLabel(latex.isEmpty ? "Empty formula" : latex)
        }
        .defaultScrollAnchor(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private func inlineChildren(_ node: Markup, style: InlineStyle, tags: inout [SafeHTML.Tag]) -> SwiftUI.Text {
        var output = SwiftUI.Text("")
        for child in node.children {
            if let html = child as? InlineHTML {
                if enableHTML, let tag = SafeHTML.lexTag(html.rawHTML), tag.end == (html.rawHTML as NSString).length {
                    if tag.isClosing {
                        if let match = tags.lastIndex(where: { $0.name == tag.name }) { tags.removeSubrange(match...) }
                    } else if SafeHTML.voidTags.contains(tag.name) {
                        if tag.name == "br" { output = output + segment("\n", style: style, tags: tags) }
                        if tag.name == "img" { output = output + segment(tag.attributes["alt"] ?? "", style: style, tags: tags) }
                    } else if !tag.isSelfClosing {
                        tags.append(tag)
                    }
                } else {
                    output = output + segment(html.rawHTML, style: style, tags: tags)
                }
                continue
            }
            if let text = child as? Markdown.Text {
                output = output + segment(text.string, style: style, tags: tags)
            } else if let code = child as? InlineCode {
                output = output + segment(code.code, style: style, tags: tags, code: true)
            } else if child is SoftBreak || child is LineBreak {
                output = output + segment("\n", style: style, tags: tags)
            } else if let image = child as? Markdown.Image {
                output = output + segment(plainText(image), style: style, tags: tags)
            } else {
                var nested = style
                if child is Strong { nested.bold = true }
                if child is Emphasis { nested.italic = true }
                if child is Strikethrough { nested.strike = true }
                if let link = child as? Markdown.Link, let destination = link.destination,
                   let url = URL(string: destination), MarkdownSyntax.isSafeLink(url) { nested.link = url }
                output = output + inlineChildren(child, style: nested, tags: &tags)
            }
        }
        return output
    }

    private func segment(_ value: String, style: InlineStyle, tags: [SafeHTML.Tag], code: Bool = false) -> SwiftUI.Text {
        var bold = style.bold
        var italic = style.italic
        var strike = style.strike
        var htmlUnderline = false
        var htmlCode = false
        var baseline: CGFloat = 0
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
                case "mark": htmlBackground = styleSheet.highlightColor ?? .yellow.opacity(0.4)
                case "sub": baseline = -4
                case "sup": baseline = 4
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
        let inlineStyle = styleSheet.resolvedInlineStyle(bold: bold, italic: italic, strike: strike,
                                                         link: link != nil, code: code || htmlCode)
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
        if htmlUnderline || inlineStyle.underline == true { result = result.underline() }
        if baseline != 0 { result = result.baselineOffset(baseline) }
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
