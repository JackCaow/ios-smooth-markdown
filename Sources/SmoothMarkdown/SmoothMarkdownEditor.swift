#if os(iOS)
import SwiftUI
import UIKit

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
    @FocusState private var searchFieldFocused: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let onSave: ((String) -> Void)?
    private let hostIO: MarkdownEditorHostIO
    private let hasImagePicker: Bool
    private let hasMarkdownImporter: Bool
    private let enableWikilinks: Bool
    private let wikilinkSuggestions: [String]
    private let onTapWikilink: ((String) -> Void)?
    private let capabilities: MarkdownEditorCapabilities
    private let toolbarCommands: [MarkdownEditorCommand]?
    private let customSlashCommands: [MarkdownEditorSlashCommand]
    private let enableSlashCommands: Bool
    private let customBlockMatcher: ((MarkdownDocumentBlock) -> Bool)?
    private let customBlockBuilder: MarkdownEditorCustomBlockBuilder?
    private let customBlockEditorBuilder: MarkdownEditorCustomBlockBuilder?

    public init(controller: MarkdownEditorController, onSave: ((String) -> Void)? = nil,
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
                enableSlashCommands: Bool = true,
                customSlashCommands: [MarkdownEditorSlashCommand] = [],
                customBlockMatcher: ((MarkdownDocumentBlock) -> Bool)? = nil,
                customBlockBuilder: MarkdownEditorCustomBlockBuilder? = nil,
                customBlockEditorBuilder: MarkdownEditorCustomBlockBuilder? = nil) {
        self.controller = controller
        self.onSave = onSave
        self.hasImagePicker = onPickImage != nil
        self.hasMarkdownImporter = onImportMarkdown != nil
        self.enableWikilinks = enableWikilinks
        self.wikilinkSuggestions = wikilinkSuggestions
        self.onTapWikilink = onTapWikilink
        self.capabilities = capabilities
        self.toolbarCommands = toolbarCommands
        self.enableSlashCommands = enableSlashCommands
        self.customSlashCommands = customSlashCommands
        self.customBlockMatcher = customBlockMatcher
        self.customBlockBuilder = customBlockBuilder
        self.customBlockEditorBuilder = customBlockEditorBuilder
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

            if !focusMode {
                ScrollView(.horizontal) {
                    HStack(spacing: dynamicTypeSize.isAccessibilitySize ? 12 : 8) {
                        Button("Undo") { controller.undo() }.disabled(!controller.canUndo)
                        Button("Redo") { controller.redo() }.disabled(!controller.canRedo)
                        if controller.mode != .formatted {
                            ForEach(visibleToolbarCommands, id: \.self) { command in
                                commandButton(command.toolbarTitle, command)
                            }
                        }
                    }
                    .buttonStyle(.borderless)
                    .padding(.horizontal)
                    .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? 8 : 0)
                }
                .frame(minHeight: 44)
            }

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
            }

            if focusMode || searchOpen {
                // Keep the keyboard command active when Focus hides the toolbar or Find is open.
                Button("Find in note", action: openSearch)
                    .keyboardShortcut("f", modifiers: .command)
                    .frame(width: 0, height: 0)
                    .opacity(0)
                    .accessibilityHidden(true)
            }

            Divider()
            ZStack(alignment: .topTrailing) {
                Group {
                    switch controller.mode {
                    case .source:
                        SourceTextView(controller: controller)
                    case .formatted:
                        FormattedBlocksView(controller: controller, enableWikilinks: enableWikilinks,
                                            wikilinkSuggestions: wikilinkSuggestions,
                                            capabilities: capabilities,
                                            enableSlashCommands: enableSlashCommands,
                                            customSlashCommands: customSlashCommands,
                                            customBlockMatcher: customBlockMatcher,
                                            customBlockBuilder: customBlockBuilder,
                                            customBlockEditorBuilder: customBlockEditorBuilder)
                    case .preview:
                        SmoothMarkdownView(markdown: controller.text, plugins: previewPlugins)
                    case .split:
                        GeometryReader { geometry in
                            VStack(spacing: 0) {
                                SourceTextView(controller: controller)
                                    .frame(height: geometry.size.height / 2)
                                Divider()
                                SmoothMarkdownView(markdown: controller.text, plugins: previewPlugins)
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
        .onChange(of: searchQuery) { _, _ in searchIndex = 0; searchHasNavigated = false }
        .onChange(of: controller.text) { _, _ in searchIndex = 0; searchHasNavigated = false }
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
    @ObservedObject var controller: MarkdownEditorController
    let enableWikilinks: Bool
    let wikilinkSuggestions: [String]
    let capabilities: MarkdownEditorCapabilities
    let enableSlashCommands: Bool
    let customSlashCommands: [MarkdownEditorSlashCommand]
    let customBlockMatcher: ((MarkdownDocumentBlock) -> Bool)?
    let customBlockBuilder: MarkdownEditorCustomBlockBuilder?
    let customBlockEditorBuilder: MarkdownEditorCustomBlockBuilder?
    @State private var rangeStartID: String?
    @State private var rangeEndID: String?
    @State private var textRangeStart: MarkdownSemanticTextPosition?
    @State private var textRangeEnd: MarkdownSemanticTextPosition?
    @State private var copiedRange = false
    @State private var showingEditingTips = false
    @State private var textRangeLinkDestination = "https://"
    @State private var showingTextRangeLinkEditor = false

    private var textRange: MarkdownSemanticTextSelection? {
        guard let textRangeStart, let textRangeEnd else { return nil }
        return .init(anchor: textRangeStart, focus: textRangeEnd)
    }

    private var textHighlights: [String: NSRange] {
        guard let textRange else { return [:] }
        return controller.semanticTextHighlightRanges(textRange) ?? [:]
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
                            Text("Select text in a heading or paragraph, then use its B, I, Link, or Code action. Markdown markers remain visible.")
                            Text("Tap Start range on a block, then End range on another block.")
                            Text("Long press and drag between paragraphs or headings to select text. Start and End at selection also work with VoiceOver.")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Select text in a heading or paragraph, then use its B, I, Link, or Code action. Markdown markers remain visible.")
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
                        Text("Long press and drag between paragraphs or headings to select text.")
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
                                              onCrossBlockDrag: { selection in
                        guard controller.copySemanticTextRange(selection) != nil else { return }
                        textRangeStart = selection.anchor
                        textRangeEnd = selection.focus
                        copiedRange = false
                    },
                                              onCaptureTextPosition: { position, isStart in
                        if isStart {
                            textRangeStart = position
                            textRangeEnd = nil
                        } else {
                            textRangeEnd = position
                        }
                        copiedRange = false
                    })
                        }
                        .padding(4)
                        .background(isInSelectedRange(block.id) ? Color.accentColor.opacity(0.12) : .clear,
                                    in: RoundedRectangle(cornerRadius: 9))
                    case .pendingParagraph:
                        PendingListParagraphField(controller: controller)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
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
        .onChange(of: controller.text) { _, _ in clearRange() }
    }

    private func clearRange() {
        rangeStartID = nil
        rangeEndID = nil
        textRangeStart = nil
        textRangeEnd = nil
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
    let onCrossBlockDrag: (MarkdownSemanticTextSelection) -> Void
    let onCaptureTextPosition: (MarkdownSemanticTextPosition, Bool) -> Void
    @State private var customBlockEditing = false
    @State private var customBlockExpectedText: String?
    @State private var inlineSelection = NSRange(location: 0, length: 0)
    @State private var wikilinkSelectedIndex = 0
    @State private var slashSelectedIndex = 0
    @State private var linkDestination = "https://"
    @State private var showLinkEditor = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let customBlockView {
                customBlockView
            } else {
            switch block.kind {
            case let .heading(level, _):
                blockLabel("Heading \(level)")
                inlineActions
                textRangeActions
                inlineTextView(font: UIFontMetrics(forTextStyle: headingTextStyle(level))
                    .scaledFont(for: .systemFont(ofSize: CGFloat(32 - (level - 1) * 3), weight: .bold)),
                               identifier: "heading-\(block.id)")
                wikilinkSuggestionPanel
                slashSuggestionPanel
            case .paragraph:
                blockLabel("Paragraph")
                inlineActions
                textRangeActions
                inlineTextView(font: .preferredFont(forTextStyle: .body), identifier: "paragraph-\(block.id)")
                wikilinkSuggestionPanel
                slashSuggestionPanel
            case let .fencedCode(_, info, _):
                blockLabel(info.isEmpty ? "Code" : "Code · \(info)")
                TextEditor(text: contentBinding)
                    .font(.system(.body, design: .monospaced))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .frame(minHeight: 120)
                    .accessibilityIdentifier("code-\(block.id)")
            case let .table(table):
                FormattedTableView(controller: controller, blockID: block.id, table: table)
            case let .list(list):
                FormattedListView(controller: controller, blockID: block.id, list: list)
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
        .padding(12)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
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
                                .accessibilityIdentifier("slash-suggestion-\(index)")
                        }
                    }
                }
                .frame(maxHeight: 220)
            }
            .font(.subheadline)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(Color(uiColor: .tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
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
                    }
                }
            }
            .font(.subheadline)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(Color(uiColor: .tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func inlineTextView(font: UIFont, identifier: String) -> some View {
        SemanticInlineTextView(text: controller.semanticDocument.blockById(block.id)?.plainText ?? block.plainText,
                               selectedRange: inlineSelection, font: font, identifier: identifier,
                               blockID: block.id, crossBlockHighlight: crossBlockHighlight,
                               onEdit: { value in
            if value.isEmpty, case .paragraph = block.kind {
                return controller.removeSemanticBlock(id: block.id)
            }
            return controller.replaceSemanticBlockContent(id: block.id, with: value)
        }, onSelection: { inlineSelection = $0 }, onCrossBlockDrag: onCrossBlockDrag,
                               suggestionsVisible: !visibleWikilinkSuggestions.isEmpty || !visibleSlashCommands.isEmpty,
                               onSuggestionKey: handleSuggestionKey)
        .frame(minHeight: 44)
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
        Text(title.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
    }
}

@available(iOS 17.0, *)
private struct FormattedTableView: View {
    @ObservedObject var controller: MarkdownEditorController
    let blockID: String
    let table: MarkdownSourceTable
    @State private var selectedCells: MarkdownSemanticTableCellSelection?

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
                                                   onRangeDrag: selectCells)
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
                                                   onRangeDrag: selectCells)
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
            }
        }
        .onChange(of: controller.text) { _, _ in selectedCells = nil }
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
    let blockID: String
    let row: Int
    let column: Int
    let isHeader: Bool
    let isRangeSelected: Bool
    let onRangeDrag: (Int, Int, Int, Int) -> Void

    var body: some View {
        FormattedTableInputField(text: textBinding, placeholder: isHeader ? "Header" : "Cell",
                                 identifier: "table-\(blockID)-\(isHeader ? "header" : "row-\(row)")-col-\(column)",
                                 blockID: blockID, row: isHeader ? 0 : row + 1, column: column,
                                 isRangeSelected: isRangeSelected, onRangeDrag: onRangeDrag)
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
    @Binding var text: String
    let placeholder: String
    let identifier: String
    let blockID: String
    let row: Int
    let column: Int
    let isRangeSelected: Bool
    let onRangeDrag: (Int, Int, Int, Int) -> Void

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
        field.backgroundColor = isRangeSelected ? UIColor.systemBlue.withAlphaComponent(0.2) : .clear
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
    }
}

