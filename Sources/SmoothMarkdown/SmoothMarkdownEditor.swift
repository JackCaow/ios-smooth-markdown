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
                        Text(mode.rawValue.capitalized).tag(mode)
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
                    commandButton("B", .bold)
                    commandButton("I", .italic)
                    commandButton("H1", .heading1)
                    commandButton("List", .unorderedList)
                    commandButton("Task", .taskList)
                    commandButton("Code", .codeBlock)
                    commandButton("Link", .link)
                }
                .buttonStyle(.borderless)
                .padding(.horizontal)
            }
            .frame(height: 44)

            Divider()
            switch controller.mode {
            case .source:
                SourceTextView(controller: controller)
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
