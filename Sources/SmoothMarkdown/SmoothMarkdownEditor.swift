#if os(iOS)
import Combine
import SwiftUI
import UIKit
import struct Markdown.Paragraph

/// Source editing, live preview, and split view backed by MarkdownEditorController.
@available(iOS 17.0, *)
public struct SmoothMarkdownEditor: View {
    @ObservedObject private var controller: MarkdownEditorController
    @State private var hostIOBusy = false
    @State private var searchOpen = false
    @State private var searchQuery = ""
    @State private var searchIndex = 0
    @State private var searchHasNavigated = false
    @State private var focusMode = false
    @State private var sourceIsComposing = false
    @State private var sourceFocusTracker = MarkdownEditorSourceFocusTracker()
    @State private var performanceReporter = MarkdownEditorPerformanceReporter()
    @FocusState private var searchFieldFocused: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.markdownEditorTheme) private var ambientEditorTheme
    private let editorTheme: MarkdownEditorTheme?
    private let onSave: ((String) -> Void)?
    private let onChanged: ((String) -> Void)?
    private let onModeChanged: ((MarkdownEditorMode) -> Void)?
    private let onSelectionChanged: ((NSRange) -> Void)?
    private let onFocusChanged: ((Bool) -> Void)?
    private let onPerformanceSnapshot: ((MarkdownEditorPerformanceSnapshot) -> Void)?
    private let hostIO: MarkdownEditorHostIO
    private let hasImagePicker: Bool
    private let hasMarkdownImporter: Bool
    private let enableWikilinks: Bool
    private let wikilinkSuggestions: [String]
    private let onTapWikilink: ((String) -> Void)?
    private let capabilities: MarkdownEditorCapabilities
    private let toolbarCommands: [MarkdownEditorCommand]?
    private let showToolbar: Bool
    private let toolbarLeading: [AnyView]
    private let toolbarTrailing: [AnyView]
    private let toolbarBuilder: ((AnyView) -> AnyView)?
    private let customSlashCommands: [MarkdownEditorSlashCommand]
    private let enableSlashCommands: Bool
    private let customBlockMatcher: ((MarkdownDocumentBlock) -> Bool)?
    private let customBlockBuilder: MarkdownEditorCustomBlockBuilder?
    private let customBlockEditorBuilder: MarkdownEditorCustomBlockBuilder?
    private let builderRegistry: BuilderRegistry?

    public init(controller: MarkdownEditorController, onSave: ((String) -> Void)? = nil,
                editorTheme: MarkdownEditorTheme? = nil,
                onChanged: ((String) -> Void)? = nil,
                onModeChanged: ((MarkdownEditorMode) -> Void)? = nil,
                onSelectionChanged: ((NSRange) -> Void)? = nil,
                onFocusChanged: ((Bool) -> Void)? = nil,
                onPerformanceSnapshot: ((MarkdownEditorPerformanceSnapshot) -> Void)? = nil,
                onPickImage: MarkdownEditorHostIO.ImagePicker? = nil,
                onImagePickEvent: ((MarkdownEditorImagePickEvent) -> Void)? = nil,
                onImportMarkdown: MarkdownEditorHostIO.MarkdownImporter? = nil,
                onExportMarkdown: MarkdownEditorHostIO.MarkdownExporter? = nil,
                onExportPDF: MarkdownEditorHostIO.PDFExporter? = nil,
                onHostIOEvent: ((MarkdownEditorHostIOEvent) -> Void)? = nil,
                enableWikilinks: Bool = true,
                wikilinkSuggestions: [String] = [],
                onTapWikilink: ((String) -> Void)? = nil,
                capabilities: MarkdownEditorCapabilities = .all,
                toolbarCommands: [MarkdownEditorCommand]? = nil,
                // Host slots wrap the native command row, following Flutter's toolbar order.
                showToolbar: Bool = true,
                toolbarLeading: [AnyView] = [],
                toolbarTrailing: [AnyView] = [],
                toolbarBuilder: ((AnyView) -> AnyView)? = nil,
                enableSlashCommands: Bool = true,
                customSlashCommands: [MarkdownEditorSlashCommand] = [],
                customBlockMatcher: ((MarkdownDocumentBlock) -> Bool)? = nil,
                customBlockBuilder: MarkdownEditorCustomBlockBuilder? = nil,
                customBlockEditorBuilder: MarkdownEditorCustomBlockBuilder? = nil,
                builderRegistry: BuilderRegistry? = nil) {
        self.controller = controller
        self.onSave = onSave
        self.editorTheme = editorTheme
        self.onChanged = onChanged
        self.onModeChanged = onModeChanged
        self.onSelectionChanged = onSelectionChanged
        self.onFocusChanged = onFocusChanged
        self.onPerformanceSnapshot = onPerformanceSnapshot
        self.hasImagePicker = onPickImage != nil
        self.hasMarkdownImporter = onImportMarkdown != nil
        self.enableWikilinks = enableWikilinks
        self.wikilinkSuggestions = wikilinkSuggestions
        self.onTapWikilink = onTapWikilink
        self.capabilities = capabilities
        self.toolbarCommands = toolbarCommands
        self.showToolbar = showToolbar
        self.toolbarLeading = toolbarLeading
        self.toolbarTrailing = toolbarTrailing
        self.toolbarBuilder = toolbarBuilder
        self.enableSlashCommands = enableSlashCommands
        self.customSlashCommands = customSlashCommands
        self.customBlockMatcher = customBlockMatcher
        self.customBlockBuilder = customBlockBuilder
        self.customBlockEditorBuilder = customBlockEditorBuilder
        self.builderRegistry = builderRegistry
        self.hostIO = MarkdownEditorHostIO(controller: controller, onPickImage: onPickImage,
                                           onImportMarkdown: onImportMarkdown, onExportMarkdown: onExportMarkdown,
                                           onExportPDF: onExportPDF,
                                           onImagePickEvent: onImagePickEvent, onEvent: onHostIOEvent)
    }

    public var body: some View {
        VStack(spacing: 0) {
            if !focusMode {
                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 8) { editorHeaderControls }
                    } else {
                        HStack { editorHeaderControls }
                    }
                }
                .padding(.horizontal)
            }

            if !toolbarLayout.sections.isEmpty { toolbarView }

            if searchOpen || !focusMode {
                HStack {
                    if searchOpen {
                        TextField("Find in note...", text: $searchQuery)
                            .textFieldStyle(.roundedBorder)
                            .focused($searchFieldFocused)
                            .submitLabel(.search)
                            .onSubmit { selectSearchMatch(forward: true) }
                            .accessibilityIdentifier("editor-find-field")
                        Text(searchMatches.isEmpty ? "Not found" : "\(min(searchIndex + 1, searchMatches.count))/\(searchMatches.count)")
                            .font(.caption.monospacedDigit())
                            .accessibilityIdentifier("editor-find-count")
                        Button("Previous", systemImage: "chevron.up") { selectSearchMatch(forward: false) }
                            .disabled(searchMatches.isEmpty)
                            .labelStyle(.iconOnly)
                            .accessibilityIdentifier("editor-find-previous")
                        Button("Next", systemImage: "chevron.down") { selectSearchMatch(forward: true) }
                            .disabled(searchMatches.isEmpty)
                            .labelStyle(.iconOnly)
                            .accessibilityIdentifier("editor-find-next")
                        Button("Close", systemImage: "xmark") { searchOpen = false; searchFieldFocused = false }
                            .labelStyle(.iconOnly)
                            .accessibilityIdentifier("editor-find-close")
                    } else {
                        Spacer()
                        Button("Find", systemImage: "magnifyingglass", action: openSearch)
                            .keyboardShortcut("f", modifiers: .command)
                            .accessibilityIdentifier("editor-find-open")
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 4)
                .background(searchOpen ? (effectiveTheme.searchBarColor ?? .clear) : .clear)
            }

            if focusMode || searchOpen {
                // Keep the keyboard command active when Focus hides the toolbar or Find is open.
                Button("Find in note", action: openSearch)
                    .keyboardShortcut("f", modifiers: .command)
                    .frame(width: 0, height: 0)
                    .opacity(0)
                    .accessibilityHidden(true)
            }

            Divider().overlay(effectiveTheme.dividerColor ?? .clear)
            ZStack(alignment: .topTrailing) {
                Group {
                    switch controller.mode {
                    case .source:
                        sourceTextView
                    case .formatted:
                        FormattedBlocksView(controller: controller, enableWikilinks: enableWikilinks,
                                            wikilinkSuggestions: wikilinkSuggestions,
                                            capabilities: capabilities,
                                            enableSlashCommands: enableSlashCommands,
                                            customSlashCommands: customSlashCommands,
                                            contentPadding: effectiveTheme.contentPadding,
                                            customBlockMatcher: customBlockMatcher,
                                            customBlockBuilder: customBlockBuilder,
                                            customBlockEditorBuilder: customBlockEditorBuilder)
                            .environment(\.markdownEditorTheme, effectiveTheme)
                    case .preview:
                        previewView
                    case .split:
                        GeometryReader { geometry in
                            VStack(spacing: 0) {
                                sourceTextView
                                    .frame(height: geometry.size.height / 2)
                                Divider().overlay(effectiveTheme.dividerColor ?? .clear)
                                previewView
                                    .frame(height: geometry.size.height / 2)
                            }
                        }
                    }
                }
                if focusMode {
                    // iPhone users need a touch exit while the normal toolbar is hidden.
                    focusToggle
                        .padding(8)
                        .background(.regularMaterial, in: Circle())
                        .padding(8)
                }
            }
        }
        .onChange(of: searchQuery) { _, _ in
            searchIndex = 0
            searchHasNavigated = false
            schedulePerformanceSnapshot()
        }
        .onReceive(controller.committedTextChanges) { next in
            searchIndex = 0
            searchHasNavigated = false
            onChanged?(next)
        }
        .onReceive(controller.$mode.dropFirst().removeDuplicates()) { next in onModeChanged?(next) }
        .onReceive(controller.$selection.dropFirst().removeDuplicates()) { next in onSelectionChanged?(next) }
        .onReceive(controller.$text.dropFirst()) { _ in schedulePerformanceSnapshot() }
        .onReceive(controller.$mode.dropFirst()) { _ in schedulePerformanceSnapshot() }
        .onReceive(controller.$selection.dropFirst()) { _ in schedulePerformanceSnapshot() }
        .onDisappear {
            sourceFocusTracker.setFocused(false, callback: onFocusChanged)
            performanceReporter.cancel()
        }
        .background(effectiveTheme.editorBackgroundColor ?? .clear)
        .modifier(EditorOptionalCornerRadius(radius: effectiveTheme.editorBorderRadius))
        .overlay {
            if let color = effectiveTheme.editorBorderColor {
                RoundedRectangle(cornerRadius: max(0, effectiveTheme.editorBorderRadius ?? 0))
                    .stroke(color)
                    .allowsHitTesting(false)
            }
        }
    }

    private var sourceTextView: some View {
        SourceTextView(controller: controller, theme: effectiveTheme,
                       onFocusChanged: { focused in
                           sourceFocusTracker.setFocused(focused, callback: onFocusChanged)
                       },
                       onCompositionChanged: { composing in
                           guard sourceIsComposing != composing else { return }
                           sourceIsComposing = composing
                           schedulePerformanceSnapshot()
                       })
    }

    private var effectiveTheme: MarkdownEditorTheme {
        ambientEditorTheme.merging(editorTheme)
    }

    private var previewView: some View {
        SmoothMarkdownView(markdown: controller.text, plugins: previewPlugins,
                           builderRegistry: builderRegistry)
            .padding(effectiveTheme.previewPadding ?? EdgeInsets())
            .background(effectiveTheme.previewBackgroundColor ?? .clear)
    }

    private func schedulePerformanceSnapshot() {
        guard let onPerformanceSnapshot else { return }
        let query = searchQuery
        let composing = sourceIsComposing
        performanceReporter.schedule(snapshot: {
            performanceReporter.capture(controller: controller, searchQuery: query,
                                        isComposing: composing)
        }, callback: onPerformanceSnapshot)
    }

    @ViewBuilder
    private var editorHeaderControls: some View {
        Picker("Mode", selection: $controller.mode) {
            ForEach(MarkdownEditorMode.allCases, id: \.self) { mode in
                Text(mode == .formatted ? "Blocks" : mode.rawValue.capitalized).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        focusToggle
        Menu("File") {
            if hasImagePicker {
                Button("Insert Image") { runHostIO { await hostIO.pickImage() } }
            }
            if hasMarkdownImporter {
                Button("Import Markdown") { runHostIO { await hostIO.importMarkdown() } }
            }
            Button("Export Markdown") { runHostIO { await hostIO.exportMarkdown() } }
            Button("Export PDF") { runHostIO { await hostIO.exportPDF() } }
        }
        .disabled(hostIOBusy)
        if let onSave {
            Button("Save") {
                onSave(controller.text)
                controller.markSaved()
            }
            .disabled(!controller.isDirty)
        }
    }

    private var searchMatches: [NSRange] { controller.findMatches(searchQuery) }

    private var focusToggle: some View {
        Button(focusMode ? "Exit Focus" : "Focus",
               systemImage: focusMode ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right") {
            focusMode.toggle()
        }
        .labelStyle(.iconOnly)
        .keyboardShortcut(.return, modifiers: [.command, .shift])
        .accessibilityIdentifier("editor-focus-toggle")
    }

    private func openSearch() {
        searchOpen = true
        searchFieldFocused = true
    }

    private func selectSearchMatch(forward: Bool) {
        let matches = searchMatches
        guard !matches.isEmpty else { return }
        if searchHasNavigated {
            searchIndex = (searchIndex + (forward ? 1 : matches.count - 1)) % matches.count
        } else {
            searchIndex = forward ? 0 : matches.count - 1
            searchHasNavigated = true
        }
        controller.mode = .source
        controller.setSelection(matches[searchIndex])
        searchFieldFocused = false
    }

    private var previewPlugins: ParserPluginRegistry? {
        let registry = controller.parserPlugins ?? ParserPluginRegistry()
        if enableWikilinks {
            let builtIns = ParserPluginRegistry.builtIns()
            for plugin in builtIns.blockPlugins where registry.getBlockPlugin(plugin.id) == nil {
                try? registry.register(plugin)
            }
            for plugin in builtIns.inlinePlugins where registry.getInlinePlugin(plugin.id) == nil {
                try? registry.register(plugin)
            }
            if registry.getInlinePlugin("wikilink") == nil {
                try? registry.register(WikilinkPlugin(onTapWikilink: onTapWikilink))
            }
        }
        guard !registry.blockPlugins.isEmpty || !registry.inlinePlugins.isEmpty else { return nil }
        return registry
    }

    private func commandButton(_ title: String, _ command: MarkdownEditorCommand) -> some View {
        Button(title) {
            guard capabilities.supports(command), command != .wikilink || enableWikilinks else { return }
            controller.applyCommand(command)
        }
            .padding(.horizontal, 5)
    }

    private var visibleToolbarCommands: [MarkdownEditorCommand] {
        capabilities.visibleToolbarCommands(toolbarCommands, enableWikilinks: enableWikilinks)
    }

    private var toolbarLayout: MarkdownEditorToolbarLayout {
        .init(showToolbar: showToolbar, focusMode: focusMode,
              leadingCount: toolbarLeading.count, trailingCount: toolbarTrailing.count)
    }

    private var toolbarView: AnyView {
        let defaultToolbar = AnyView(ScrollView(.horizontal) {
            HStack(spacing: dynamicTypeSize.isAccessibilitySize ? 12 : 8) {
                ForEach(toolbarLayout.sections, id: \.self) { section in
                    switch section {
                    case .leading(let index): toolbarLeading[index]
                    case .history:
                        Button("Undo") { controller.undo() }.disabled(!controller.canUndo)
                        Button("Redo") { controller.redo() }.disabled(!controller.canRedo)
                    case .commands:
                        if controller.mode != .formatted {
                            ForEach(visibleToolbarCommands, id: \.self) { command in
                                commandButton(command.toolbarTitle, command)
                            }
                        }
                    case .trailing(let index): toolbarTrailing[index]
                    }
                }
            }
            .buttonStyle(.borderless)
            .padding(.horizontal)
            .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? 8 : 0)
        }
        .frame(minHeight: 44)
        .foregroundStyle(effectiveTheme.toolbarIconColor ?? .primary)
        .background(effectiveTheme.toolbarColor ?? .clear))
        return toolbarBuilder?(defaultToolbar) ?? defaultToolbar
    }

    private func runHostIO(_ work: @escaping () async -> Bool) {
        guard !hostIOBusy else { return }
        hostIOBusy = true
        Task { @MainActor in
            _ = await work()
            hostIOBusy = false
        }
    }
}

