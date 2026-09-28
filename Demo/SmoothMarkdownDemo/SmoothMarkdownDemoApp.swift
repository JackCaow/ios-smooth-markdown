import SmoothMarkdown
import SwiftUI

private let demoMarkdown = """
# Smooth Markdown iOS

A **native** renderer with *inline formatting* and [links](https://github.com/JackCaow/flutter-smooth-markdown).

```swift
let message = "A long code line stays on one line and scrolls horizontally instead of wrapping inside the code panel."
print(message) // Copy this block
```

<details>
<summary>Tap to expand **features**</summary>
Hidden **formatted** content.
- First item
- Second item
</details>

<details open>
<summary>Already expanded</summary>
Visible content by default.
</details>

Inline SVG: before ![Bundled vector](native-vector.svg) after.

![Bundled vector](native-vector.svg)

![Remote SVG](https://upload.wikimedia.org/wikipedia/commons/0/02/SVG_logo.svg)

> The source editor now supports formatting commands and preview.

Footnotes have named[^note] and numeric[^2] references.

[^note]: A **formatted** footnote
    With a continuation line
[^2]: A second footnote

HTML: <b>bold</b> and <span style="color:red">red</span>.

Mixed Markdown: before ![inline GitHub logo](https://github.githubassets.com/images/modules/logos_page/GitHub-Mark.png) after the image.

Mixed HTML: before <img src="https://github.githubassets.com/images/modules/logos_page/GitHub-Mark.png" alt="inline HTML logo" width="32" height="32"> after the image.

<div align="center">Centered **Markdown**</div>

<img src="https://github.githubassets.com/images/modules/logos_page/GitHub-Mark.png" alt="HTML GitHub logo" width="64" height="64">

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
