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
                Text("Edit block text here. Inline Markdown markers remain editable text.")
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch block.kind {
            case let .heading(level, _):
                blockLabel("Heading \(level)")
                TextField("Heading", text: contentBinding)
                    .font(.system(size: CGFloat(32 - (level - 1) * 3), weight: .bold))
                    .accessibilityIdentifier("heading-\(block.id)")
            case .paragraph:
                blockLabel("Paragraph")
                TextField("Paragraph", text: contentBinding, axis: .vertical)
                    .lineLimit(2...10)
                    .font(.body)
                    .accessibilityIdentifier("paragraph-\(block.id)")
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
        .accessibilityIdentifier("block-\(block.id)")
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
private struct SourceTextView: UIViewRepresentable {
    @ObservedObject var controller: MarkdownEditorController

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
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
