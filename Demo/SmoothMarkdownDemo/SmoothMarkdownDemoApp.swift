import SmoothMarkdown
import SwiftUI

private let demoMarkdown = """
# Smooth Markdown iOS

A **native** renderer with *inline formatting* and [links](https://github.com/JackCaow/flutter-smooth-markdown).

> The source editor now supports formatting commands and preview.

- [x] Render headings and emphasis
- [ ] Complete formatted-block editing

| Platform | Renderer |
| --- | --- |
| iOS | SwiftUI |

![GitHub logo](https://github.githubassets.com/images/modules/logos_page/GitHub-Mark.png)

```swift
SmoothMarkdownView(markdown: "Hello")
```
"""

@main
struct SmoothMarkdownDemoApp: App {
    var body: some Scene {
        WindowGroup { DemoContentView() }
    }
}

private struct DemoContentView: View {
    @StateObject private var controller = MarkdownEditorController(text: demoMarkdown)
    @State private var showEditor = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(showEditor ? "Read" : "Open editor") { showEditor.toggle() }
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            if showEditor {
                SmoothMarkdownEditor(controller: controller)
            } else {
                SmoothMarkdownView(markdown: controller.text)
            }
        }
    }
}