@available(iOS 17.0, *)
private struct EditorOptionalCornerRadius: ViewModifier {
    let radius: CGFloat?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let radius {
            content.clipShape(RoundedRectangle(cornerRadius: max(0, radius)))
        } else {
            content
        }
    }
}

@available(iOS 17.0, *)
private struct EditorSlashCommand {
    let title: String
    let searchText: String
    let command: MarkdownEditorCommand?
    let customCommand: MarkdownEditorSlashCommand?

    init(title: String, searchText: String, command: MarkdownEditorCommand) {
        self.title = title
        self.searchText = searchText
        self.command = command
        self.customCommand = nil
    }

    init(custom: MarkdownEditorSlashCommand) {
        self.title = custom.title
        self.searchText = custom.searchText
        self.command = nil
        self.customCommand = custom
    }

    static let builtIns: [Self] = [
        .init(title: "Text", searchText: "paragraph body plain normal", command: .paragraph),
        .init(title: "Heading 1", searchText: "heading h1 title", command: .heading1),
        .init(title: "Heading 2", searchText: "h2 heading subtitle", command: .heading2),
        .init(title: "Heading 3", searchText: "h3 heading", command: .heading3),
        .init(title: "Heading 4", searchText: "heading h4", command: .heading4),
        .init(title: "Heading 5", searchText: "heading h5", command: .heading5),
        .init(title: "Heading 6", searchText: "heading h6", command: .heading6),
        .init(title: "Bullet List", searchText: "bullet unordered ul list", command: .unorderedList),
        .init(title: "Numbered List", searchText: "number ordered ol list numbered", command: .orderedList),
        .init(title: "Task List", searchText: "todo checklist checkbox task", command: .taskList),
        .init(title: "Blockquote", searchText: "blockquote quote", command: .blockquote),
        .init(title: "Code Block", searchText: "code fenced block pre", command: .codeBlock),
        .init(title: "Mermaid Diagram", searchText: "mermaid diagram flowchart chart", command: .mermaidDiagram),
        .init(title: "Block Math", searchText: "math equation", command: .blockMath),
        .init(title: "Horizontal Rule", searchText: "divider separator hr line horizontal rule", command: .horizontalRule),
        .init(title: "Image", searchText: "picture photo img", command: .image),
        .init(title: "Table", searchText: "table grid", command: .table),
        .init(title: "Wikilink", searchText: "wiki note link wikilink [[", command: .wikilink),
    ]
}

