import SmoothMarkdown
import SwiftUI
import XCTest

@MainActor
final class EditorToolbarAPITests: XCTestCase {
    func testPublicEditorAcceptsHostToolbarSlotsAndReplacement() {
        let editor = SmoothMarkdownEditor(
            controller: MarkdownEditorController(text: "Example"),
            showToolbar: true,
            toolbarLeading: [AnyView(Button("Host leading") {})],
            toolbarTrailing: [AnyView(Button("Host trailing") {})],
            toolbarBuilder: { _ in AnyView(Text("Host toolbar")) })
        _ = editor
    }
}
