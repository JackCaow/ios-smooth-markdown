import SmoothMarkdown
import SwiftUI

private let demoMarkdown = """
# Smooth Markdown iOS

A **native** renderer with *inline formatting* and [links](https://github.com/JackCaow/flutter-smooth-markdown).

> The source editor now supports formatting commands and preview.

HTML: <b>bold</b> and <span style="color:red">red</span>.

<div align="center">Centered **Markdown**</div>

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
    @State private var enableHTML = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(showEditor ? "Read" : "Open editor") { showEditor.toggle() }
                if !showEditor {
                    Button(enableHTML ? "HTML on" : "Enable HTML") { enableHTML.toggle() }
                }
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            if showEditor {
                SmoothMarkdownEditor(controller: controller)
            } else {
                SmoothMarkdownView(markdown: controller.text, enableHTML: enableHTML)
            }
        }
    }
}
