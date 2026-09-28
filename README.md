# ios-smooth-markdown

Native Swift package and SwiftUI demo, based on [Flutter Smooth Markdown](https://github.com/JackCaow/flutter-smooth-markdown) version 0.10.0.

## Status

Reader and editor work in progress. The package renders headings, paragraphs, inline emphasis, actionable links, code blocks, blockquotes, ordered/bullet/task lists, GFM tables, network images, and horizontal rules. It supports per-text-block selection, basic `AsyncSequence<String>` chunk accumulation, and blocks unsafe link/image schemes. The source editor supports UTF-16 selections, undo/redo, grouped transactions, search, formatting commands, and source/preview/split layouts. Formatted-block editing, table-cell operations, math and Mermaid rendering, streaming throttle/partial-HTML behavior, cross-block selection, plugins, configurable themes, and opt-in HTML still need implementation. Do not treat this as a parity release.

Run `swift test` for the package. Run `cd Demo && xcodegen generate`, then open `SmoothMarkdownDemo.xcodeproj` for the demo.

The public components include `SmoothMarkdownView(markdown:onLinkTap:onImageTap:)`, `StreamMarkdownView(chunks:)`, `MarkdownEditorController`, and `SmoothMarkdownEditor(controller:onSave:)` on iOS. Swift Markdown parses GFM to a markup tree; SwiftUI renders each block directly. The [Flutter source and tests](https://github.com/JackCaow/flutter-smooth-markdown) remain the behavior reference.