@available(iOS 17.0, *)
private struct FormattedBlocksView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.markdownEditorTheme) private var editorTheme
    @ObservedObject var controller: MarkdownEditorController
    let enableWikilinks: Bool
    let wikilinkSuggestions: [String]
    let capabilities: MarkdownEditorCapabilities
    let enableSlashCommands: Bool
    let customSlashCommands: [MarkdownEditorSlashCommand]
    let contentPadding: EdgeInsets?
    let customBlockMatcher: ((MarkdownDocumentBlock) -> Bool)?
    let customBlockBuilder: MarkdownEditorCustomBlockBuilder?
    let customBlockEditorBuilder: MarkdownEditorCustomBlockBuilder?
    @State private var rangeStartID: String?
    @State private var rangeEndID: String?
    @State private var textRangeStart: MarkdownSemanticTextPosition?
    @State private var textRangeEnd: MarkdownSemanticTextPosition?
    @State private var textRangeSource: String?
    @State private var copiedRange = false
    @State private var showingEditingTips = false
    @State private var textRangeLinkDestination = "https://"
    @State private var showingTextRangeLinkEditor = false
    @State private var visibleTextRange: MarkdownVisibleTextSelection?
    @State private var visibleLinkDestination = "https://"
    @State private var showingVisibleLinkEditor = false

    private var textRange: MarkdownSemanticTextSelection? {
        guard let textRangeStart, let textRangeEnd else { return nil }
        return .init(anchor: textRangeStart, focus: textRangeEnd, source: textRangeSource)
    }

    private var textHighlights: [String: NSRange] {
        guard let textRange else { return [:] }
        return controller.semanticTextHighlightRanges(textRange) ?? [:]
    }

    private var listItemHighlights: [String: MarkdownEditorController.ListLineHighlights] {
        guard let textRange else { return [:] }
        return controller.semanticListLineHighlightRanges(textRange) ?? [:]
    }

    private var tableCellHighlights: [String: [Int: [Int: NSRange]]] {
        guard let textRange else { return [:] }
        return controller.semanticTableCellHighlightRanges(textRange) ?? [:]
    }

    private var visibleHighlights: [String: NSRange] {
        guard let selected = visibleTextRange, selected.source == controller.text else { return [:] }
        let blocks = controller.semanticDocument.blocks
        guard let anchor = blocks.firstIndex(where: { $0.id == selected.anchor.blockID }),
              let focus = blocks.firstIndex(where: { $0.id == selected.focus.blockID }) else { return [:] }
        let first = min(anchor, focus)
        let last = max(anchor, focus)
        let forward = anchor < focus || (anchor == focus && selected.anchor.offset <= selected.focus.offset)
        let start = forward ? selected.anchor.offset : selected.focus.offset
        let end = forward ? selected.focus.offset : selected.anchor.offset
        var highlights: [String: NSRange] = [:]
        for index in first...last {
            let block = blocks[index]
            switch block.kind {
            case .paragraph, .heading: break
            default: return [:]
            }
            guard let length = MarkdownInlineMarkEditor.visibleUTF16Length(of: block.plainText) else { return [:] }
            let lower = index == first ? start : 0
            let upper = index == last ? end : length
            guard lower >= 0, upper >= lower, upper <= length else { return [:] }
            highlights[block.id] = NSRange(location: lower, length: upper - lower)
        }
        return highlights
    }

    private enum Row: Identifiable {
        case block(MarkdownDocumentBlock)
        case pendingParagraph

        var id: String {
            switch self {
            case let .block(block): "block-\(block.id)"
            case .pendingParagraph: "pending-list-paragraph"
            }
        }
    }

    private var rows: [Row] {
        let document = controller.semanticDocument
        guard let pending = controller.pendingListParagraph else {
            return document.blocks.map(Row.block)
        }
        var result: [Row] = []
        var insertedPending = false
        for block in document.blocks {
            let start = document.sourceRange(of: block.id)?.location ?? Int.max
            if !insertedPending && pending.sourceOffset <= start {
                result.append(.pendingParagraph)
                insertedPending = true
            }
            if !pending.draft.isEmpty, start == pending.sourceOffset {
                continue // The focused field owns this source-backed block until it resigns focus.
            }
            result.append(.block(block))
        }
        if !insertedPending { result.append(.pendingParagraph) }
        return result
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if dynamicTypeSize.isAccessibilitySize {
                    DisclosureGroup("Editing tips", isExpanded: $showingEditingTips) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Select rendered text in a heading or paragraph to format it. Open Edit Markdown for raw editing and other actions.")
                            Text("Tap Start range on a block, then End range on another block.")
                            Text("Select text in prose, code, or a table cell, then use Start and End at selection. Long press and drag between text blocks also works.")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Select rendered text in a heading or paragraph to format it. Open Edit Markdown for raw editing and other actions.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 6) {
                    if !dynamicTypeSize.isAccessibilitySize || rangeStartID != nil {
                        Text(rangeStartID == nil ? "Tap Start range on a block, then End range on another block." :
                             rangeEndID == nil ? "Choose the last block in the range." : "Block range selected.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 8) {
                        if let rangeStartID, let rangeEndID {
                            Button("Copy Markdown") {
                                if let copied = controller.copySemanticBlockRange(from: rangeStartID, to: rangeEndID) {
                                    UIPasteboard.general.string = copied
                                    copiedRange = true
                                }
                            }
                            .accessibilityIdentifier("block-range-copy")
                            Button("Delete blocks", role: .destructive) {
                                if controller.deleteSemanticBlockRange(from: rangeStartID, to: rangeEndID) {
                                    clearRange()
                                }
                            }
                            .disabled(!controller.canDeleteSemanticBlockRange(from: rangeStartID, to: rangeEndID))
                            .accessibilityIdentifier("block-range-delete")
                        }
                        if rangeStartID != nil {
                            Button("Clear range") { clearRange() }
                                .accessibilityIdentifier("block-range-clear")
                        }
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                }
                VStack(alignment: .leading, spacing: 6) {
                    if !dynamicTypeSize.isAccessibilitySize {
                        Text("Select text in prose, code, or a table cell. Use Start and End at selection across blocks.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 8) {
                        if let textRange {
                            Menu("Format text range") {
                                if capabilities.supports(.bold) {
                                    Button("Bold") { _ = controller.applySemanticInlineMarkToTextRange(textRange, mark: .bold) }
                                }
                                if capabilities.supports(.italic) {
                                    Button("Italic") { _ = controller.applySemanticInlineMarkToTextRange(textRange, mark: .italic) }
                                }
                                if capabilities.supports(.strikethrough) {
                                    Button("Strikethrough") {
                                        _ = controller.applySemanticInlineMarkToTextRange(textRange, mark: .strikethrough)
                                    }
                                }
                                if capabilities.supports(.inlineCode) {
                                    Button("Inline code") { _ = controller.applySemanticInlineMarkToTextRange(textRange, mark: .code) }
                                }
                                if capabilities.supports(.link) {
                                    Button("Link") { showingTextRangeLinkEditor = true }
                                }
                            }
                            .accessibilityIdentifier("text-range-format")
                            .disabled(!controller.canApplySemanticInlineMarkToTextRange(textRange))
                            Button("Copy text range") {
                                if let copied = controller.copySemanticTextRange(textRange) {
                                    UIPasteboard.general.string = copied
                                    copiedRange = true
                                }
                            }
                            .accessibilityIdentifier("text-range-copy")
                            Button("Delete text range", role: .destructive) {
                                if controller.deleteSemanticTextRange(textRange) { clearRange() }
                            }
                            .disabled(!controller.canReplaceSemanticTextRange(textRange))
                            .accessibilityIdentifier("text-range-delete")
                            Button("Replace from clipboard") {
                                if let value = UIPasteboard.general.string,
                                   controller.replaceSemanticTextRange(textRange, with: value) {
                                    clearRange()
                                }
                            }
                            .accessibilityIdentifier("text-range-replace")
                        }
                        if textRangeStart != nil {
                            Button("Clear text range") { clearRange() }
                                .accessibilityIdentifier("text-range-clear")
                        }
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                }
                if let selected = visibleTextRange, selected.source == controller.text {
                    HStack(spacing: 8) {
                        Menu("Format rendered selection") {
                            if capabilities.supports(.bold) {
                                Button("Bold") { applyVisibleMark(.bold, to: selected) }
                            }
                            if capabilities.supports(.italic) {
                                Button("Italic") { applyVisibleMark(.italic, to: selected) }
                            }
                            if capabilities.supports(.strikethrough) {
                                Button("Strikethrough") { applyVisibleMark(.strikethrough, to: selected) }
                            }
                            if capabilities.supports(.inlineCode) {
                                Button("Inline code") { applyVisibleMark(.code, to: selected) }
                            }
                            if capabilities.supports(.link) {
                                Button("Link") { showingVisibleLinkEditor = true }
                            }
                            Divider()
                            Button("Copy Markdown") {
                                if let copied = controller.copyVisibleTextRange(selected) {
                                    UIPasteboard.general.string = copied
                                    copiedRange = true
                                }
                            }
                            .accessibilityIdentifier("visible-range-copy")
                            Button("Delete selected text", role: .destructive) {
                                if controller.deleteVisibleTextRange(selected) { clearRange() }
                            }
                            .disabled(!controller.canReplaceVisibleTextRange(selected))
                            .accessibilityIdentifier("visible-range-delete")
                            Button("Replace with plain text from clipboard") {
                                if let value = UIPasteboard.general.string,
                                   controller.replaceVisibleTextRange(selected, with: value) {
                                    clearRange()
                                }
                            }
                            .disabled(UIPasteboard.general.string.map {
                                !controller.canReplaceVisibleTextRange(selected, with: $0)
                            } ?? true)
                            .accessibilityIdentifier("visible-range-replace")
                            Button("Edit Markdown in Source mode") {
                                controller.mode = .source
                                clearRange()
                            }
                            .accessibilityIdentifier("visible-range-source-fallback")
                        }
                        .accessibilityIdentifier("visible-range-format")
                        Text("Rendered characters selected")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .buttonStyle(.bordered)
                }
                if copiedRange {
                    Text("Markdown copied")
                        .font(.caption)
                        .accessibilityIdentifier("block-range-copy-feedback")
                }
                ForEach(rows) { row in
                    switch row {
                    case let .block(block):
                        VStack(alignment: .leading, spacing: 2) {
                            Button(rangeStartID == nil ? "Start range" : "End range") {
                                if rangeStartID == nil || rangeEndID != nil {
                                    rangeStartID = block.id
                                    rangeEndID = nil
                                } else if rangeStartID != block.id {
                                    rangeEndID = block.id
                                }
                                copiedRange = false
                            }
                            .font(.caption)
                            .accessibilityIdentifier("block-range-\(block.id)")
                            FormattedBlockRow(controller: controller, block: block,
                                              enableWikilinks: enableWikilinks,
                                              wikilinkSuggestions: wikilinkSuggestions,
                                              capabilities: capabilities,
                                              enableSlashCommands: enableSlashCommands,
                                              customSlashCommands: customSlashCommands,
                                              customBlockMatcher: customBlockMatcher,
                                              customBlockBuilder: customBlockBuilder,
                                              customBlockEditorBuilder: customBlockEditorBuilder,
                                              crossBlockHighlight: textHighlights[block.id],
                                              listItemHighlights: listItemHighlights[block.id],
                                              tableCellHighlights: tableCellHighlights[block.id],
                                              visibleCrossBlockHighlight: visibleHighlights[block.id],
                                              onCrossBlockDrag: { selection in
                        guard controller.copySemanticTextRange(selection) != nil else { return }
                        textRangeStart = selection.anchor
                        textRangeEnd = selection.focus
                        textRangeSource = controller.text
                        copiedRange = false
                    },
                                              onVisibleSelection: { range in
                        guard range.length > 0 else { return }
                        visibleTextRange = .init(source: controller.text,
                                                 anchor: .init(blockID: block.id, offset: range.location),
                                                 focus: .init(blockID: block.id, offset: NSMaxRange(range)))
                    },
                                              onVisibleCrossBlockDrag: { anchor, focus in
                        visibleTextRange = .init(source: controller.text, anchor: anchor, focus: focus)
                    },
                                              onCaptureTextPosition: { position, isStart in
                        if isStart {
                            textRangeStart = position
                            textRangeEnd = nil
                            textRangeSource = controller.text
                        } else {
                            textRangeEnd = position
                        }
                        copiedRange = false
                    }, onCaptureListTextPosition: { position, isStart in
                        if isStart {
                            textRangeStart = position
                            textRangeEnd = nil
                            textRangeSource = controller.text
                        } else {
                            textRangeEnd = position
                        }
                        copiedRange = false
                    })
                        }
                        .padding(4)
                        .background(isInSelectedRange(block.id) ?
                                    (editorTheme.selectionColor ?? Color.accentColor.opacity(0.12)) : .clear,
                                    in: RoundedRectangle(cornerRadius: 9))
                    case .pendingParagraph:
                        PendingListParagraphField(controller: controller)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(contentPadding ?? EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
        }
        .alert("Link URL", isPresented: $showingTextRangeLinkEditor) {
            TextField("https://example.com", text: $textRangeLinkDestination)
                .textInputAutocapitalization(.never)
            Button("Apply") {
                if let textRange {
                    _ = controller.applySemanticInlineMarkToTextRange(
                        textRange, mark: .link(destination: textRangeLinkDestination))
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Only http, https, mailto, and tel links are accepted.")
        }
        .alert("Rendered link URL", isPresented: $showingVisibleLinkEditor) {
            TextField("https://example.com", text: $visibleLinkDestination)
                .textInputAutocapitalization(.never)
            Button("Apply") {
                if let selected = visibleTextRange {
                    applyVisibleMark(.link(destination: visibleLinkDestination), to: selected)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Only safe Markdown link destinations are accepted.")
        }
        .onChange(of: controller.text) { _, _ in clearRange() }
    }

    private func applyVisibleMark(_ mark: MarkdownInlineMark, to selected: MarkdownVisibleTextSelection) {
        if controller.applySemanticInlineMarkToVisibleTextRange(selected, mark: mark) {
            visibleTextRange = nil
        }
    }

    private func clearRange() {
        rangeStartID = nil
        rangeEndID = nil
        textRangeStart = nil
        textRangeEnd = nil
        textRangeSource = nil
        visibleTextRange = nil
        copiedRange = false
    }

    private func isInSelectedRange(_ id: String) -> Bool {
        guard let rangeStartID, let rangeEndID else { return id == rangeStartID }
        let blocks = controller.semanticDocument.blocks
        guard let start = blocks.firstIndex(where: { $0.id == rangeStartID }),
              let end = blocks.firstIndex(where: { $0.id == rangeEndID }),
              let index = blocks.firstIndex(where: { $0.id == id }) else { return false }
        return (min(start, end)...max(start, end)).contains(index)
    }
}

/// The field has a stable row identity while its first keystroke becomes a parsed paragraph.
@available(iOS 17.0, *)
private struct PendingListParagraphField: UIViewRepresentable {
    @ObservedObject var controller: MarkdownEditorController

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.textChanged(_:)), for: .editingChanged)
        field.font = .preferredFont(forTextStyle: .body)
        field.adjustsFontForContentSizeCategory = true
        field.placeholder = "Paragraph"
        field.accessibilityIdentifier = "list-exit-paragraph"
        field.text = controller.pendingListParagraph?.draft
        field.borderStyle = .roundedRect
        let controller = controller
        DispatchQueue.main.async { [weak field] in
            guard controller.pendingListParagraph != nil else { return }
            field?.becomeFirstResponder()
        }
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.parent = self
        let draft = controller.pendingListParagraph?.draft ?? ""
        if field.text != draft { field.text = draft }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: PendingListParagraphField
        init(parent: PendingListParagraphField) { self.parent = parent }

        @objc func textChanged(_ field: UITextField) {
            guard parent.controller.updatePendingListParagraph(field.text ?? "") else {
                field.text = parent.controller.pendingListParagraph?.draft ?? ""
                return
            }
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            return false
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            parent.controller.finishPendingListParagraph()
        }
    }
}

@available(iOS 17.0, *)
private struct FormattedBlockRow: View {
    private struct CodeLanguageOption: Identifiable {
        let id: String
        let title: String
    }

    /// Matches the language picker in Flutter's formatted code block header.
    private static let codeLanguages: [CodeLanguageOption] = [
        .init(id: "", title: "Plain text"), .init(id: "javascript", title: "JavaScript"),
        .init(id: "typescript", title: "TypeScript"), .init(id: "python", title: "Python"),
        .init(id: "rust", title: "Rust"), .init(id: "json", title: "JSON"),
        .init(id: "sql", title: "SQL"), .init(id: "css", title: "CSS"),
        .init(id: "html", title: "HTML"), .init(id: "bash", title: "Bash"),
        .init(id: "markdown", title: "Markdown"), .init(id: "yaml", title: "YAML"),
        .init(id: "go", title: "Go"), .init(id: "java", title: "Java"),
        .init(id: "cpp", title: "C++"), .init(id: "c", title: "C"),
        .init(id: "swift", title: "Swift"), .init(id: "ruby", title: "Ruby"),
        .init(id: "php", title: "PHP"), .init(id: "diff", title: "Diff"),
        .init(id: "dockerfile", title: "Dockerfile"), .init(id: "mermaid", title: "Mermaid"),
    ]

    @Environment(\.markdownEditorTheme) private var editorTheme
    @ObservedObject var controller: MarkdownEditorController
    let block: MarkdownDocumentBlock
    let enableWikilinks: Bool
    let wikilinkSuggestions: [String]
    let capabilities: MarkdownEditorCapabilities
    let enableSlashCommands: Bool
    let customSlashCommands: [MarkdownEditorSlashCommand]
    let customBlockMatcher: ((MarkdownDocumentBlock) -> Bool)?
    let customBlockBuilder: MarkdownEditorCustomBlockBuilder?
    let customBlockEditorBuilder: MarkdownEditorCustomBlockBuilder?
    let crossBlockHighlight: NSRange?
    let listItemHighlights: [Int: NSRange]?
    let tableCellHighlights: [Int: [Int: NSRange]]?
    let visibleCrossBlockHighlight: NSRange?
    let onCrossBlockDrag: (MarkdownSemanticTextSelection) -> Void
    let onVisibleSelection: (NSRange) -> Void
    let onVisibleCrossBlockDrag: (MarkdownVisibleTextPosition, MarkdownVisibleTextPosition) -> Void
    let onCaptureTextPosition: (MarkdownSemanticTextPosition, Bool) -> Void
    let onCaptureListTextPosition: (MarkdownSemanticTextPosition, Bool) -> Void
    @State private var customBlockEditing = false
    @State private var customBlockExpectedText: String?
    @State private var inlineSelection = NSRange(location: 0, length: 0)
    @State private var wikilinkSelectedIndex = 0
    @State private var slashSelectedIndex = 0
    @State private var linkDestination = "https://"
    @State private var showLinkEditor = false
    @State private var editingMarkdown = false

    private var hasWholeBlockTextRangeHighlight: Bool {
        guard crossBlockHighlight != nil else { return false }
        switch block.kind {
        case .paragraph, .heading: return false
        case .list: return listItemHighlights == nil
        case .fencedCode: return false
        case .table: return tableCellHighlights == nil
        case .horizontalRule, .plugin, .raw: return true
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let customBlockView {
                customBlockView
            } else {
            switch block.kind {
            case let .heading(level, _):
                blockLabel("Heading \(level)")
                let font = UIFontMetrics(forTextStyle: headingTextStyle(level))
                    .scaledFont(for: .systemFont(ofSize: CGFloat(32 - (level - 1) * 3), weight: .bold))
                proseContent(font: font, rawIdentifier: "heading-\(block.id)",
                             visibleIdentifier: "rendered-heading-\(block.id)")
            case .paragraph:
                blockLabel("Paragraph")
                proseContent(font: .preferredFont(forTextStyle: .body), rawIdentifier: "paragraph-\(block.id)",
                             visibleIdentifier: "rendered-paragraph-\(block.id)")
            case let .fencedCode(_, info, _):
                HStack {
                    blockLabel("Code")
                    Spacer(minLength: 8)
                    codeLanguageMenu(info: info)
                }
                HStack(spacing: 8) {
                    Button("Start at code selection") {
                        onCaptureTextPosition(.init(blockID: block.id, offset: inlineSelection.location), true)
                    }
                    .accessibilityIdentifier("code-range-start-\(block.id)")
                    Button("End at code selection") {
                        onCaptureTextPosition(.init(blockID: block.id, offset: NSMaxRange(inlineSelection)), false)
                    }
                    .accessibilityIdentifier("code-range-end-\(block.id)")
                }
                .font(.caption)
                .buttonStyle(.bordered)
                SemanticInlineTextView(
                    text: controller.semanticDocument.blockById(block.id)?.plainText ?? block.plainText,
                    selectedRange: inlineSelection,
                    font: .preferredFont(forTextStyle: .body),
                    identifier: "code-\(block.id)", blockID: block.id,
                    crossBlockHighlight: crossBlockHighlight,
                    onEdit: { controller.replaceSemanticBlockContent(id: block.id, with: $0) },
                    onStructuredPaste: { _, _ in false },
                    onSelection: { inlineSelection = $0 },
                    onCrossBlockDrag: onCrossBlockDrag,
                    suggestionsVisible: false,
                    onSuggestionKey: { _ in }, isCode: true)
                    .frame(minHeight: 120)
            case let .table(table):
                FormattedTableView(controller: controller, blockID: block.id, table: table,
                                   textHighlights: tableCellHighlights,
                                   onCaptureTextPosition: onCaptureTextPosition)
            case let .list(list):
                FormattedListView(controller: controller, blockID: block.id, list: list,
                                  textHighlights: listItemHighlights,
                                  onCaptureTextPosition: onCaptureListTextPosition)
            case .horizontalRule:
                blockLabel("Divider")
                Divider()
            case .plugin, .raw:
                blockLabel("Source only")
                Text(block.source.trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(4)
                    .textSelection(.enabled)
                Button("Edit source") {
                    if let range = controller.semanticDocument.sourceRange(of: block.id) {
                        controller.setSelection(range)
                    }
                    controller.mode = .source
                }
                .font(.caption)
            }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(editorTheme.blockPadding ?? EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
        .background(hasWholeBlockTextRangeHighlight ?
                    (editorTheme.selectionColor ?? Color.accentColor).opacity(0.22) :
                    Color(uiColor: .secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: max(0, editorTheme.blockBorderRadius ?? 8)))
        .overlay {
            if let color = editorTheme.blockBorderColor {
                RoundedRectangle(cornerRadius: max(0, editorTheme.blockBorderRadius ?? 8))
                    .stroke(color)
                    .allowsHitTesting(false)
            }
        }
        .alert("Link URL", isPresented: $showLinkEditor) {
            TextField("https://example.com", text: $linkDestination)
                .textInputAutocapitalization(.never)
            Button("Apply") { apply(.link(destination: linkDestination)) }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Only http, https, mailto, and tel links are accepted.")
        }
        .onChange(of: controller.text) { _, _ in
            wikilinkSelectedIndex = 0
            slashSelectedIndex = 0
        }
    }

    private func codeLanguageMenu(info: String) -> some View {
        let current = info.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
        let known = Self.codeLanguages.first { $0.id == current }
        let title = known?.title ?? current
        return Menu {
            if known == nil {
                Button("Current: \(current)") { }.disabled(true)
            }
            ForEach(Self.codeLanguages) { option in
                Button {
                    if option.id != current { _ = controller.setCodeBlockLanguage(id: block.id, to: option.id) }
                } label: {
                    if option.id == current {
                        Label(option.title, systemImage: "checkmark")
                    } else {
                        Text(option.title)
                    }
                }
                .accessibilityIdentifier("code-language-choice-\(option.id.isEmpty ? "plain" : option.id)")
            }
        } label: {
            Text(title)
                .font(.caption)
                .lineLimit(1)
        }
        .accessibilityLabel("Code language: \(title)")
        .accessibilityIdentifier("code-language-\(block.id)")
    }

    private var customBlockView: AnyView? {
        let matched: Bool
        if let customBlockMatcher {
            matched = customBlockMatcher(block)
        } else if case .plugin = block.kind {
            matched = true
        } else {
            matched = false
        }
        guard matched else { return nil }
        let expectedText = customBlockEditing ? (customBlockExpectedText ?? "") : controller.text
        let context = MarkdownEditorCustomBlockContext(
            blockID: block.id, blockKind: block.kind, markdown: block.source,
            plainText: block.plainText, isEditing: customBlockEditing,
            edit: {
                customBlockExpectedText = controller.text
                customBlockEditing = true
            },
            replaceMarkdown: { markdown in
                let changed = controller.replaceCustomBlockMarkdown(id: block.id, expectedText: expectedText,
                                                                    with: markdown)
                if changed {
                    customBlockEditing = false
                    customBlockExpectedText = nil
                }
                return changed
            },
            finishEditing: {
                customBlockEditing = false
                customBlockExpectedText = nil
            },
            delete: {
                let changed = controller.deleteCustomBlock(id: block.id, expectedText: expectedText)
                if changed {
                    customBlockEditing = false
                    customBlockExpectedText = nil
                }
                return changed
            })
        if customBlockEditing, let editor = customBlockEditorBuilder?(context) { return editor }
        return customBlockBuilder?(context)
    }

    private var activeSlashMatch: MarkdownSlashCommandMatch? {
        enableSlashCommands ? controller.slashCommandMatch(inBlock: block.id, selection: inlineSelection) : nil
    }

    private var visibleSlashCommands: [EditorSlashCommand] {
        guard let match = activeSlashMatch else { return [] }
        let all = EditorSlashCommand.builtIns.filter {
            ($0.command.map { capabilities.supports($0) && ($0 != .wikilink || enableWikilinks) } ?? true)
        } + customSlashCommands.map(EditorSlashCommand.init(custom:))
        return all.filter {
            match.query.isEmpty || $0.title.localizedCaseInsensitiveContains(match.query)
                || $0.searchText.localizedCaseInsensitiveContains(match.query)
        }
    }

    @ViewBuilder
    private var slashSuggestionPanel: some View {
        if activeSlashMatch != nil, !visibleSlashCommands.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Slash command suggestions")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(visibleSlashCommands.enumerated()), id: \.offset) { index, item in
                            Button(item.title) { selectSlashCommand(item) }
                                .fontWeight(index == min(slashSelectedIndex, visibleSlashCommands.count - 1) ? .semibold : .regular)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(index == min(slashSelectedIndex, visibleSlashCommands.count - 1) ?
                                            (editorTheme.suggestionSelectedBackgroundColor ?? .clear) : .clear,
                                            in: RoundedRectangle(cornerRadius: 4))
                                .accessibilityIdentifier("slash-suggestion-\(index)")
                        }
                    }
                }
                .frame(maxHeight: 220)
            }
            .font(.subheadline)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(editorTheme.suggestionPanelColor ?? Color(uiColor: .tertiarySystemBackground),
                        in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func selectSlashCommand(_ item: EditorSlashCommand) {
        guard let match = activeSlashMatch else { return }
        if let command = item.command,
           capabilities.supports(command),
           (command != .wikilink || enableWikilinks),
           controller.applySlashCommand(command, match: match) {
            slashSelectedIndex = 0
        }
        if let custom = item.customCommand {
            Task { @MainActor in
                let markdown: String?
                if let fixed = custom.markdown {
                    markdown = fixed
                } else {
                    markdown = await custom.onSelected?(match.query)
                }
                if let markdown, controller.applyCustomSlashCommand(markdown, match: match) {
                    slashSelectedIndex = 0
                }
            }
        }
    }

    private var activeWikilinkMatch: WikilinkTrigger.Match? {
        guard enableWikilinks, inlineSelection.length == 0 else { return nil }
        let body = controller.semanticDocument.blockById(block.id)?.plainText ?? block.plainText
        return WikilinkTrigger.match(in: body, cursor: inlineSelection.location)
    }

    private var visibleWikilinkSuggestions: [String] {
        guard let match = activeWikilinkMatch else { return [] }
        return WikilinkTrigger.suggestions(wikilinkSuggestions, for: match.query)
    }

    @ViewBuilder
    private var wikilinkSuggestionPanel: some View {
        if activeWikilinkMatch != nil {
            let matches = visibleWikilinkSuggestions
            VStack(alignment: .leading, spacing: 4) {
                if matches.isEmpty {
                    Text("No matching notes").foregroundStyle(.secondary)
                        .accessibilityIdentifier("wikilink-empty-state")
                } else {
                    ForEach(Array(matches.enumerated()), id: \.offset) { index, title in
                        Button(title) {
                            selectWikilink(title)
                        }
                        .accessibilityIdentifier("wikilink-suggestion-\(index)")
                        .fontWeight(index == min(wikilinkSelectedIndex, matches.count - 1) ? .semibold : .regular)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(index == min(wikilinkSelectedIndex, matches.count - 1) ?
                                    (editorTheme.suggestionSelectedBackgroundColor ?? .clear) : .clear,
                                    in: RoundedRectangle(cornerRadius: 4))
                    }
                }
            }
            .font(.subheadline)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(editorTheme.suggestionPanelColor ?? Color(uiColor: .tertiarySystemBackground),
                        in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func inlineTextView(font: UIFont, identifier: String) -> some View {
        let sourceAtRender = controller.text
        return SemanticInlineTextView(text: controller.semanticDocument.blockById(block.id)?.plainText ?? block.plainText,
                               selectedRange: inlineSelection, font: font, identifier: identifier,
                               blockID: block.id, crossBlockHighlight: crossBlockHighlight,
                               onEdit: { value in
            if value.isEmpty, case .paragraph = block.kind {
                return controller.removeSemanticBlock(id: block.id)
            }
            return controller.replaceSemanticBlockContent(id: block.id, with: value)
        }, onStructuredPaste: { range, markdown in
            let inserted = controller.replaceSemanticTextRangeWithMarkdownBlocks(id: block.id,
                                                                                 range: range,
                                                                                 markdown: markdown,
                                                                                 ifTextIs: sourceAtRender)
            if inserted { inlineSelection = NSRange(location: 0, length: 0) }
            return inserted
        }, onSelection: { inlineSelection = $0 }, onCrossBlockDrag: onCrossBlockDrag,
                               suggestionsVisible: !visibleWikilinkSuggestions.isEmpty || !visibleSlashCommands.isEmpty,
                               onSuggestionKey: handleSuggestionKey)
        .frame(minHeight: 44)
    }

    @ViewBuilder
    private func proseContent(font: UIFont, rawIdentifier: String, visibleIdentifier: String) -> some View {
        let markdown = controller.semanticDocument.blockById(block.id)?.plainText ?? block.plainText
        if MarkdownInlineMarkEditor.visibleText(of: markdown) != nil {
            VisibleInlineTextView(markdown: markdown, font: font, identifier: visibleIdentifier,
                                  blockID: block.id, crossBlockHighlight: visibleCrossBlockHighlight,
                                  onSelection: onVisibleSelection, onCrossBlockDrag: onVisibleCrossBlockDrag)
                .frame(minHeight: 44)
            DisclosureGroup("Edit Markdown", isExpanded: $editingMarkdown) {
                inlineActions
                textRangeActions
                inlineTextView(font: font, identifier: rawIdentifier)
                wikilinkSuggestionPanel
                slashSuggestionPanel
            }
            .font(.caption)
        } else {
            inlineActions
            textRangeActions
            inlineTextView(font: font, identifier: rawIdentifier)
            wikilinkSuggestionPanel
            slashSuggestionPanel
        }
    }

    private func headingTextStyle(_ level: Int) -> UIFont.TextStyle {
        switch level {
        case 1: .largeTitle
        case 2: .title1
        case 3: .title2
        default: .title3
        }
    }

    private func selectWikilink(_ title: String) {
        if let next = controller.insertWikilinkSuggestion(title, inBlock: block.id,
                                                          selection: inlineSelection) {
            inlineSelection = next
            wikilinkSelectedIndex = 0
        }
    }

    private func handleWikilinkKey(_ key: WikilinkSuggestionKey) {
        let suggestions = visibleWikilinkSuggestions
        guard !suggestions.isEmpty else { return }
        switch key {
        case .next: wikilinkSelectedIndex = (wikilinkSelectedIndex + 1) % suggestions.count
        case .previous: wikilinkSelectedIndex = (wikilinkSelectedIndex - 1 + suggestions.count) % suggestions.count
        case .accept: selectWikilink(suggestions[min(wikilinkSelectedIndex, suggestions.count - 1)])
        }
    }

    private func handleSuggestionKey(_ key: WikilinkSuggestionKey) {
        let commands = visibleSlashCommands
        guard !commands.isEmpty else { handleWikilinkKey(key); return }
        switch key {
        case .next: slashSelectedIndex = (slashSelectedIndex + 1) % commands.count
        case .previous: slashSelectedIndex = (slashSelectedIndex - 1 + commands.count) % commands.count
        case .accept: selectSlashCommand(commands[min(slashSelectedIndex, commands.count - 1)])
        }
    }

    private var inlineActions: some View {
        HStack(spacing: 12) {
            if capabilities.supports(.bold) {
                Button("B") { apply(.bold) }.accessibilityLabel("Bold selection")
            }
            if capabilities.supports(.italic) {
                Button("I") { apply(.italic) }.accessibilityLabel("Italic selection")
            }
            if capabilities.supports(.link) {
                Button("Link") { showLinkEditor = true }.accessibilityLabel("Link selection")
            }
            if capabilities.supports(.inlineCode) {
                Button("Code") { apply(.code) }.accessibilityLabel("Inline code selection")
            }
        }
        .font(.caption.weight(.semibold))
        .buttonStyle(.bordered)
        .disabled(inlineSelection.length == 0)
    }

    private var textRangeActions: some View {
        HStack(spacing: 8) {
            Button("Start at selection") {
                onCaptureTextPosition(.init(blockID: block.id, offset: inlineSelection.location), true)
            }
            .accessibilityIdentifier("text-range-start-\(block.id)")
            Button("End at selection") {
                onCaptureTextPosition(.init(blockID: block.id, offset: NSMaxRange(inlineSelection)), false)
            }
            .accessibilityIdentifier("text-range-end-\(block.id)")
        }
        .font(.caption)
        .buttonStyle(.bordered)
    }

    private func apply(_ mark: MarkdownInlineMark) {
        if let next = controller.applySemanticInlineMark(id: block.id, selection: inlineSelection, mark: mark) {
            inlineSelection = next
        }
    }

    private var contentBinding: Binding<String> {
        Binding(get: {
            controller.semanticDocument.blockById(block.id)?.plainText ?? block.plainText
        }, set: { value in
            if value.isEmpty, case .paragraph = block.kind {
                controller.removeSemanticBlock(id: block.id)
            } else {
                controller.replaceSemanticBlockContent(id: block.id, with: value)
            }
        })
    }

    private func blockLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(editorTheme.blockHeaderTextColor ?? .secondary)
            .padding(.horizontal, editorTheme.blockHeaderColor == nil ? 0 : 6)
            .padding(.vertical, editorTheme.blockHeaderColor == nil ? 0 : 3)
            .background(editorTheme.blockHeaderColor ?? .clear,
                        in: RoundedRectangle(cornerRadius: 4))
    }
}

@available(iOS 17.0, *)
private struct FormattedTableView: View {
    @Environment(\.markdownEditorTheme) private var editorTheme
    @ObservedObject var controller: MarkdownEditorController
    let blockID: String
    let table: MarkdownSourceTable
    let textHighlights: [Int: [Int: NSRange]]?
    let onCaptureTextPosition: (MarkdownSemanticTextPosition, Bool) -> Void
    @State private var selectedCells: MarkdownSemanticTableCellSelection?
    @State private var focusedCell: (row: Int, column: Int, selection: NSRange)?
    @State private var keepSelectionAfterPaste = false
    @State private var pasteError = false

    private func isSelected(row: Int, column: Int) -> Bool {
        guard let selectedCells,
              let rectangle = controller.semanticTableCellRectangle(selectedCells) else { return false }
        return rectangle.rows.contains(row) && rectangle.columns.contains(column)
    }

    private func selectCells(anchorRow: Int, anchorColumn: Int, focusRow: Int, focusColumn: Int) {
        let selection = MarkdownSemanticTableCellSelection(blockID: blockID,
                                                            anchorRow: anchorRow, anchorColumn: anchorColumn,
                                                            focusRow: focusRow, focusColumn: focusColumn)
        if controller.semanticTableCellRectangle(selection) != nil { selectedCells = selection }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("TABLE · \(table.columnCount) COLUMNS")
                    .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Menu("Add") {
                    Button("Row") { edit { $0.insertingRowAfter($0.rows.count - 1) } }
                    Button("Column") { edit { $0.insertingColumnAfter($0.columnCount - 1) } }
                }
            }
            if let focusedCell {
                HStack(spacing: 8) {
                    Button("Start at cell selection") {
                        onCaptureTextPosition(.init(blockID: blockID, offset: focusedCell.selection.location,
                                                    tableRow: focusedCell.row, tableColumn: focusedCell.column), true)
                    }
                    .accessibilityIdentifier("table-text-range-start-\(blockID)")
                    Button("End at cell selection") {
                        onCaptureTextPosition(.init(blockID: blockID, offset: NSMaxRange(focusedCell.selection),
                                                    tableRow: focusedCell.row, tableColumn: focusedCell.column), false)
                    }
                    .accessibilityIdentifier("table-text-range-end-\(blockID)")
                }
                .font(.caption)
                .buttonStyle(.bordered)
            }
            if let selectedCells {
                HStack(spacing: 8) {
                    Menu("Format cells") {
                        Button("Bold") { _ = controller.applySemanticInlineMarkToTableCells(selectedCells, mark: .bold) }
                        Button("Italic") { _ = controller.applySemanticInlineMarkToTableCells(selectedCells, mark: .italic) }
                        Button("Strikethrough") { _ = controller.applySemanticInlineMarkToTableCells(selectedCells, mark: .strikethrough) }
                        Button("Inline code") { _ = controller.applySemanticInlineMarkToTableCells(selectedCells, mark: .code) }
                    }
                    .accessibilityIdentifier("table-range-format")
                    Button("Copy cells") {
                        if let copied = controller.copySemanticTableCellsAsTSV(selectedCells) {
                            UIPasteboard.general.string = copied
                        }
                    }
                    Button("Paste cells") {
                        if let pasted = UIPasteboard.general.string {
                            keepSelectionAfterPaste = true
                            if !controller.pasteSemanticTableCells(pasted, into: selectedCells) {
                                keepSelectionAfterPaste = false
                                pasteError = true
                            }
                        } else {
                            pasteError = true
                        }
                    }
                    .accessibilityIdentifier("table-range-paste")
                    Button("Clear cells", role: .destructive) {
                        if controller.clearSemanticTableCells(selectedCells) { self.selectedCells = nil }
                    }
                    .disabled(!controller.canClearSemanticTableCells(selectedCells))
                    Button("Clear selection") { self.selectedCells = nil }
                }
                .font(.caption)
                .buttonStyle(.bordered)
            }
            ScrollView(.horizontal) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        ForEach(table.headers.indices, id: \.self) { column in
                            VStack(alignment: .leading, spacing: 4) {
                                FormattedTableCell(controller: controller, blockID: blockID,
                                                   row: 0, column: column, isHeader: true,
                                                   isRangeSelected: isSelected(row: 0, column: column),
                                                   textHighlight: textHighlights?[0]?[column],
                                                   onRangeDrag: selectCells,
                                                   onSelection: { row, column, range in
                                                       focusedCell = (row, column, range)
                                                   })
                                Menu(alignmentLabel(table.alignments[column])) {
                                    Button("Align default") { edit { $0.settingColumnAlignment(column, to: nil) } }
                                    Button("Align left") { edit { $0.settingColumnAlignment(column, to: .left) } }
                                    Button("Align center") { edit { $0.settingColumnAlignment(column, to: .center) } }
                                    Button("Align right") { edit { $0.settingColumnAlignment(column, to: .right) } }
                                    Divider()
                                    Button("Insert column before") { edit { $0.insertingColumnBefore(column) } }
                                    Button("Insert column after") { edit { $0.insertingColumnAfter(column) } }
                                    Button("Delete column", role: .destructive) { edit { $0.deletingColumn(column) } }
                                }
                                .font(.caption2)
                            }
                            .frame(width: 150)
                        }
                    }
                    ForEach(table.rows.indices, id: \.self) { row in
                        HStack(spacing: 6) {
                            ForEach(table.headers.indices, id: \.self) { column in
                                FormattedTableCell(controller: controller, blockID: blockID,
                                                   row: row, column: column, isHeader: false,
                                                   isRangeSelected: isSelected(row: row + 1, column: column),
                                                   textHighlight: textHighlights?[row + 1]?[column],
                                                   onRangeDrag: selectCells,
                                                   onSelection: { row, column, range in
                                                       focusedCell = (row, column, range)
                                                   })
                                    .frame(width: 150)
                            }
                            Menu("Row \(row + 1)") {
                                Button("Insert row before") { edit { $0.insertingRowBefore(row) } }
                                Button("Insert row after") { edit { $0.insertingRowAfter(row) } }
                                Button("Delete row", role: .destructive) { edit { $0.deletingRow(row) } }
                            }
                            .font(.caption)
                        }
                    }
                }
                .padding(editorTheme.tablePadding ?? EdgeInsets())
            }
        }
        .onChange(of: controller.text) { _, _ in
            if keepSelectionAfterPaste, let selectedCells,
               controller.semanticTableCellRectangle(selectedCells) != nil {
                keepSelectionAfterPaste = false
            } else {
                keepSelectionAfterPaste = false
                selectedCells = nil
            }
        }
        .alert("Table paste not applied", isPresented: $pasteError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The clipboard must contain a rectangular grid matching the selected cells. No cells were changed.")
        }
    }

    private func edit(_ transform: (MarkdownSourceTable) -> MarkdownSourceTable) {
        controller.updateSemanticTable(id: blockID, transform)
    }

    private func alignmentLabel(_ alignment: MarkdownTableAlignment?) -> String {
        switch alignment {
        case .left: "Left"
        case .center: "Center"
        case .right: "Right"
        case nil: "Default"
        }
    }
}

@available(iOS 17.0, *)
private struct FormattedTableCell: View {
    @ObservedObject var controller: MarkdownEditorController
    @State private var pasteError = false
    let blockID: String
    let row: Int
    let column: Int
    let isHeader: Bool
    let isRangeSelected: Bool
    let textHighlight: NSRange?
    let onRangeDrag: (Int, Int, Int, Int) -> Void
    let onSelection: (Int, Int, NSRange) -> Void

    var body: some View {
        FormattedTableInputField(text: textBinding, placeholder: isHeader ? "Header" : "Cell",
                                 identifier: "table-\(blockID)-\(isHeader ? "header" : "row-\(row)")-col-\(column)",
                                 blockID: blockID, row: isHeader ? 0 : row + 1, column: column,
                                 isHeader: isHeader,
                                 isRangeSelected: isRangeSelected, textHighlight: textHighlight,
                                 onRangeDrag: onRangeDrag,
                                 onSelection: onSelection,
                                 onGridPaste: { source in
                                     controller.pasteTableCells(source, inTable: blockID,
                                                                row: isHeader ? 0 : row + 1,
                                                                column: column)
                                 }, onSourcePaste: { source, range, visibleText in
                                     controller.pasteIntoTableCellSource(source, inTable: blockID,
                                                                         row: isHeader ? 0 : row + 1,
                                                                         column: column, visibleText: visibleText,
                                                                         visibleRange: range)
                                 }, onPasteRejected: {
                                     pasteError = true
                                 })
        .alert("Table paste not applied", isPresented: $pasteError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The cell selection could not be mapped safely to its Markdown source. The clipboard is unchanged; switch to Source mode to paste it there.")
        }
    }

    private var textBinding: Binding<String> {
        Binding(get: {
            guard let block = controller.semanticDocument.blockById(blockID),
                  case let .table(table) = block.kind, table.headers.indices.contains(column) else { return "" }
            let source = isHeader ? table.headers[column] :
                (table.rows.indices.contains(row) ? table.rows[row][column] : "")
            return source.replacingOccurrences(of: "\\|", with: "|")
        }, set: { value in
            controller.updateSemanticTable(id: blockID) {
                $0.replacingCell(rowIndex: row, columnIndex: column, text: value, header: isHeader)
            }
        })
    }
}

@available(iOS 17.0, *)
private struct FormattedTableInputField: UIViewRepresentable {
    @Environment(\.markdownEditorTheme) private var editorTheme
    @Binding var text: String
    let placeholder: String
    let identifier: String
    let blockID: String
    let row: Int
    let column: Int
    let isHeader: Bool
    let isRangeSelected: Bool
    let textHighlight: NSRange?
    let onRangeDrag: (Int, Int, Int, Int) -> Void
    let onSelection: (Int, Int, NSRange) -> Void
    let onGridPaste: (String) -> Bool
    let onSourcePaste: (String, NSRange, String) -> Bool
    let onPasteRejected: () -> Void

    func makeUIView(context: Context) -> FormattedRangeTextField {
        let field = FormattedRangeTextField()
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.textChanged(_:)), for: .editingChanged)
        field.font = .preferredFont(forTextStyle: .body)
        field.adjustsFontForContentSizeCategory = true
        field.borderStyle = .roundedRect
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.placeholder = placeholder
        field.accessibilityIdentifier = identifier
        field.text = text
        configure(field)
        return field
    }

    func updateUIView(_ field: FormattedRangeTextField, context: Context) {
        context.coordinator.parent = self
        if field.text != text { field.text = text }
        configure(field)
    }

    private func configure(_ field: FormattedRangeTextField) {
        field.rangeIdentity = .table(blockID: blockID, row: row, column: column)
        field.crossCellHighlight = textHighlight
        field.crossCellHighlightColor = editorTheme.selectionColor.map(UIColor.init)
        let background = editorTheme.tableCellBackground(isSelected: isRangeSelected, isHeader: isHeader)
        field.backgroundColor = background.map(UIColor.init) ??
            (isRangeSelected ? UIColor.systemBlue.withAlphaComponent(0.2) : .clear)
        if let color = editorTheme.tableCellBorder(isActive: field.isFirstResponder) {
            field.borderStyle = .none
            field.layer.borderColor = UIColor(color).cgColor
            field.layer.borderWidth = field.isFirstResponder ? 1.5 : 1
            field.layer.cornerRadius = 5
        } else {
            field.borderStyle = .roundedRect
            field.layer.borderWidth = 0
            field.layer.cornerRadius = 0
        }
        field.onRangeDrag = { anchor, focus in
            guard case let .table(firstBlock, firstRow, firstColumn) = anchor,
                  case let .table(lastBlock, lastRow, lastColumn) = focus,
                  firstBlock == lastBlock else { return }
            onRangeDrag(firstRow, firstColumn, lastRow, lastColumn)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: FormattedTableInputField
        init(parent: FormattedTableInputField) { self.parent = parent }

        @objc func textChanged(_ field: UITextField) { parent.text = field.text ?? "" }
        private func reportSelection(_ field: UITextField) {
            guard let selected = field.selectedTextRange else { return }
            let start = field.offset(from: field.beginningOfDocument, to: selected.start)
            let end = field.offset(from: field.beginningOfDocument, to: selected.end)
            parent.onSelection(parent.row, parent.column, NSRange(location: start, length: end - start))
        }
        func textFieldDidChangeSelection(_ textField: UITextField) { reportSelection(textField) }
        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange,
                       replacementString string: String) -> Bool {
            guard textField.markedTextRange == nil,
                  string.contains("\t") || string.contains("\n") || string.contains("\r") else { return true }
            let visibleText = textField.text ?? ""
            if MarkdownEditorController.shouldRouteFocusedTablePasteAsGrid(
                string, visibleText: visibleText, selection: range), parent.onGridPaste(string) {
                return false
            }
            if !parent.onSourcePaste(string, range, visibleText) { parent.onPasteRejected() }
            return false
        }
        func textFieldDidBeginEditing(_ textField: UITextField) {
            reportSelection(textField)
            if let field = textField as? FormattedRangeTextField { parent.configure(field) }
        }
        func textFieldDidEndEditing(_ textField: UITextField) {
            if let field = textField as? FormattedRangeTextField { parent.configure(field) }
        }
    }
}

@available(iOS 17.0, *)
private struct FormattedListView: View {
    @Environment(\.markdownEditorTheme) private var editorTheme
    @ObservedObject var controller: MarkdownEditorController
    let blockID: String
    let list: MarkdownSourceList
    let textHighlights: MarkdownEditorController.ListLineHighlights?
    let onCaptureTextPosition: (MarkdownSemanticTextPosition, Bool) -> Void
    @State private var focusRequest: (index: Int, continuationIndex: Int?, offset: Int, token: UUID)?
    @State private var itemSelections: [Int: NSRange] = [:]
    @State private var continuationSelections: [Int: [Int: NSRange]] = [:]
    @State private var trailingSelections: [Int: [Int: NSRange]] = [:]
    @State private var selectedItems: MarkdownSemanticListItemSelection?
    @State private var rangeLinkDestination = "https://"
    @State private var showingRangeLinkEditor = false
    @State private var showingPasteFailure = false

    private func isSelected(_ index: Int) -> Bool {
        guard let selectedItems else { return false }
        let first = min(selectedItems.anchorIndex, selectedItems.focusIndex)
        let last = max(selectedItems.anchorIndex, selectedItems.focusIndex)
        return (first...last).contains(index)
    }

    private func requestedFocus(for index: Int, continuationIndex: Int? = nil) -> (token: UUID, offset: Int)? {
        guard let focusRequest, focusRequest.index == index,
              focusRequest.continuationIndex == continuationIndex else { return nil }
        return (focusRequest.token, focusRequest.offset)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("LIST").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                .alert("Paste could not be applied", isPresented: $showingPasteFailure) {
                    Button("OK") { }
                } message: {
                    Text("The list changed before the paste. Your text is still on the clipboard; tap the row and paste again.")
                }
            if let selectedItems {
                HStack(spacing: 8) {
                    Menu("Format items") {
                        Button("Bold") { _ = controller.applySemanticInlineMarkToListItemRange(selectedItems, mark: .bold) }
                        Button("Italic") { _ = controller.applySemanticInlineMarkToListItemRange(selectedItems, mark: .italic) }
                        Button("Strikethrough") { _ = controller.applySemanticInlineMarkToListItemRange(selectedItems, mark: .strikethrough) }
                        Button("Inline code") { _ = controller.applySemanticInlineMarkToListItemRange(selectedItems, mark: .code) }
                        Button("Link") { showingRangeLinkEditor = true }
                    }
                    .accessibilityIdentifier("list-range-format")
                    Button("Copy items") {
                        if let copied = controller.copySemanticListItemRange(selectedItems) {
                            UIPasteboard.general.string = copied
                        }
                    }
                    Button("Delete items", role: .destructive) {
                        if controller.deleteSemanticListItemRange(selectedItems) { self.selectedItems = nil }
                    }
                    .disabled(!controller.canDeleteSemanticListItemRange(selectedItems))
                    Button("Clear selection") { self.selectedItems = nil }
                }
                .font(.caption)
                .buttonStyle(.bordered)
            }
            ForEach(0..<list.items.count, id: \.self) { index in
                let item = list.items[index]
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        if let checked = item.checked {
                            Button {
                                controller.updateSemanticList(id: blockID) { $0.settingTaskChecked(at: index, to: !checked) }
                            } label: {
                                Image(systemName: checked ? "checkmark.square" : "square")
                            }
                            .accessibilityLabel(checked ? "Mark item \(index + 1) incomplete" : "Mark item \(index + 1) complete")
                        } else {
                            Text(item.marker).font(.system(.body, design: .monospaced))
                        }
                        let sourceAtRender = controller.text
                        FormattedListItemField(text: Binding(get: {
                            guard let block = controller.semanticDocument.blockById(blockID),
                                  case let .list(current) = block.kind,
                                  current.items.indices.contains(index) else { return item.content }
                            return current.items[index].content
                        }, set: { value in
                            controller.updateSemanticList(id: blockID) { $0.replacingItemContent(at: index, with: value) }
                        }), blockID: blockID, index: index, isRangeSelected: isSelected(index),
                            crossItemHighlight: textHighlights?.primary[index],
                            onSelection: { itemSelections[index] = $0 },
                            onRangeDrag: { anchor, focus in
                                let selection = MarkdownSemanticListItemSelection(blockID: blockID,
                                                                                   anchorIndex: anchor,
                                                                                   focusIndex: focus)
                                if controller.copySemanticListItemRange(selection) != nil {
                                    selectedItems = selection
                                }
                            },
                            focusRequest: requestedFocus(for: index),
                            onSubmit: { contentOffset in
                                let split = contentOffset < (item.content as NSString).length
                                if controller.submitSemanticListItem(id: blockID, at: index, contentOffset: contentOffset), split {
                                    focusRequest = (index + 1, nil, 0, UUID())
                                }
                        }, onIndent: { outdent in
                            _ = changeIndent(at: index, outdent: outdent)
                        }, onStructuredPaste: { range, markdown, displayedText in
                            if let focus = controller.replaceSemanticListLineWithMarkdownBlocks(
                                id: blockID, index: index, range: range, markdown: markdown,
                                ifTextIs: sourceAtRender) {
                                focusRequest = (focus.index, focus.continuationIndex, focus.offset, UUID())
                                return true
                            }
                            if controller.pasteListLineVerbatimInSource(id: blockID, index: index,
                                                                        range: range, markdown: markdown,
                                                                        displayedText: displayedText) { return true }
                            showingPasteFailure = true
                            return false
                        })
                        .accessibilityIdentifier("list-\(blockID)-item-\(index)")
                        .frame(maxWidth: .infinity)
                        Button { _ = changeIndent(at: index, outdent: true) } label: {
                            Image(systemName: "decrease.indent")
                        }
                        .accessibilityLabel("Outdent item \(index + 1)")
                        .disabled(list.outdentingItem(at: index) == nil)
                        Button { _ = changeIndent(at: index, outdent: false) } label: {
                            Image(systemName: "increase.indent")
                        }
                        .accessibilityLabel("Indent item \(index + 1)")
                        .disabled(list.indentingItem(at: index) == nil)
                    }
                    if let selected = itemSelections[index] {
                        HStack(spacing: 8) {
                            Button("Start at selection") {
                                onCaptureTextPosition(.init(blockID: blockID, offset: selected.location,
                                                            listItemIndex: index), true)
                            }
                            .accessibilityIdentifier("text-range-start-\(blockID)-item-\(index)")
                            Button("End at selection") {
                                onCaptureTextPosition(.init(blockID: blockID, offset: NSMaxRange(selected),
                                                            listItemIndex: index), false)
                            }
                            .accessibilityIdentifier("text-range-end-\(blockID)-item-\(index)")
                        }
                        .font(.caption)
                        .buttonStyle(.bordered)
                    }
                    ForEach(item.continuations.indices, id: \.self) { lineIndex in
                        let continuation = item.continuations[lineIndex]
                        let sourceAtRender = controller.text
                        FormattedListItemField(text: Binding(get: {
                            guard let block = controller.semanticDocument.blockById(blockID),
                                  case let .list(current) = block.kind,
                                  current.items.indices.contains(index),
                                  current.items[index].continuations.indices.contains(lineIndex) else {
                                return continuation.content
                            }
                            return current.items[index].continuations[lineIndex].content
                        }, set: { value in
                            controller.updateSemanticList(id: blockID) {
                                $0.replacingContinuationContent(at: index, lineIndex: lineIndex, with: value)
                            }
                        }), blockID: blockID, index: index, isRangeSelected: isSelected(index),
                            crossItemHighlight: textHighlights?.continuations[index]?[lineIndex],
                            onSelection: { continuationSelections[index, default: [:]][lineIndex] = $0 },
                            onRangeDrag: { anchor, focus in
                                let selection = MarkdownSemanticListItemSelection(blockID: blockID,
                                                                                   anchorIndex: anchor,
                                                                                   focusIndex: focus)
                                if controller.copySemanticListItemRange(selection) != nil {
                                    selectedItems = selection
                                }
                            }, focusRequest: requestedFocus(for: index, continuationIndex: lineIndex),
                            onSubmit: nil, onIndent: { outdent in
                                _ = changeIndent(at: index, outdent: outdent)
                            }, onStructuredPaste: { range, markdown, displayedText in
                                if let focus = controller.replaceSemanticListLineWithMarkdownBlocks(
                                    id: blockID, index: index, continuationIndex: lineIndex,
                                    range: range, markdown: markdown,
                                    ifTextIs: sourceAtRender) {
                                    focusRequest = (focus.index, focus.continuationIndex, focus.offset, UUID())
                                    return true
                                }
                                if controller.pasteListLineVerbatimInSource(id: blockID, index: index,
                                                                            continuationIndex: lineIndex,
                                                                            range: range, markdown: markdown,
                                                                            displayedText: displayedText) { return true }
                                showingPasteFailure = true
                                return false
                            })
                        .padding(.leading, CGFloat(continuation.indent.count - item.indent.count) * 8)
                        .accessibilityIdentifier("list-\(blockID)-item-\(index)-continuation-\(lineIndex)")
                        if let selected = continuationSelections[index]?[lineIndex] {
                            HStack(spacing: 8) {
                                Button("Start at selection") {
                                    onCaptureTextPosition(.init(blockID: blockID, offset: selected.location,
                                        listItemIndex: index, listContinuationIndex: lineIndex), true)
                                }
                                .accessibilityIdentifier("text-range-start-\(blockID)-item-\(index)-continuation-\(lineIndex)")
                                Button("End at selection") {
                                    onCaptureTextPosition(.init(blockID: blockID, offset: NSMaxRange(selected),
                                        listItemIndex: index, listContinuationIndex: lineIndex), false)
                                }
                                .accessibilityIdentifier("text-range-end-\(blockID)-item-\(index)-continuation-\(lineIndex)")
                            }
                            .font(.caption)
                            .buttonStyle(.bordered)
                        }
                    }
                }
                .padding(.leading, CGFloat(item.indent.count) * 8)
                .padding(4)
                .background(isSelected(index) || textHighlights?.primary[index] != nil ||
                            textHighlights?.continuations[index] != nil ?
                            (editorTheme.selectionColor ?? Color.accentColor.opacity(0.15)) : .clear,
                            in: RoundedRectangle(cornerRadius: 6))
                ForEach(list.trailingOwners(after: index), id: \.self) { parentIndex in
                    ForEach(list.items[parentIndex].trailingContinuations.indices, id: \.self) { lineIndex in
                        let continuation = list.items[parentIndex].trailingContinuations[lineIndex]
                        FormattedListItemField(text: Binding(get: {
                            guard let block = controller.semanticDocument.blockById(blockID),
                                  case let .list(current) = block.kind,
                                  current.items.indices.contains(parentIndex),
                                  current.items[parentIndex].trailingContinuations.indices.contains(lineIndex) else {
                                return continuation.content
                            }
                            return current.items[parentIndex].trailingContinuations[lineIndex].content
                        }, set: { value in
                            controller.updateSemanticList(id: blockID) {
                                $0.replacingTrailingContinuationContent(at: parentIndex,
                                                                        lineIndex: lineIndex, with: value)
                            }
                        }), blockID: blockID, index: parentIndex, isRangeSelected: isSelected(parentIndex),
                            crossItemHighlight: textHighlights?.trailing[parentIndex]?[lineIndex],
                            onSelection: { trailingSelections[parentIndex, default: [:]][lineIndex] = $0 },
                            onRangeDrag: { anchor, focus in
                                let selection = MarkdownSemanticListItemSelection(blockID: blockID,
                                                                                   anchorIndex: anchor,
                                                                                   focusIndex: focus)
                                if controller.copySemanticListItemRange(selection) != nil {
                                    selectedItems = selection
                                }
                            }, focusRequest: nil, onSubmit: nil, onIndent: { _ in },
                            onStructuredPaste: { range, markdown, displayedText in
                                if controller.pasteListLineVerbatimInSource(id: blockID, index: parentIndex,
                                                                            trailingIndex: lineIndex,
                                                                            range: range, markdown: markdown,
                                                                            displayedText: displayedText) { return true }
                                showingPasteFailure = true
                                return false
                            })
                            .padding(.leading, CGFloat(continuation.indent.count) * 8 + 4)
                            .padding(.top, 4)
                            .accessibilityIdentifier("list-\(blockID)-item-\(parentIndex)-trailing-\(lineIndex)")
                        if let selected = trailingSelections[parentIndex]?[lineIndex] {
                            HStack(spacing: 8) {
                                Button("Start at selection") {
                                    onCaptureTextPosition(.init(blockID: blockID, offset: selected.location,
                                        listItemIndex: parentIndex, listTrailingIndex: lineIndex), true)
                                }
                                .accessibilityIdentifier("text-range-start-\(blockID)-item-\(parentIndex)-trailing-\(lineIndex)")
                                Button("End at selection") {
                                    onCaptureTextPosition(.init(blockID: blockID, offset: NSMaxRange(selected),
                                        listItemIndex: parentIndex, listTrailingIndex: lineIndex), false)
                                }
                                .accessibilityIdentifier("text-range-end-\(blockID)-item-\(parentIndex)-trailing-\(lineIndex)")
                            }
                            .font(.caption)
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
        .alert("Link URL", isPresented: $showingRangeLinkEditor) {
            TextField("https://example.com", text: $rangeLinkDestination)
                .textInputAutocapitalization(.never)
            Button("Apply") {
                if let selectedItems {
                    _ = controller.applySemanticInlineMarkToListItemRange(
                        selectedItems, mark: .link(destination: rangeLinkDestination))
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Only http, https, mailto, and tel links are accepted.")
        }
        .onChange(of: controller.text) { _, _ in
            selectedItems = nil
            itemSelections.removeAll()
            continuationSelections.removeAll()
            trailingSelections.removeAll()
        }
    }

    private func changeIndent(at index: Int, outdent: Bool) -> Bool {
        controller.updateSemanticList(id: blockID) { list in
            outdent ? list.outdentingItem(at: index) : list.indentingItem(at: index)
        }
    }

}

@available(iOS 17.0, *)
enum FormattedRangeFieldIdentity: Equatable {
    case list(blockID: String, index: Int)
    case table(blockID: String, row: Int, column: Int)
}

/// Tracks a long press as it crosses editable fields without taking away their
/// native caret, IME, edit menu or ScrollView gestures.
@available(iOS 17.0, *)
class FormattedRangeTextField: UITextField, UIGestureRecognizerDelegate {
    var rangeIdentity: FormattedRangeFieldIdentity?
    var onRangeDrag: ((FormattedRangeFieldIdentity, FormattedRangeFieldIdentity) -> Void)?
    var crossCellHighlight: NSRange? { didSet { setNeedsLayout() } }
    var crossCellHighlightColor: UIColor? { didSet { setNeedsLayout() } }
    private var dragAnchor: FormattedRangeFieldIdentity?
    private let cellRangeLayer = CAShapeLayer()

    override func layoutSubviews() {
        super.layoutSubviews()
        if cellRangeLayer.superlayer == nil { layer.insertSublayer(cellRangeLayer, at: 0) }
        cellRangeLayer.frame = bounds
        cellRangeLayer.fillColor = (crossCellHighlightColor ?? tintColor.withAlphaComponent(0.22)).cgColor
        let path = UIBezierPath()
        if let highlight = crossCellHighlight, highlight.length > 0,
           let first = position(from: beginningOfDocument, offset: highlight.location),
           let last = position(from: first, offset: highlight.length),
           let range = textRange(from: first, to: last) {
            for rect in selectionRects(for: range) where !rect.rect.isEmpty {
                path.append(UIBezierPath(roundedRect: rect.rect, cornerRadius: 2))
            }
        }
        cellRangeLayer.path = path.cgPath
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        installRangeGesture()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        installRangeGesture()
    }

    private func installRangeGesture() {
        let drag = UILongPressGestureRecognizer(target: self, action: #selector(handleRangeDrag(_:)))
        drag.minimumPressDuration = 0.4
        drag.cancelsTouchesInView = false
        drag.delegate = self
        addGestureRecognizer(drag)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }

    @objc private func handleRangeDrag(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            if markedTextRange == nil { dragAnchor = rangeIdentity }
        case .changed:
            guard let anchor = dragAnchor, let window else { return }
            var hit = window.hitTest(gesture.location(in: window), with: nil)
            while hit != nil && !(hit is FormattedRangeTextField) { hit = hit?.superview }
            guard let target = hit as? FormattedRangeTextField,
                  target.markedTextRange == nil, let focus = target.rangeIdentity,
                  focus != anchor else { return }
            onRangeDrag?(anchor, focus)
        case .ended, .cancelled, .failed:
            dragAnchor = nil
        default: break
        }
    }
}

/// UITextField handles Tab before SwiftUI's focus traversal so the active list item stays focused.
@available(iOS 17.0, *)
final class FormattedListKeyboardTextField: FormattedRangeTextField {
    var onIndent: ((Bool) -> Void)?
    var onReturnAtCaret: ((Int) -> Void)?
    var crossItemHighlight: NSRange? { didSet { setNeedsLayout() } }
    var crossItemHighlightColor: UIColor? { didSet { setNeedsLayout() } }
    private let rangeLayer = CAShapeLayer()

    override func layoutSubviews() {
        super.layoutSubviews()
        if rangeLayer.superlayer == nil { layer.insertSublayer(rangeLayer, at: 0) }
        rangeLayer.frame = bounds
        rangeLayer.fillColor = (crossItemHighlightColor ?? tintColor.withAlphaComponent(0.22)).cgColor
        let path = UIBezierPath()
        if let highlight = crossItemHighlight, highlight.length > 0,
           let first = position(from: beginningOfDocument, offset: highlight.location),
           let last = position(from: first, offset: highlight.length),
           let range = textRange(from: first, to: last) {
            for rect in selectionRects(for: range) where !rect.rect.isEmpty {
                path.append(UIBezierPath(roundedRect: rect.rect, cornerRadius: 2))
            }
        }
        rangeLayer.path = path.cgPath
    }

    /// Return from a one-line field only when the caret is collapsed.
    @discardableResult
    func submitAtCurrentCaret() -> Bool {
        guard let selectedTextRange, selectedTextRange.isEmpty else { return false }
        onReturnAtCaret?(offset(from: beginningOfDocument, to: selectedTextRange.start))
        return true
    }

    override var keyCommands: [UIKeyCommand]? {
        let indent = UIKeyCommand(input: "\t", modifierFlags: [], action: #selector(indentItem))
        let outdent = UIKeyCommand(input: "\t", modifierFlags: [.shift], action: #selector(outdentItem))
        indent.wantsPriorityOverSystemBehavior = true
        outdent.wantsPriorityOverSystemBehavior = true
        return [indent, outdent] + (super.keyCommands ?? [])
    }

    @objc private func indentItem() { onIndent?(false) }
    @objc private func outdentItem() { onIndent?(true) }
}

@available(iOS 17.0, *)
private struct FormattedListItemField: UIViewRepresentable {
    @Environment(\.markdownEditorTheme) private var editorTheme
    @Binding var text: String
    let blockID: String
    let index: Int
    let isRangeSelected: Bool
    let crossItemHighlight: NSRange?
    let onSelection: ((NSRange) -> Void)?
    let onRangeDrag: (Int, Int) -> Void
    let focusRequest: (token: UUID, offset: Int)?
    let onSubmit: ((Int) -> Void)?
    let onIndent: (Bool) -> Void
    let onStructuredPaste: (NSRange, String, String) -> Bool

    func makeUIView(context: Context) -> FormattedListKeyboardTextField {
        let field = FormattedListKeyboardTextField()
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.textChanged(_:)), for: .editingChanged)
        field.font = .preferredFont(forTextStyle: .body)
        field.adjustsFontForContentSizeCategory = true
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.returnKeyType = .default
        field.placeholder = "List item"
        field.text = text
        field.onIndent = onIndent
        field.onReturnAtCaret = onSubmit
        field.crossItemHighlight = crossItemHighlight
        field.crossItemHighlightColor = editorTheme.selectionColor.map(UIColor.init)
        field.rangeIdentity = .list(blockID: blockID, index: index)
        field.onRangeDrag = { anchor, focus in
            guard case let .list(firstBlock, firstIndex) = anchor,
                  case let .list(lastBlock, lastIndex) = focus,
                  firstBlock == lastBlock else { return }
            onRangeDrag(firstIndex, lastIndex)
        }
        field.backgroundColor = isRangeSelected ?
            (editorTheme.selectionColor.map(UIColor.init) ?? UIColor.systemBlue.withAlphaComponent(0.2)) : .clear
        return field
    }

    func updateUIView(_ field: FormattedListKeyboardTextField, context: Context) {
        context.coordinator.parent = self
        field.onIndent = onIndent
        field.onReturnAtCaret = onSubmit
        field.crossItemHighlight = crossItemHighlight
        field.crossItemHighlightColor = editorTheme.selectionColor.map(UIColor.init)
        field.rangeIdentity = .list(blockID: blockID, index: index)
        field.onRangeDrag = { anchor, focus in
            guard case let .list(firstBlock, firstIndex) = anchor,
                  case let .list(lastBlock, lastIndex) = focus,
                  firstBlock == lastBlock else { return }
            onRangeDrag(firstIndex, lastIndex)
        }
        field.backgroundColor = isRangeSelected ?
            (editorTheme.selectionColor.map(UIColor.init) ?? UIColor.systemBlue.withAlphaComponent(0.2)) : .clear
        if field.text != text { field.text = text }
        if let focusRequest, context.coordinator.handledFocusRequest != focusRequest.token {
            context.coordinator.handledFocusRequest = focusRequest.token
            field.becomeFirstResponder()
            if let caret = field.position(from: field.beginningOfDocument,
                                          offset: min(focusRequest.offset, ((field.text ?? "") as NSString).length)) {
                field.selectedTextRange = field.textRange(from: caret, to: caret)
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: FormattedListItemField
        var handledFocusRequest: UUID?

        init(parent: FormattedListItemField) { self.parent = parent }

        @objc func textChanged(_ field: UITextField) {
            parent.text = field.text ?? ""
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            textFieldDidChangeSelection(textField)
        }

        func textFieldDidChangeSelection(_ textField: UITextField) {
            guard let range = textField.selectedTextRange else { return }
            let start = textField.offset(from: textField.beginningOfDocument, to: range.start)
            let end = textField.offset(from: textField.beginningOfDocument, to: range.end)
            parent.onSelection?(NSRange(location: min(start, end), length: abs(end - start)))
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            guard parent.onSubmit != nil else { return true }
            (textField as? FormattedListKeyboardTextField)?.submitAtCurrentCaret()
            return false
        }

        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange,
                       replacementString string: String) -> Bool {
            if textField.markedTextRange == nil, string.contains("\n") || string.contains("\r") {
                // A single-line field cannot safely absorb rejected block syntax.
                // Route prose paragraphs and blank lines through the same
                // source-preserving fallback as structured Markdown.
                _ = parent.onStructuredPaste(range, string, textField.text ?? "")
                return false
            }
            return true
        }
    }
}

@available(iOS 17.0, *)
private enum WikilinkSuggestionKey { case next, previous, accept }

@available(iOS 17.0, *)
private class WikilinkInputTextView: UITextView {
    var suggestionsVisible = false
    var onSuggestionKey: ((WikilinkSuggestionKey) -> Void)?

    override var keyCommands: [UIKeyCommand]? {
        guard suggestionsVisible else { return super.keyCommands }
        return (super.keyCommands ?? []) + [
            UIKeyCommand(input: UIKeyCommand.inputDownArrow, modifierFlags: [], action: #selector(nextSuggestion)),
            UIKeyCommand(input: UIKeyCommand.inputUpArrow, modifierFlags: [], action: #selector(previousSuggestion)),
        ]
    }

    @objc private func nextSuggestion() { onSuggestionKey?(.next) }
    @objc private func previousSuggestion() { onSuggestionKey?(.previous) }
}

/// A visual selection across separate editable UITextViews. UIKit still owns
/// ordinary selection, edit menus, marked text and the keyboard within a row.
@available(iOS 17.0, *)
private final class SemanticRangeTextView: WikilinkInputTextView {
    var semanticBlockID = ""
    var isRenderedSelectionSurface = false
    var crossBlockHighlight: NSRange? { didSet { setNeedsLayout() } }
    var crossBlockHighlightColor: UIColor? { didSet { setNeedsLayout() } }
    private let rangeLayer = CAShapeLayer()

    override func layoutSubviews() {
        super.layoutSubviews()
        if rangeLayer.superlayer == nil { layer.insertSublayer(rangeLayer, at: 0) }
        rangeLayer.frame = bounds
        rangeLayer.fillColor = (crossBlockHighlightColor ?? tintColor.withAlphaComponent(0.22)).cgColor
        let path = UIBezierPath()
        if let highlight = crossBlockHighlight, highlight.length > 0,
           let first = position(from: beginningOfDocument, offset: highlight.location),
           let last = position(from: first, offset: highlight.length),
           let range = textRange(from: first, to: last) {
            for selectionRect in selectionRects(for: range) where !selectionRect.rect.isEmpty {
                path.append(UIBezierPath(roundedRect: selectionRect.rect, cornerRadius: 2))
            }
        }
        rangeLayer.path = path.cgPath
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        setNeedsLayout()
    }
}

@available(iOS 17.0, *)
private struct SemanticInlineTextView: UIViewRepresentable {
    @Environment(\.markdownEditorTheme) private var editorTheme
    let text: String
    let selectedRange: NSRange
    let font: UIFont
    let identifier: String
    let blockID: String
    let crossBlockHighlight: NSRange?
    let onEdit: (String) -> Bool
    let onStructuredPaste: (NSRange, String) -> Bool
    let onSelection: (NSRange) -> Void
    let onCrossBlockDrag: (MarkdownSemanticTextSelection) -> Void
    let suggestionsVisible: Bool
    let onSuggestionKey: (WikilinkSuggestionKey) -> Void
    var isCode = false

    func makeUIView(context: Context) -> UITextView {
        let view = SemanticRangeTextView()
        view.delegate = context.coordinator
        view.semanticBlockID = blockID
        view.crossBlockHighlight = crossBlockHighlight
        view.crossBlockHighlightColor = editorTheme.selectionColor.map(UIColor.init)
        let drag = UILongPressGestureRecognizer(target: context.coordinator,
                                                action: #selector(Coordinator.handleRangeDrag(_:)))
        drag.minimumPressDuration = 0.4
        drag.cancelsTouchesInView = false
        drag.delegate = context.coordinator
        view.addGestureRecognizer(drag)
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.textContainerInset = UIEdgeInsets(top: 6, left: 4, bottom: 6, right: 4)
        view.textContainer.lineFragmentPadding = 0
        view.font = isCode ? UIFont.monospacedSystemFont(ofSize: font.pointSize, weight: .regular) : font
        view.adjustsFontForContentSizeCategory = true
        view.text = text
        view.autocorrectionType = isCode ? .no : .default
        view.autocapitalizationType = isCode ? .none : .sentences
        view.accessibilityIdentifier = identifier
        view.suggestionsVisible = suggestionsVisible
        view.onSuggestionKey = onSuggestionKey
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.isUpdating = true
        defer { context.coordinator.isUpdating = false }
        view.font = isCode ? UIFont.monospacedSystemFont(ofSize: font.pointSize, weight: .regular) : font
        if let view = view as? SemanticRangeTextView {
            view.semanticBlockID = blockID
            view.crossBlockHighlight = crossBlockHighlight
            view.crossBlockHighlightColor = editorTheme.selectionColor.map(UIColor.init)
        }
        if let view = view as? WikilinkInputTextView {
            view.suggestionsVisible = suggestionsVisible
            view.onSuggestionKey = onSuggestionKey
        }
        if view.text != text { view.text = text }
        let limit = (text as NSString).length
        let location = min(max(0, selectedRange.location), limit)
        let valid = NSRange(location: location, length: min(max(0, selectedRange.length), limit - location))
        if view.selectedRange != valid { view.selectedRange = valid }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 300
        let measured = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: max(44, ceil(measured.height)))
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
        var parent: SemanticInlineTextView
        var isUpdating = false
        private var dragAnchor: MarkdownSemanticTextPosition?
        init(parent: SemanticInlineTextView) { self.parent = parent }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }

        @objc func handleRangeDrag(_ gesture: UILongPressGestureRecognizer) {
            guard let source = gesture.view as? SemanticRangeTextView else { return }
            switch gesture.state {
            case .began:
                guard source.markedTextRange == nil,
                      let position = source.closestPosition(to: gesture.location(in: source)) else { return }
                let offset = source.offset(from: source.beginningOfDocument, to: position)
                dragAnchor = .init(blockID: source.semanticBlockID, offset: offset)
            case .changed:
                guard let anchor = dragAnchor, let window = source.window else { return }
                let point = gesture.location(in: window)
                var hit = window.hitTest(point, with: nil)
                while hit != nil && !(hit is SemanticRangeTextView) { hit = hit?.superview }
                guard let target = hit as? SemanticRangeTextView,
                      target.semanticBlockID != anchor.blockID,
                      target.markedTextRange == nil,
                      let position = target.closestPosition(to: gesture.location(in: target)) else { return }
                let offset = target.offset(from: target.beginningOfDocument, to: position)
                parent.onCrossBlockDrag(.init(anchor: anchor,
                                              focus: .init(blockID: target.semanticBlockID, offset: offset)))
            case .ended, .cancelled, .failed:
                dragAnchor = nil
            default: break
            }
        }

        func textViewDidChange(_ textView: UITextView) {
            guard parent.onEdit(textView.text) else {
                isUpdating = true
                textView.text = parent.text
                isUpdating = false
                return
            }
            parent.onSelection(textView.selectedRange)
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange,
                      replacementText text: String) -> Bool {
            if text == "\n", parent.suggestionsVisible {
                parent.onSuggestionKey(.accept)
                return false
            }
            if MarkdownEditorController.isStructuredBlockPaste(text, hasMarkedText: textView.markedTextRange != nil),
               parent.onStructuredPaste(range, text) {
                return false
            }
            return true
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            if !isUpdating { parent.onSelection(textView.selectedRange) }
        }
    }
}

/// Selectable rendered prose; the adjacent disclosure keeps raw Markdown editing available.
@available(iOS 17.0, *)
private struct VisibleInlineTextView: UIViewRepresentable {
    @Environment(\.markdownEditorTheme) private var editorTheme
    let markdown: String
    let font: UIFont
    let identifier: String
    let blockID: String
    let crossBlockHighlight: NSRange?
    let onSelection: (NSRange) -> Void
    let onCrossBlockDrag: (MarkdownVisibleTextPosition, MarkdownVisibleTextPosition) -> Void

    func makeUIView(context: Context) -> UITextView {
        let view = SemanticRangeTextView()
        view.delegate = context.coordinator
        view.semanticBlockID = blockID
        view.isRenderedSelectionSurface = true
        view.crossBlockHighlight = crossBlockHighlight
        view.crossBlockHighlightColor = editorTheme.selectionColor.map(UIColor.init)
        view.isEditable = false
        view.isSelectable = true
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.textContainerInset = UIEdgeInsets(top: 6, left: 4, bottom: 6, right: 4)
        view.textContainer.lineFragmentPadding = 0
        view.adjustsFontForContentSizeCategory = true
        view.dataDetectorTypes = []
        view.accessibilityIdentifier = identifier
        view.attributedText = renderedText()
        context.coordinator.lastMarkdown = markdown
        context.coordinator.lastFontSize = font.pointSize
        let drag = UILongPressGestureRecognizer(target: context.coordinator,
                                                action: #selector(Coordinator.handleRangeDrag(_:)))
        drag.minimumPressDuration = 0.4
        drag.cancelsTouchesInView = false
        drag.delegate = context.coordinator
        view.addGestureRecognizer(drag)
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        if let view = view as? SemanticRangeTextView {
            view.semanticBlockID = blockID
            view.crossBlockHighlight = crossBlockHighlight
            view.crossBlockHighlightColor = editorTheme.selectionColor.map(UIColor.init)
        }
        if context.coordinator.lastMarkdown != markdown || context.coordinator.lastFontSize != font.pointSize {
            context.coordinator.isUpdating = true
            view.attributedText = renderedText()
            context.coordinator.lastMarkdown = markdown
            context.coordinator.lastFontSize = font.pointSize
            context.coordinator.isUpdating = false
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let measured = uiView.sizeThatFits(CGSize(width: proposal.width ?? 300, height: .greatestFiniteMagnitude))
        return CGSize(width: proposal.width ?? 300, height: max(44, ceil(measured.height)))
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    private func renderedText() -> NSAttributedString {
        let output = NSMutableAttributedString(string: "")
        let parsed = MarkdownSyntax.parse(markdown, useCache: false)
        guard let paragraph = Array(parsed.children).first as? Paragraph else {
            return NSAttributedString(string: markdown, attributes: [.font: font])
        }
        for run in InlineContent.runs(in: paragraph, enableHTML: false) {
            guard case let .text(value, style, _, _) = run else { continue }
            var traits = font.fontDescriptor.symbolicTraits
            if style.bold { traits.insert(.traitBold) }
            if style.italic { traits.insert(.traitItalic) }
            let descriptor = font.fontDescriptor.withSymbolicTraits(traits) ?? font.fontDescriptor
            let styledFont = UIFont(descriptor: descriptor, size: font.pointSize)
            var attributes: [NSAttributedString.Key: Any] = [.font: styledFont]
            if style.link != nil {
                attributes[.foregroundColor] = UIColor.systemBlue
                attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }
            output.append(NSAttributedString(string: value, attributes: attributes))
        }
        return output
    }

    final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
        var parent: VisibleInlineTextView
        var isUpdating = false
        var lastMarkdown: String?
        var lastFontSize: CGFloat?
        private var dragAnchor: MarkdownVisibleTextPosition?

        init(parent: VisibleInlineTextView) { self.parent = parent }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }

        @objc func handleRangeDrag(_ gesture: UILongPressGestureRecognizer) {
            guard let source = gesture.view as? SemanticRangeTextView else { return }
            switch gesture.state {
            case .began:
                guard source.markedTextRange == nil,
                      let position = source.closestPosition(to: gesture.location(in: source)) else { return }
                let offset = source.offset(from: source.beginningOfDocument, to: position)
                dragAnchor = .init(blockID: source.semanticBlockID, offset: offset)
            case .changed:
                guard let anchor = dragAnchor, let window = source.window else { return }
                let point = gesture.location(in: window)
                var hit = window.hitTest(point, with: nil)
                while hit != nil && !(hit is SemanticRangeTextView) { hit = hit?.superview }
                guard let target = hit as? SemanticRangeTextView, target.isRenderedSelectionSurface,
                      target.semanticBlockID != anchor.blockID,
                      target.markedTextRange == nil,
                      let position = target.closestPosition(to: gesture.location(in: target)) else { return }
                let offset = target.offset(from: target.beginningOfDocument, to: position)
                parent.onCrossBlockDrag(anchor, .init(blockID: target.semanticBlockID, offset: offset))
            case .ended, .cancelled, .failed: dragAnchor = nil
            default: break
            }
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            if !isUpdating { parent.onSelection(textView.selectedRange) }
        }
    }
}

@available(iOS 17.0, *)
private struct SourceTextView: UIViewRepresentable {
    @ObservedObject var controller: MarkdownEditorController
    let theme: MarkdownEditorTheme
    let onFocusChanged: ((Bool) -> Void)?
    let onCompositionChanged: ((Bool) -> Void)?

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.accessibilityIdentifier = "markdown-source"
        view.adjustsFontForContentSizeCategory = true
        context.coordinator.defaultTextColor = view.textColor
        context.coordinator.defaultBackgroundColor = view.backgroundColor
        applyTheme(to: view, coordinator: context.coordinator)
        view.autocapitalizationType = .none
        view.autocorrectionType = .no
        view.text = controller.text
        view.selectedRange = controller.selection
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        applyTheme(to: view, coordinator: context.coordinator)
        if view.text != controller.text { view.text = controller.text }
        if view.selectedRange != controller.selection {
            view.selectedRange = controller.selection
            view.scrollRangeToVisible(controller.selection)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    private func applyTheme(to view: UITextView, coordinator: Coordinator) {
        let size = max(1, theme.sourceFontSize ?? 15)
        let baseFont = theme.sourceFontName.flatMap { UIFont(name: $0, size: size) }
            ?? .monospacedSystemFont(ofSize: size, weight: .regular)
        let font = UIFontMetrics(forTextStyle: .body).scaledFont(for: baseFont)
        if view.font != font { view.font = font }
        if let textColor = theme.sourceTextColor.map(UIColor.init) {
            if view.textColor != textColor { view.textColor = textColor }
            coordinator.didOverrideTextColor = true
        } else if coordinator.didOverrideTextColor {
            view.textColor = coordinator.defaultTextColor
            coordinator.didOverrideTextColor = false
        }
        if let backgroundColor = theme.sourceBackgroundColor.map(UIColor.init) {
            if view.backgroundColor != backgroundColor { view.backgroundColor = backgroundColor }
            coordinator.didOverrideBackgroundColor = true
        } else if coordinator.didOverrideBackgroundColor {
            view.backgroundColor = coordinator.defaultBackgroundColor
            coordinator.didOverrideBackgroundColor = false
        }
        if let padding = theme.sourcePadding {
            let inset = UIEdgeInsets(top: padding.top, left: padding.leading,
                                     bottom: padding.bottom, right: padding.trailing)
            if view.textContainerInset != inset { view.textContainerInset = inset }
        } else {
            let inset = UIEdgeInsets(top: 16, left: 12, bottom: 16, right: 12)
            if view.textContainerInset != inset { view.textContainerInset = inset }
        }
    }

    static func dismantleUIView(_ view: UITextView, coordinator: Coordinator) {
        if view.isFirstResponder { view.resignFirstResponder() }
        coordinator.parent.onFocusChanged?(false)
        coordinator.parent.onCompositionChanged?(false)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: SourceTextView
        var defaultTextColor: UIColor?
        var defaultBackgroundColor: UIColor?
        var didOverrideTextColor = false
        var didOverrideBackgroundColor = false
        init(parent: SourceTextView) { self.parent = parent }

        func textViewDidBeginEditing(_ textView: UITextView) { parent.onFocusChanged?(true) }

        func textViewDidEndEditing(_ textView: UITextView) {
            parent.onFocusChanged?(false)
            parent.onCompositionChanged?(false)
        }

        func textViewDidChange(_ textView: UITextView) {
            let composing = textView.markedTextRange != nil
            parent.onCompositionChanged?(composing)
            parent.controller.updateFromInput(text: textView.text, selection: textView.selectedRange,
                                              isComposing: composing)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            parent.controller.setSelection(textView.selectedRange)
        }
    }
}
#endif
