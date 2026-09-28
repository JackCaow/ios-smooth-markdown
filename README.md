# ios-smooth-markdown

Native Swift package and SwiftUI demo, based on [Flutter Smooth Markdown](https://github.com/JackCaow/flutter-smooth-markdown) version 0.10.0.

## Status

Reader work in progress. The package renders headings, paragraphs, inline emphasis, actionable links, code blocks, blockquotes, ordered/bullet/task lists, GFM tables, network images, and horizontal rules. It supports per-text-block selection, basic `AsyncSequence<String>` chunk accumulation, and blocks unsafe link/image schemes. Math, Mermaid, streaming throttle/partial-HTML behavior, cross-block selection, plugins, configurable themes, opt-in HTML and editing still need implementation. Do not treat this as a parity release.

Run `swift test` for the package. Run `cd Demo && xcodegen generate`, then open `SmoothMarkdownDemo.xcodeproj` for the demo.

The public components are `SmoothMarkdownView(markdown:onLinkTap:onImageTap:)` and `StreamMarkdownView(chunks:)`. Swift Markdown parses GFM to a markup tree; SwiftUI renders each block directly. The [Flutter source and tests](https://github.com/JackCaow/flutter-smooth-markdown) remain the behavior reference.