@available(iOS 17.0, *)
private struct FormattedListView: View {
    @ObservedObject var controller: MarkdownEditorController
    let blockID: String
    let list: MarkdownSourceList
    @State private var focusRequest: (index: Int, token: UUID)?
    @State private var selectedItems: MarkdownSemanticListItemSelection?
    @State private var rangeLinkDestination = "https://"
    @State private var showingRangeLinkEditor = false

    private func isSelected(_ index: Int) -> Bool {
        guard let selectedItems else { return false }
        let first = min(selectedItems.anchorIndex, selectedItems.focusIndex)
        let last = max(selectedItems.anchorIndex, selectedItems.focusIndex)
        return (first...last).contains(index)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("LIST").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
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
                        FormattedListItemField(text: Binding(get: {
                            guard let block = controller.semanticDocument.blockById(blockID),
                                  case let .list(current) = block.kind,
                                  current.items.indices.contains(index) else { return item.content }
                            return current.items[index].content
                        }, set: { value in
                            controller.updateSemanticList(id: blockID) { $0.replacingItemContent(at: index, with: value) }
                        }), blockID: blockID, index: index, isRangeSelected: isSelected(index),
                            onRangeDrag: { anchor, focus in
                                let selection = MarkdownSemanticListItemSelection(blockID: blockID,
                                                                                   anchorIndex: anchor,
                                                                                   focusIndex: focus)
                                if controller.copySemanticListItemRange(selection) != nil {
                                    selectedItems = selection
                                }
                            },
                            focusRequest: focusRequest?.index == index ? focusRequest?.token : nil,
                            onSubmit: { contentOffset in
                                let split = contentOffset < (item.content as NSString).length
                                if controller.submitSemanticListItem(id: blockID, at: index, contentOffset: contentOffset), split {
                                    focusRequest = (index + 1, UUID())
                                }
                        }, onIndent: { outdent in
                            _ = changeIndent(at: index, outdent: outdent)
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
                    ForEach(item.continuations.indices, id: \.self) { lineIndex in
                        let continuation = item.continuations[lineIndex]
                        TextField("Continuation", text: Binding(get: {
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
                        }))
                        .padding(.leading, CGFloat(continuation.indent.count - item.indent.count) * 8)
                        .accessibilityIdentifier("list-\(blockID)-item-\(index)-continuation-\(lineIndex)")
                    }
                }
                .padding(.leading, CGFloat(item.indent.count) * 8)
                .padding(4)
                .background(isSelected(index) ? Color.accentColor.opacity(0.15) : .clear,
                            in: RoundedRectangle(cornerRadius: 6))
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
        .onChange(of: controller.text) { _, _ in selectedItems = nil }
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
    private var dragAnchor: FormattedRangeFieldIdentity?

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
    @Binding var text: String
    let blockID: String
    let index: Int
    let isRangeSelected: Bool
    let onRangeDrag: (Int, Int) -> Void
    let focusRequest: UUID?
    let onSubmit: (Int) -> Void
    let onIndent: (Bool) -> Void

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
        field.rangeIdentity = .list(blockID: blockID, index: index)
        field.onRangeDrag = { anchor, focus in
            guard case let .list(firstBlock, firstIndex) = anchor,
                  case let .list(lastBlock, lastIndex) = focus,
                  firstBlock == lastBlock else { return }
            onRangeDrag(firstIndex, lastIndex)
        }
        field.backgroundColor = isRangeSelected ? UIColor.systemBlue.withAlphaComponent(0.2) : .clear
        return field
    }

    func updateUIView(_ field: FormattedListKeyboardTextField, context: Context) {
        context.coordinator.parent = self
        field.onIndent = onIndent
        field.onReturnAtCaret = onSubmit
        field.rangeIdentity = .list(blockID: blockID, index: index)
        field.onRangeDrag = { anchor, focus in
            guard case let .list(firstBlock, firstIndex) = anchor,
                  case let .list(lastBlock, lastIndex) = focus,
                  firstBlock == lastBlock else { return }
            onRangeDrag(firstIndex, lastIndex)
        }
        field.backgroundColor = isRangeSelected ? UIColor.systemBlue.withAlphaComponent(0.2) : .clear
        if field.text != text { field.text = text }
        if let focusRequest, context.coordinator.handledFocusRequest != focusRequest {
            context.coordinator.handledFocusRequest = focusRequest
            field.becomeFirstResponder()
            field.selectedTextRange = field.textRange(from: field.beginningOfDocument,
                                                      to: field.beginningOfDocument)
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

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            (textField as? FormattedListKeyboardTextField)?.submitAtCurrentCaret()
            return false
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
    var crossBlockHighlight: NSRange? { didSet { setNeedsLayout() } }
    private let rangeLayer = CAShapeLayer()

    override func layoutSubviews() {
        super.layoutSubviews()
        if rangeLayer.superlayer == nil { layer.insertSublayer(rangeLayer, at: 0) }
        rangeLayer.frame = bounds
        rangeLayer.fillColor = tintColor.withAlphaComponent(0.22).cgColor
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
    let text: String
    let selectedRange: NSRange
    let font: UIFont
    let identifier: String
    let blockID: String
    let crossBlockHighlight: NSRange?
    let onEdit: (String) -> Bool
    let onSelection: (NSRange) -> Void
    let onCrossBlockDrag: (MarkdownSemanticTextSelection) -> Void
    let suggestionsVisible: Bool
    let onSuggestionKey: (WikilinkSuggestionKey) -> Void

    func makeUIView(context: Context) -> UITextView {
        let view = SemanticRangeTextView()
        view.delegate = context.coordinator
        view.semanticBlockID = blockID
        view.crossBlockHighlight = crossBlockHighlight
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
        view.font = font
        view.adjustsFontForContentSizeCategory = true
        view.text = text
        view.autocorrectionType = .default
        view.accessibilityIdentifier = identifier
        view.suggestionsVisible = suggestionsVisible
        view.onSuggestionKey = onSuggestionKey
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.isUpdating = true
        defer { context.coordinator.isUpdating = false }
        view.font = font
        if let view = view as? SemanticRangeTextView {
            view.semanticBlockID = blockID
            view.crossBlockHighlight = crossBlockHighlight
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
            return true
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            if !isUpdating { parent.onSelection(textView.selectedRange) }
        }
    }
}

@available(iOS 17.0, *)
private struct SourceTextView: UIViewRepresentable {
    @ObservedObject var controller: MarkdownEditorController

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.accessibilityIdentifier = "markdown-source"
        view.font = UIFontMetrics(forTextStyle: .body)
            .scaledFont(for: .monospacedSystemFont(ofSize: 15, weight: .regular))
        view.adjustsFontForContentSizeCategory = true
        view.textContainerInset = UIEdgeInsets(top: 16, left: 12, bottom: 16, right: 12)
        view.autocapitalizationType = .none
        view.autocorrectionType = .no
        view.text = controller.text
        view.selectedRange = controller.selection
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        if view.text != controller.text { view.text = controller.text }
        if view.selectedRange != controller.selection {
            view.selectedRange = controller.selection
            view.scrollRangeToVisible(controller.selection)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: SourceTextView
        init(parent: SourceTextView) { self.parent = parent }

        func textViewDidChange(_ textView: UITextView) {
            parent.controller.updateFromInput(text: textView.text, selection: textView.selectedRange)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            parent.controller.setSelection(textView.selectedRange)
        }
    }
}
#endif
