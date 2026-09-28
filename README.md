# ios-smooth-markdown

Native Swift package and SwiftUI demo, based on [Flutter Smooth Markdown](https://github.com/JackCaow/flutter-smooth-markdown) version 0.10.0.

## Status

Reader and editor work in progress. The package renders headings, paragraphs, inline emphasis, actionable links, fenced code blocks with language tags, copy feedback, horizontal scrolling, selectable text and initial syntax highlighting, blockquotes, ordered/bullet/task lists, GFM tables, footnote references and definitions, collapsible `details` blocks, inline `$...$` and display `$$...$$` math, standalone network or bundled-asset bitmap and SVG images, images mixed with inline text, and horizontal rules. It includes an opt-in parser and renderer plugin registry with mention, hashtag, emoji, admonition, thinking, artifact, and tool-call plugins. `details` blocks work with HTML disabled, match the source package's `<details>` and `<details open>` openers, and render Markdown in the summary and body. Footnotes render named or numeric references as small blue superscripts and definitions as indented labeled content, including indented continuation lines and inline formatting. Mixed text and images wrap at word boundaries; Markdown images render by default, while HTML images require `enableHTML`. Inline images without explicit dimensions use a 24-point placeholder size. It supports per-text-block selection, `AsyncSequence<String>` chunk accumulation with a 50 ms update throttle and completion flush, and blocks unsafe link/image schemes. Opt-in HTML handles common inline formatting, safe link styling, bounded font/color styles, `br`, `hr`, standalone or mixed `img` with pixel dimensions and alt fallback, and `div`/`p`/`center`/`blockquote` containers; streaming withholds incomplete tags outside code. The source editor supports UTF-16 selections, undo/redo, grouped transactions, search, formatting commands, and source/preview/split layouts. Source-backed GFM tables support insertion, cell replacement, row/column edits, alignment, and deletion at the current selection. Formatted-block editing, semantic table selection/header flags and inline-preserving cell edits, Mermaid rendering, full HTML behavior, cross-block selection, dynamic tool-call result/status updates, and complete Flutter style-sheet coverage still need implementation. Do not treat this as a parity release.

SVG files use [SwiftDraw](https://github.com/swhitty/SwiftDraw) 0.29.0, loaded from HTTP(S) or the app bundle. The demo includes `native-vector.svg`; host apps must bundle their own local SVG files. An invalid or missing SVG falls back to its alt/title label.

Math uses [SwiftUIMath](https://github.com/gonzalezreal/swiftui-math) 0.1.0 for native SwiftUI typesetting. It supports the library's TeX math subset, including fractions, sums, scripts, Greek letters, and common operators. Full LaTeX documents and arbitrary packages are outside this renderer's scope.

Plugins are disabled unless passed to a reader. `ParserPluginRegistry.builtIns()` enables all seven native plugins; apps can register their own `InlineParserPlugin` or `BlockParserPlugin` implementations with parse and SwiftUI render hooks. Higher priorities run first, duplicate IDs throw, and a plugin returning `nil` lets the next plugin try. For example:

```swift
let plugins = ParserPluginRegistry.builtIns()
SmoothMarkdownView(markdown: "Hi @alice :wave:", plugins: plugins)
```

The AI block plugins recognize `<thinking>`/`<think>`/`<|thinking|>` (collapsed by default), `<artifact identifier="..." type="...">`, and `<tool_use>` with `<tool_name>`, optional `<tool_id>`, and `<input>`. Thinking content is shown as selectable text when expanded. Artifact cards show the type/title, let users copy exact content, and support an `onArtifactTap` callback. Tool-call cards show the name and pending status, with expandable parameters and an `onToolCallTap` callback. All three accept an omitted closing tag by consuming through the document end, matching the Flutter parser. Fenced code blocks are protected from plugin parsing. Flutter's parser creates tool calls in pending status; updates to results/status and artifact file download remain future work.

Run `swift test` for the package. Run `cd Demo && xcodegen generate`, then open `SmoothMarkdownDemo.xcodeproj` for the demo.

The public components include `SmoothMarkdownView(markdown:onLinkTap:onImageTap:enableHTML:codeBlockOptions:onCodeCopy:styleSheet:)`, `StreamMarkdownView(chunks:streamID:throttleMillis:enableHTML:onLinkTap:onImageTap:codeBlockOptions:onCodeCopy:onError:styleSheet:)`, `MarkdownEditorController`, and `SmoothMarkdownEditor(controller:onSave:)` on iOS. HTML is disabled by default. `CodeBlockOptions` controls the copy button, language tag, and highlighting. The optional `onCodeCopy` callback receives the exact copied code and its language. Initial highlighting covers Swift, Kotlin, Java, Dart, JavaScript, TypeScript, Python, JSON, and shell scripts; unknown languages render as plain code. Pass a new `streamID` when replacing an active async sequence so the view resets its accumulated document. Swift Markdown parses GFM to a markup tree; SwiftUI renders each block directly. The [Flutter source and tests](https://github.com/JackCaow/flutter-smooth-markdown) remain the behavior reference.

`MarkdownStyleSheet` provides host-theme defaults and `light()`, `dark()`, `github(dark:)`, and `vscode(dark:)` presets. Change its public properties to customize colors, fonts, and spacing:

```swift
var style = MarkdownStyleSheet.github(dark: true)
style.linkColor = .cyan
style.blockSpacing = 16
SmoothMarkdownView(markdown: content, styleSheet: style)
```

The demo's Theme menu switches among all presets. This first native style API covers common reader elements; Flutter's stylesheet also offers more specialized styles and table row decorations.
