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
    private let onSave: ((String) -> Void)?
    private let hostIO: MarkdownEditorHostIO
    private let hasImagePicker: Bool
    private let hasMarkdownImporter: Bool
    private let enableWikilinks: Bool
    private let wikilinkSuggestions: [String]
    private let onTapWikilink: ((String) -> Void)?

    public init(controller: MarkdownEditorController, onSave: ((String) -> Void)? = nil,
                onPickImage: MarkdownEditorHostIO.ImagePicker? = nil,
                onImagePickEvent: ((MarkdownEditorImagePickEvent) -> Void)? = nil,
                onImportMarkdown: MarkdownEditorHostIO.MarkdownImporter? = nil,
                onExportMarkdown: MarkdownEditorHostIO.MarkdownExporter? = nil,
                onExportPDF: MarkdownEditorHostIO.PDFExporter? = nil,
                onHostIOEvent: ((MarkdownEditorHostIOEvent) -> Void)? = nil,
                enableWikilinks: Bool = true,
                wikilinkSuggestions: [String] = [],
                onTapWikilink: ((String) -> Void)? = nil) {
        self.controller = controller
        self.onSave = onSave
        self.hasImagePicker = onPickImage != nil
        self.hasMarkdownImporter = onImportMarkdown != nil
        self.enableWikilinks = enableWikilinks
        self.wikilinkSuggestions = wikilinkSuggestions
        self.onTapWikilink = onTapWikilink
        self.hostIO = MarkdownEditorHostIO(controller: controller, onPickImage: onPickImage,
                                           onImportMarkdown: onImportMarkdown, onExportMarkdown: onExportMarkdown,
                                           onExportPDF: onExportPDF,
                                           onImagePickEvent: onImagePickEvent, onEvent: onHostIOEvent)
    }

    public var body: some View {
        VStack(spacing: 0) {
            if !focusMode {
                HStack {
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
                .padding(.horizontal)
            }

            if !focusMode {
                ScrollView(.horizontal) {
                    HStack(spacing: 2) {
                        Button("Undo") { controller.undo() }.disabled(!controller.canUndo)
                        Button("Redo") { controller.redo() }.disabled(!controller.canRedo)
                        if controller.mode != .formatted {
                            commandButton("B", .bold)
                            commandButton("I", .italic)
                            commandButton("H1", .heading1)
                            commandButton("List", .unorderedList)
                            commandButton("Task", .taskList)
                            commandButton("Code", .codeBlock)
                            commandButton("Link", .link)
                            commandButton("Table", .table)
                            if enableWikilinks { commandButton("Wiki", .wikilink) }
                        }
                    }
                    .buttonStyle(.borderless)
                    .padding(.horizontal)
                }
                .frame(height: 44)
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
                                            wikilinkSuggestions: wikilinkSuggestions)
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
        guard enableWikilinks else { return nil }
        let registry = ParserPluginRegistry.builtIns()
        try? registry.register(WikilinkPlugin(onTapWikilink: onTapWikilink))
        return registry
    }

    private func commandButton(_ title: String, _ command: MarkdownEditorCommand) -> some View {
        Button(title) { controller.applyCommand(command) }
            .padding(.horizontal, 5)
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
    let command: MarkdownEditorCommand

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
    @ObservedObject var controller: MarkdownEditorController
    let enableWikilinks: Bool
    let wikilinkSuggestions: [String]

    var body: some View {
        let document = controller.semanticDocument
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                Text("Select text in a heading or paragraph, then use its B, I, Link, or Code action. Markdown markers remain visible.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(document.blocks) { block in
                    FormattedBlockRow(controller: controller, block: block,
                                      enableWikilinks: enableWikilinks,
                                      wikilinkSuggestions: wikilinkSuggestions)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
    }
}

@available(iOS 17.0, *)
private struct FormattedBlockRow: View {
    @ObservedObject var controller: MarkdownEditorController
    let block: MarkdownDocumentBlock
    let enableWikilinks: Bool
    let wikilinkSuggestions: [String]
    @State private var inlineSelection = NSRange(location: 0, length: 0)
    @State private var wikilinkSelectedIndex = 0
    @State private var slashSelectedIndex = 0
    @State private var linkDestination = "https://"
    @State private var showLinkEditor = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch block.kind {
            case let .heading(level, _):
                blockLabel("Heading \(level)")
                inlineActions
                inlineTextView(font: .systemFont(ofSize: CGFloat(32 - (level - 1) * 3), weight: .bold),
                               identifier: "heading-\(block.id)")
                wikilinkSuggestionPanel
                slashSuggestionPanel
            case .paragraph:
                blockLabel("Paragraph")
                inlineActions
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
            case .raw:
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

    private var activeSlashMatch: MarkdownSlashCommandMatch? {
        controller.slashCommandMatch(inBlock: block.id, selection: inlineSelection)
    }

    private var visibleSlashCommands: [EditorSlashCommand] {
        guard let match = activeSlashMatch else { return [] }
        return EditorSlashCommand.builtIns.filter {
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
        if controller.applySlashCommand(item.command, match: match) {
            slashSelectedIndex = 0
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
                               onEdit: { value in
            if value.isEmpty, case .paragraph = block.kind {
                return controller.removeSemanticBlock(id: block.id)
            }
            return controller.replaceSemanticBlockContent(id: block.id, with: value)
        }, onSelection: { inlineSelection = $0 },
                               suggestionsVisible: !visibleWikilinkSuggestions.isEmpty || !visibleSlashCommands.isEmpty,
                               onSuggestionKey: handleSuggestionKey)
        .frame(minHeight: 44)
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
            Button("B") { apply(.bold) }.accessibilityLabel("Bold selection")
            Button("I") { apply(.italic) }.accessibilityLabel("Italic selection")
            Button("Link") { showLinkEditor = true }.accessibilityLabel("Link selection")
            Button("Code") { apply(.code) }.accessibilityLabel("Inline code selection")
        }
        .font(.caption.weight(.semibold))
        .buttonStyle(.bordered)
        .disabled(inlineSelection.length == 0)
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
            ScrollView(.horizontal) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        ForEach(table.headers.indices, id: \.self) { column in
                            VStack(alignment: .leading, spacing: 4) {
                                FormattedTableCell(controller: controller, blockID: blockID,
                                                   row: 0, column: column, isHeader: true)
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
                                                   row: row, column: column, isHeader: false)
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

    var body: some View {
        TextField(isHeader ? "Header" : "Cell", text: textBinding)
            .textFieldStyle(.roundedBorder)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .accessibilityIdentifier("table-\(blockID)-\(isHeader ? "header" : "row-\(row)")-col-\(column)")
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
private struct FormattedListView: View {
    @ObservedObject var controller: MarkdownEditorController
    let blockID: String
    let list: MarkdownSourceList

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("LIST").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
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
                        TextField("List item", text: Binding(get: {
                            guard let block = controller.semanticDocument.blockById(blockID),
                                  case let .list(current) = block.kind,
                                  current.items.indices.contains(index) else { return item.content }
                            return current.items[index].content
                        }, set: { value in
                            controller.updateSemanticList(id: blockID) { $0.replacingItemContent(at: index, with: value) }
                        }))
                        .accessibilityIdentifier("list-\(blockID)-item-\(index)")
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
            }
        }
    }

    private func changeIndent(at index: Int, outdent: Bool) -> Bool {
        controller.updateSemanticList(id: blockID) { list in
            outdent ? list.outdentingItem(at: index) : list.indentingItem(at: index)
        }
    }
}

@available(iOS 17.0, *)
private enum WikilinkSuggestionKey { case next, previous, accept }

@available(iOS 17.0, *)
private final class WikilinkInputTextView: UITextView {
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

@available(iOS 17.0, *)
private struct SemanticInlineTextView: UIViewRepresentable {
    let text: String
    let selectedRange: NSRange
    let font: UIFont
    let identifier: String
    let onEdit: (String) -> Bool
    let onSelection: (NSRange) -> Void
    let suggestionsVisible: Bool
    let onSuggestionKey: (WikilinkSuggestionKey) -> Void

    func makeUIView(context: Context) -> UITextView {
        let view = WikilinkInputTextView()
        view.delegate = context.coordinator
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.textContainerInset = UIEdgeInsets(top: 6, left: 4, bottom: 6, right: 4)
        view.textContainer.lineFragmentPadding = 0
        view.font = font
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

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: SemanticInlineTextView
        var isUpdating = false
        init(parent: SemanticInlineTextView) { self.parent = parent }

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
        view.font = .monospacedSystemFont(ofSize: 15, weight: .regular)
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
