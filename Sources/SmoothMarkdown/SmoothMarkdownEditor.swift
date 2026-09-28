#if os(iOS)
import SwiftUI
import UIKit

/// Source editing, live preview, and split view backed by MarkdownEditorController.
@available(iOS 17.0, *)
public struct SmoothMarkdownEditor: View {
    @ObservedObject private var controller: MarkdownEditorController
    private let onSave: ((String) -> Void)?

    public init(controller: MarkdownEditorController, onSave: ((String) -> Void)? = nil) {
        self.controller = controller
        self.onSave = onSave
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Mode", selection: $controller.mode) {
                    ForEach(MarkdownEditorMode.allCases, id: \.self) { mode in
                        Text(mode == .formatted ? "Blocks" : mode.rawValue.capitalized).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                if let onSave {
                    Button("Save") {
                        onSave(controller.text)
                        controller.markSaved()
                    }
                    .disabled(!controller.isDirty)
                }
            }
            .padding(.horizontal)

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
                    }
                }
                .buttonStyle(.borderless)
                .padding(.horizontal)
            }
            .frame(height: 44)

            Divider()
            switch controller.mode {
            case .source:
                SourceTextView(controller: controller)
            case .formatted:
                FormattedBlocksView(controller: controller)
            case .preview:
                SmoothMarkdownView(markdown: controller.text)
            case .split:
                GeometryReader { geometry in
                    VStack(spacing: 0) {
                        SourceTextView(controller: controller)
                            .frame(height: geometry.size.height / 2)
                        Divider()
                        SmoothMarkdownView(markdown: controller.text)
                            .frame(height: geometry.size.height / 2)
                    }
                }
            }
        }
    }

    private func commandButton(_ title: String, _ command: MarkdownEditorCommand) -> some View {
        Button(title) { controller.applyCommand(command) }
            .padding(.horizontal, 5)
    }
}

@available(iOS 17.0, *)
private struct FormattedBlocksView: View {
    @ObservedObject var controller: MarkdownEditorController

    var body: some View {
        let document = controller.semanticDocument
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                Text("Select text in a heading or paragraph, then use its B, I, Link, or Code action. Markdown markers remain visible.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(document.blocks) { block in
                    FormattedBlockRow(controller: controller, block: block)
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
    @State private var inlineSelection = NSRange(location: 0, length: 0)
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
            case .paragraph:
                blockLabel("Paragraph")
                inlineActions
                inlineTextView(font: .preferredFont(forTextStyle: .body), identifier: "paragraph-\(block.id)")
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
    }

    private func inlineTextView(font: UIFont, identifier: String) -> some View {
        SemanticInlineTextView(text: controller.semanticDocument.blockById(block.id)?.plainText ?? block.plainText,
                               selectedRange: inlineSelection, font: font, identifier: identifier,
                               onEdit: { value in
            if value.isEmpty, case .paragraph = block.kind {
                return controller.removeSemanticBlock(id: block.id)
            }
            return controller.replaceSemanticBlockContent(id: block.id, with: value)
        }, onSelection: { inlineSelection = $0 })
        .frame(minHeight: 44)
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
            ForEach(list.items.indices, id: \.self) { index in
                let item = list.items[index]
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
                }
                .padding(.leading, CGFloat(item.indent.count) * 8)
            }
        }
    }
}

@available(iOS 17.0, *)
private struct SemanticInlineTextView: UIViewRepresentable {
    let text: String
    let selectedRange: NSRange
    let font: UIFont
    let identifier: String
    let onEdit: (String) -> Bool
    let onSelection: (NSRange) -> Void

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.textContainerInset = UIEdgeInsets(top: 6, left: 4, bottom: 6, right: 4)
        view.textContainer.lineFragmentPadding = 0
        view.font = font
        view.text = text
        view.autocorrectionType = .default
        view.accessibilityIdentifier = identifier
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.isUpdating = true
        defer { context.coordinator.isUpdating = false }
        view.font = font
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
        if view.selectedRange != controller.selection { view.selectedRange = controller.selection }
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
