# ios-smooth-markdown

Native Swift package and SwiftUI demo, based on [Flutter Smooth Markdown](https://github.com/JackCaow/flutter-smooth-markdown) version 0.10.0.

## Status

Reader and editor work in progress. The package renders headings, paragraphs, inline emphasis, actionable links, code blocks, blockquotes, ordered/bullet/task lists, GFM tables, network images, and horizontal rules. It supports per-text-block selection, `AsyncSequence<String>` chunk accumulation with a 50 ms update throttle and completion flush, and blocks unsafe link/image schemes. Opt-in HTML handles common inline formatting, safe link styling, bounded font/color styles, `br`, `hr`, and `div`/`p`/`center`/`blockquote` containers; streaming withholds incomplete tags outside code. The source editor supports UTF-16 selections, undo/redo, grouped transactions, search, formatting commands, and source/preview/split layouts. Source-backed GFM tables support insertion, cell replacement, row/column edits, alignment, and deletion at the current selection. Formatted-block editing, semantic table selection/header flags and inline-preserving cell edits, math and Mermaid rendering, inline HTML images, full HTML behavior, cross-block selection, plugins, and configurable themes still need implementation. Do not treat this as a parity release.

Run `swift test` for the package. Run `cd Demo && xcodegen generate`, then open `SmoothMarkdownDemo.xcodeproj` for the demo.

The public components include `SmoothMarkdownView(markdown:onLinkTap:onImageTap:enableHTML:)`, `StreamMarkdownView(chunks:streamID:throttleMillis:enableHTML:)`, `MarkdownEditorController`, and `SmoothMarkdownEditor(controller:onSave:)` on iOS. HTML is disabled by default. Pass a new `streamID` when replacing an active async sequence so the view resets its accumulated document. Swift Markdown parses GFM to a markup tree; SwiftUI renders each block directly. The [Flutter source and tests](https://github.com/JackCaow/flutter-smooth-markdown) remain the behavior reference.
