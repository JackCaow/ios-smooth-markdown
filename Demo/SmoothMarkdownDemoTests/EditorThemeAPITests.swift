import SmoothMarkdown
import SwiftUI
import XCTest

@MainActor
final class EditorThemeAPITests: XCTestCase {
    func testPublicEditorAcceptsLocalAndAmbientThemes() {
        let editor = SmoothMarkdownEditor(
            controller: MarkdownEditorController(text: "Example"),
            editorTheme: MarkdownEditorTheme(
                editorBorderColor: .blue,
                toolbarColor: .yellow,
                sourceTextColor: .primary,
                sourceFontSize: 17,
                sourcePadding: EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10)))
            .markdownEditorTheme(MarkdownEditorTheme(
                previewPadding: EdgeInsets(top: 12, leading: 0, bottom: 0, trailing: 0)))
        _ = editor
    }
}
