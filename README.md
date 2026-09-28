# ios-smooth-markdown

Native Swift package and SwiftUI demo, based on [Flutter Smooth Markdown](https://github.com/JackCaow/flutter-smooth-markdown) version 0.10.0.

## Status

Research scaffold and first vertical slice. The package renders headings, paragraphs, inline emphasis, code blocks and blockquotes. Links are visually styled but not interactive yet. Lists, tables, images, math, Mermaid, streaming, selection and editing still need implementation. Do not treat this as a parity release.

Run `swift build` for the package. Run `cd Demo && xcodegen generate`, then open `SmoothMarkdownDemo.xcodeproj` for the demo.

The public component is `SmoothMarkdownView(markdown:)`. Swift Markdown parses GFM to a markup tree; SwiftUI renders each block directly. The [Flutter source and tests](https://github.com/JackCaow/flutter-smooth-markdown) remain the behavior reference.
