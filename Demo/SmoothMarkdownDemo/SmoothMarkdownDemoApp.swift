import SmoothMarkdown
import SwiftUI

@main
struct SmoothMarkdownDemoApp: App {
    var body: some Scene {
        WindowGroup {
            SmoothMarkdownView(markdown: """
            # Smooth Markdown iOS

            A **native** renderer with *inline formatting* and [links](https://github.com/JackCaow/flutter-smooth-markdown).

            > This is the first vertical slice of the Flutter port.

            - [x] Render headings and emphasis
            - [ ] Port the editor

            | Platform | Renderer |
            | --- | --- |
            | iOS | SwiftUI |

            ![GitHub logo](https://github.githubassets.com/images/modules/logos_page/GitHub-Mark.png)

            ```swift
            SmoothMarkdownView(markdown: "Hello")
            ```
            """)
        }
    }
}
