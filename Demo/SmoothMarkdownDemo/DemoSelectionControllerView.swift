import SmoothMarkdown
import SwiftUI

/// A complete prose host for exercising the public programmatic selection API.
struct DemoSelectionControllerView: View {
    let styleSheet: MarkdownStyleSheet
    @State private var controller = SmoothSelectionController()
    @State private var copiedText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button("Select all") { controller.selectAll() }
                    .accessibilityIdentifier("demo-selection-select-all")
                Button("Copy") {
                    if controller.copySelection() { copiedText = controller.selectedText ?? "" }
                }
                .accessibilityIdentifier("demo-selection-copy")
                Button("Clear") {
                    controller.clearSelection()
                    copiedText = ""
                }
                .accessibilityIdentifier("demo-selection-clear")
            }
            .buttonStyle(.bordered)
            SmoothMarkdownView(markdown: "# Native selection\n\nFirst paragraph has selectable words.\n\nSecond paragraph can join the range.",
                               styleSheet: styleSheet, selectable: true,
                               selectionController: controller, scrollable: false)
                .accessibilityIdentifier("demo-selection-controller-reader")
            Text(copiedText).accessibilityIdentifier("demo-selection-copied-text")
            Divider()
            SmoothMarkdownView(markdown: selectionMarkdown, styleSheet: styleSheet,
                               selectable: true, scrollable: false)
        }
    }
}
