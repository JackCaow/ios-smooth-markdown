# ios-smooth-markdown

Native Swift package and SwiftUI demo, based on [Flutter Smooth Markdown](https://github.com/JackCaow/flutter-smooth-markdown) version 0.10.0.

## Use in an iOS app

Requires iOS 17 or newer. In Xcode, choose **File > Add Package Dependencies**, enter
`https://github.com/JackCaow/ios-smooth-markdown`, select the `main` branch, and add
the **SmoothMarkdown** product to your app target. There is no version tag yet;
pin a commit in shipped apps until a versioned release is available.

For a package manifest, add the same repository and product:

```swift
dependencies: [
    .package(url: "https://github.com/JackCaow/ios-smooth-markdown", branch: "main")
],
targets: [
    .target(name: "YourApp", dependencies: [
        .product(name: "SmoothMarkdown", package: "ios-smooth-markdown")
    ])
]
```

Render Markdown in any SwiftUI screen:

```swift
import SmoothMarkdown
import SwiftUI

struct ArticleView: View {
    let markdown: String

    var body: some View {
        SmoothMarkdownView(markdown: markdown, selectable: true)
    }
}
```

`SmoothMarkdownView` owns vertical scrolling by default. Set `scrollable: false`
when the parent already scrolls, such as a chat list. HTML and parser plugins are
off by default. The `Demo` directory is a runnable example, not an app dependency.

### Flutter and Android API mapping

The SwiftUI entry points are `SmoothMarkdownView(markdown:)`,
`StreamMarkdownView(chunks:)`, and `SmoothMarkdownEditor(controller:)`. The reader
and stream accept the Flutter-style `onTapLink: (String) -> Void` and
`onTapImage: (String, String?, String?) -> Void` callbacks. Their original
`onLinkTap: (URL) -> Void`, `onImageTap: (URL) -> Void`, and
`onImageTapWithMetadata: (String, String?, String?) -> Void` callbacks remain
available. When both matching forms are supplied, both run, with the original
callback first. Image callbacks receive the original Markdown or HTML source,
alt text, and title. `imageBuilder`, `codeBuilder`, `useEnhancedComponents`,
`enableCache`, `selectable`, `plugins`, and `builderRegistry` map directly to the
Flutter reader concepts. Reader and stream default to standard components;
editor Preview and Split default to enhanced components.

```swift
SmoothMarkdownView(
    markdown: source,
    onTapLink: { url in openLink(url) },
    onTapImage: { source, alt, title in showImage(source, alt: alt, title: title) },
    scrollable: false
)
```

The native editor controller starts in Source mode. To match Flutter's default
Formatted mode, set it explicitly before creating the view:

```swift
let controller = MarkdownEditorController(text: source)
controller.mode = .formatted
SmoothMarkdownEditor(controller: controller)
```

Math rendering differs from Flutter's default configuration: iOS currently
recognizes `$...$` and `$$...$$` without an `enableLatex` switch, while Flutter
requires `MarkdownConfig(enableLatex: true)`. Enable that Flutter option when
the same document should render formulas on all platforms.

## Status

On iOS, hosts can customize the menu shown for a selected native reader-text range:

```swift
SmoothMarkdownView(markdown: source, selectable: true)
    .readerTextSelectionMenu { selectedText, suggestedActions in
        UIMenu(children: suggestedActions + [
            UIAction(title: "Quote") { _ in quote(selectedText) }
        ])
    }
```

The modifier also works on `StreamMarkdownView`. Native TextKit selection, including ranges across hosted code, images, and math, supplies the semantic text that Copy would place on the clipboard and UIKit's suggested actions. Image-only selections have no text action. Separate code, math, bundled plugin, and manual cross-block controls offer an Actions button that passes the complete block or chosen range text and a suggested Copy action to the same builder. Their existing Copy controls remain available. SwiftUI `Text` substring selection inside those separate views cannot expose its selection to this UIKit menu builder; custom plugin views keep their own controls.

On iOS, pass a `SmoothSelectionController` to a selectable reader to select its complete native TextKit document from app controls:

```swift
let selection = SmoothSelectionController()
SmoothMarkdownView(markdown: source, selectable: true, selectionController: selection)

selection.selectAll()
selection.selectWordAt(pressLocationOnScreen)
selection.selectParagraphAt(pressLocationOnScreen)
let text = selection.selectedText
selection.copySelection()
selection.clearSelection()
```

The same parameter is available on `StreamMarkdownView`. `isAttached` becomes true after a complete native host mounts; `selectedRange` is a UTF-16 range in its visible text. The two point-based methods take screen coordinates and return false when the point is outside the host. Commands return false when no complete host is attached. Sections rendered by separate legacy views or custom builders cannot provide one document-wide native range, so this controller does not span them. Native UIKit selection remains available on those sections.

Reader and editor work in progress. The package renders headings, paragraphs, inline emphasis, actionable links, fenced code blocks with language tags, copy feedback, horizontal scrolling, selectable text and initial syntax highlighting, blockquotes, ordered/bullet/task lists, GFM tables, footnote references and definitions, collapsible `details` blocks, inline `$...$` and display `$$...$$` math, standalone network or bundled-asset bitmap and SVG images, images mixed with inline text, and horizontal rules. It includes an opt-in parser and renderer plugin registry with mention, hashtag, emoji, admonition, thinking, artifact, and tool-call plugins. `details` blocks work with HTML disabled, match the source package's `<details>` and `<details open>` openers, and render Markdown in the summary and body. Footnotes render named or numeric references as small blue superscripts and definitions as indented labeled content, including indented continuation lines and inline formatting. Mixed text and images wrap at word boundaries; Markdown images render by default, while HTML images require `enableHTML`. Inline and standalone images use their decoded natural dimensions and shrink proportionally to the available line width; HTML width/height remain explicit. On iOS, adjacent supported headings, paragraphs, lists, quotes, and top-level horizontal rules share one native UIKit text selection range, including an accessibility Select all reader text action. The rule is drawn in the range and contributes a blank line when copied. The default continuous TextKit reader hosts built-in standalone and inline images, GFM tables, code blocks, and inline and display math at measured attachment positions. It also includes built-in disclosure summaries and simple footnote definitions when their visible content can be mapped to the native text range. Disclosure expansion updates that range and its Copy result. Copy skips image alt text, includes table cells as tab-separated rows, and includes math as LaTeX without dollar delimiters. Unsupported sections retain their earlier renderer and selection behavior. It supports `AsyncSequence<String>` chunk accumulation with a 50 ms update throttle and completion flush, and blocks unsafe link/image schemes. Opt-in HTML handles common inline formatting, safe link styling, bounded font/color styles, `br`, `hr`, standalone or mixed `img` with pixel dimensions and alt fallback, and `div`/`p`/`center`/`blockquote` containers; streaming withholds incomplete tags outside code. The source editor supports UTF-16 selections, undo/redo, grouped transactions, search, formatting commands, and source/preview/split layouts. Source-backed GFM tables support insertion, cell replacement, row/column edits, alignment, and deletion at the current selection. Blocks mode also recognizes top-level GFM tables and offers cell fields, row/column menus, and alignment controls through the same undo history; untouched table source is preserved exactly, while edited tables use normalized pipe formatting. Full formatted-block editing, semantic table selection/header flags and inline-preserving cell edits, full Mermaid coverage, full HTML behavior, selection across every renderer boundary, dynamic tool-call result/status updates, and complete Flutter style-sheet coverage still need implementation. Do not treat this as a parity release.

In Blocks mode, selecting the endpoints of a complete top-level range can copy or delete lists, tables, raw HTML, code, and prose together. Delete is one undo step and is enabled only if reparsing preserves every untouched block's source and trivia; ambiguous adjacency remains unchanged. This is whole-block editing, not character selection inside those structures.

For source-backed formatting of rendered paragraph or ATX-heading text, pass `MarkdownVisibleTextSelection(source: controller.text, anchor: .init(blockID: "block-0", offset: 2), focus: .init(blockID: "block-1", offset: 4))` to `controller.applySemanticInlineMarkToVisibleTextRange(_:mark:)`. Offsets are UTF-16 positions in rendered text, excluding Markdown markers; this is separate from `MarkdownSemanticTextSelection`, whose offsets refer to the editable raw Markdown body. Bold, italic, and safe links can cover partial text inside existing bold, italic, or links and adjacent prose blocks in one undo step when Swift Markdown can preserve the original visible text and marks. A stale source snapshot, intervening non-prose block, nested link, unsupported inline syntax, split surrogate pair, or unsafe/ambiguous destination rejects the entire command without history changes. Blocks mode now shows a selectable rendered text surface for supported paragraphs and ATX headings. Double-tap or drag to select visible characters, then use Format rendered selection for Bold, Italic, or Link; a long press can drag naturally into an adjacent prose block. Edit Markdown expands the original source-backed field, and Source mode retains the full raw document editor. Unsupported inline syntax stays in the raw field; visible selections cannot cross non-prose blocks.

Simple blockquotes with explicit `>` on every physical line now have editable text rows in Blocks mode. `MarkdownSemanticTextPosition(blockID:offset:quoteLineIndex:)` uses UTF-16 offsets in a row's Markdown body, excluding its exact quote prefix. Start/End at selection feeds the existing Copy/Delete/Replace range controls; Copy includes the starting quote prefix and all selected source line endings. A replacement within one quote block retains untouched source and is one undo step. Cross-line replacement requires identical quote prefixes on every selected line. Lazy continuation lines, differing nesting depths, structured quote children, stale snapshots, and ambiguous reparses leave the source unchanged and can be edited in Source mode. Inline Markdown markers remain visible in the row field; this is source-backed quote editing rather than full rich-text child editing.

SVG files use [SwiftDraw](https://github.com/swhitty/SwiftDraw) 0.29.0, loaded from HTTP(S) or the app bundle. The demo includes `native-vector.svg`; host apps must bundle their own local SVG files. An invalid or missing SVG falls back to its alt/title label.

`SmoothMarkdownView` accepts `enableCache` (default `true`) and `selectable` (default `false`). The bounded shared parse cache is bypassed when caching is disabled or a plugin registry is supplied; streaming readers bypass it. Set `selectable: true` to enable native text selection in prose, lists, quotes, individual table cells, and fenced code. On iOS, adjacent supported prose and top-level rules share one UIKit selection surface with native drag handles. For supported multi-block documents, the continuous TextKit host gives built-in images, GFM tables, code blocks, and display math one native selection range. The legacy fallback still offers **Select surrounding content** for supported blocks when the continuous host is unavailable. Built-in fenced code can join the same range when its Copy button is visible: long-press that existing button for **Select surrounding content**, then choose the range endpoints. Tapping **Copy** on the code block still copies only the code and calls `onCodeCopy`; copying a block range includes the code text and does not call that callback. This block-level control preserves image tap callbacks, the existing table grid, and native display-math rendering and accessibility. A standalone display formula also offers **Copy formula**. It does not provide native cross-surface drag handles or partial table-cell or formula-character ranges; the selection controller does not operate on this separate block-level range. The code text retains its own native character selection and horizontal scrolling. Host-supplied `codeBuilder` views and built-in code with the Copy button hidden remain separate boundaries, as do custom plugin views, HTML sections, and details. The block-range control copies whole blocks; its range endpoints are not continuous native character drag handles. The dedicated [iPhone 17 Pro Simulator capture](benchmarks/evidence/ios-reader-table-range.png) shows the preserved table grid and copied prose plus cells after a table-header long press and block-range selection on iOS 26.0.1; this does not establish physical-device behavior. The [display-math capture](benchmarks/evidence/ios-reader-math-range.png) shows native formula typesetting and copied prose plus LaTeX after a formula long press and block taps on the same Simulator; [four focused UI tests](benchmarks/evidence/ios-reader-math-ui-summary.json) passed across math, table, and image ranges. The [code-block Simulator capture](benchmarks/evidence/ios-reader-code-range.png) shows the original code presentation and copied adjacent prose. In [focused code UI results](benchmarks/evidence/ios-reader-code-ui-summary.json), three tests passed in the first run; the fourth used an incorrect XCTest element type for the native Copy menu, then passed its single-test rerun after the locator was corrected.

Mermaid uses native SwiftUI Canvas for bounded flowchart, sequence, pie, timeline, Gantt, Kanban, radar, XY, class, state, and ER subsets through the opt-in `MermaidPlugin`. Fenced `theme=light`, `dark`, `forest`, and `neutral` select the matching Flutter background, node, text, and edge palette; without an explicit theme, the diagram follows the device appearance. Flowcharts also recognize nested `subgraph` containers and edges to a declared group, with group labels and bounds drawn in Canvas. Structured diagrams recognize class members and common relationship markers, basic state transitions with distinct start/end markers, and ER attributes/cardinalities. Unsupported structured statements fall back to source instead of rendering a partial graph. Composite states, class namespaces, ER subgraphs, advanced styling, full Mermaid syntax, and pixel-identical layout remain future work. The demo has a Structured view with native diagram fixtures; the [iPhone 17 Pro Simulator subgraph screenshot](benchmarks/evidence/ios-mermaid-subgraph.png) records the visible group box and label.

Math uses [SwiftUIMath](https://github.com/gonzalezreal/swiftui-math) 0.1.0 for native SwiftUI typesetting. It supports the library's TeX math subset, including fractions, sums, scripts, Greek letters, and common operators. Full LaTeX documents and arbitrary packages are outside this renderer's scope.

Plugins are disabled unless passed to a reader. `ParserPluginRegistry.builtIns()` enables all eight native plugins; apps can register their own `InlineParserPlugin` or `BlockParserPlugin` implementations with parse and SwiftUI render hooks. Higher priorities run first, duplicate IDs throw, and a plugin returning `nil` lets the next plugin try. For example:

```swift
let plugins = ParserPluginRegistry.builtIns()
SmoothMarkdownView(markdown: "Hi @alice :wave:", plugins: plugins)
```

Blocks editing can use the same opt-in block registry. Pass it when creating `MarkdownEditorController` (or `MarkdownDocumentCodec`) so a host plugin can recognize an otherwise unknown top-level construct such as `:::custom ... :::`. The parsed block has `.plugin(id:match:)`; `match.source` and `MarkdownDocument.sourceRange(of:)` retain the exact source and UTF-16 offsets. `SmoothMarkdownEditor` passes the controller's parser plugins and its optional `builderRegistry` to Preview and Split. A `customBlockBuilder` handles recognized plugin blocks automatically in Blocks mode, with `customBlockEditorBuilder` for edit mode; supply `customBlockMatcher` to select other source blocks or override which blocks use the callbacks. Without a custom view, a plugin block offers Edit source. Registries are copied when passed to the codec/controller, and invalid plugin line counts fall through to ordinary Markdown parsing. Replacement and deletion still require a current source snapshot and preserved neighboring block boundaries.

```swift
let plugins = ParserPluginRegistry()
try plugins.register(MyCustomBlockPlugin()) // conforms to BlockParserPlugin
let controller = MarkdownEditorController(text: markdown, plugins: plugins)
SmoothMarkdownEditor(controller: controller, customBlockBuilder: { context in
    guard case let .plugin(id, _) = context.blockKind, id == "my-custom" else { return nil }
    return AnyView(Text(context.plainText))
})
```

The AI block plugins recognize `<thinking>`/`<think>`/`<|thinking|>` (collapsed by default), `<artifact identifier="..." type="...">`, and `<tool_use>` with `<tool_name>`, optional `<tool_id>`, and `<input>`. Thinking content is shown as selectable text when expanded. Artifact cards show the type/title, let users copy exact content, and support an `onArtifactTap` callback. Tool-call cards show the name and pending status, with expandable parameters and an `onToolCallTap` callback. All three accept an omitted closing tag by consuming through the document end, matching the Flutter parser. Fenced code blocks are protected from plugin parsing. Flutter's parser creates tool calls in pending status; updates to results/status and artifact file download remain future work.

The experimental `MarkdownDocumentCodec` keeps original Markdown bytes and whitespace for untouched blocks. Its semantic model recognizes paragraphs, ATX headings, fenced code, horizontal rules, GFM tables, and ordered, bullet, and task list items with nested markers and indented paragraph continuations. Leading YAML frontmatter is stored as a source-preserving raw block, with its content editable in **Blocks** mode. Blank-separated list bodies, HTML, math, and other constructs remain source-preserving raw blocks. `MarkdownDocumentEditor` supports top-level content replacement and block moves with undo/redo. `MarkdownEditorController.semanticDocument` exposes a snapshot; supported Blocks edits use its source undo history. **Blocks** mode offers selected-text B, I, Link, and inline Code actions for paragraphs and ATX headings, a monospaced fenced-code field, editable GFM tables, and list item and continuation text fields with task checkboxes. Nested items and their continuations can be edited in Blocks mode; Indent and Outdent controls move an item with its descendants. List edits keep untouched indentation, bullets, numbering, spacing, and line endings. Tap Start range and End range on two top-level rows to copy their exact Markdown source or delete simple prose/code/rule blocks as one undo step. Complex lists, tables, and source-only blocks can be copied but cannot be deleted through this range action. Unsupported blocks offer **Edit source**. Source, preview, and split modes remain available. Inline Markdown markers remain visible in block fields. Formatted paragraph and heading rows accept structured block paste. List item and continuation rows accept nested list paste, including an ordinary suffix that stays editable as the parent paragraph after the pasted children. The edit keeps the original marker, task state, adjacent source, and one-step undo. When a multiline paste cannot safely fit the formatted list model, the exact text is inserted at the row selection in Source mode; if the row changed before the paste, the editor shows an error and leaves the clipboard available for retry. Fully visual inline editing, other blank-separated list bodies, free-form cross-block text selection and replacement, general structural paste, selection mapping across blocks, and stable IDs across reparsing remain future work.

The frontmatter field edits content between the leading `---` lines and uses the normal source undo stack. `replaceFrontmatterContent(id:with:)` retains an existing BOM, delimiter spacing, CRLF or LF endings, and all following Markdown. It rejects a new closing `---` line inside the body. It does not validate YAML, create frontmatter in a document without it, or change the delimiters; use Source mode for those actions.

For a character range in a list item's primary text field, use `MarkdownSemanticTextPosition(blockID: "block-1", offset: 3, listItemIndex: 0)`; add `listContinuationIndex` or `listTrailingIndex` for its continuation before or after nested children. Offsets count UTF-16 units in the chosen physical field, including visible Markdown markers. `MarkdownSemanticTextSelection(anchor:focus:source:)` can combine list endpoints with another list line or paragraph/heading. `copySemanticTextRange` retains the first selected line's marker or indent and the exact intervening source. `deleteSemanticTextRange` and `replaceSemanticTextRange` edit any one list field through one undo step after reparsing the complete list and verifying untouched blocks. Flat root primary-line ranges retain their existing safe merge behavior; nested/continuation ranges crossing physical lines can be copied but fail closed for replacement. In Blocks mode, each list field has **Start at selection** and **End at selection** controls. Multiline replacement and ambiguous structural merges remain Source-mode actions. A whole-item nested sibling Copy produces standalone unindented list Markdown, matching Flutter.

`SmoothMarkdownEditor` accepts optional async `onPickImage`, `onImportMarkdown`, `onExportMarkdown`, and `onExportPdf(markdown, html)` callbacks. Hosts can observe source, mode, and UTF-16 source-selection changes through `onChanged`, `onModeChanged`, and `onSelectionChanged`; these callbacks do not emit initial values. `onChanged` emits each committed edit, including rapid edits and undo/redo, while a grouped transaction emits its final source once. Source input during marked-text composition is reported only after commit. `onFocusChanged` reports focus transitions of the source field, as Flutter's source `FocusNode` does. `onPerformanceSnapshot` coalesces state changes on the main actor and reports UTF-16 source length, block count, mode, source composition, and find matches. Native rendering does not track Flutter's formatted segments, segment cache, or suggestion-panel telemetry, so those snapshot properties are nil. It also supports `wikilinkSuggestions`, `onTapWikilink`, and `enableWikilinks` for formatted `[[` completion and preview taps. Its File menu shows image picking and import when supplied, and always offers Markdown export (clipboard fallback without a callback). A nil picker/import result or thrown cancellation leaves the document unchanged; errors are reported through `onHostIOEvent`, and image lifecycle also has `onImagePickEvent`. Successful insertion uses the selection captured when the action began, creates one undo step, and rejects a stale result if the source changed while the host callback was pending. Host apps own file pickers, asset upload, and sharing. The PDF callback passes source Markdown and rendered HTML to the host; the host creates and shares the PDF.

The iOS editor Demo defaults to Flutter example's fixed image URL and sample import response. Its **Host I/O → Use device files and image URLs** option instead opens the iOS document importer/exporter for UTF-8 Markdown and an HTTP(S) image URL entry alert; cancellation and file errors flow through the public async status callbacks. The image URL flow does not select local Photos assets. A host that wants Photos must upload or persist an image and return an `http(s)` URL or bundle asset path accepted by `ImageSource`; writing a temporary `file://` URL into Markdown is unsupported.

Hosts can put SwiftUI actions before or after the native command row with `toolbarLeading` and `toolbarTrailing` arrays of `AnyView`. `toolbarBuilder` receives that row as an `AnyView` and can wrap or replace it; `showToolbar: false` hides it. Focus mode also hides the row. These options follow the Flutter toolbar extension points, although the iOS header, find controls, and native command selection remain separate.

`MarkdownEditorTheme` adds optional per-editor styling via `editorTheme:` or ambient styling via `.markdownEditorTheme(...)`; explicit values win over ambient values. It covers the outer background/border/radius, toolbar and search colors, dividers, source pane background/text/font/padding, preview background/padding, and formatted content padding. It also styles native block cards and labels, table cells and their selected/focused states, formatted block/list/cross-block selection, and slash/wikilink suggestion panels. Unset values retain the existing native Demo appearance. Flutter uses a full-width block header strip and a true table grid; the native editor uses compact labels and rounded cell fields, so their theme fields affect those corresponding surfaces. Flutter's formatted block drop-target colors are not exposed because native formatted block drag and drop does not exist yet. Richer `Decoration`/`TextStyle` objects are also still absent.

In Blocks mode, a selected top-level paragraph/heading range now offers **Transform blocks**. It can group touched prose into one bullet, ordered, or task list or one blockquote, or turn each touched block into a paragraph or H1–H6. It retains inline Markdown and untouched neighboring source, validates the reparsed document, and commits one undo step. A partial text selection transforms its whole touched blocks, as in Flutter. Structural blocks and unsafe reparses remain Source-mode edits; paragraph/heading conversion of multiline prose is not yet supported. The compiled Demo UI test still needs a physical iPhone run.

Run `swift test` for the package. Run `cd Demo && xcodegen generate`, then open `SmoothMarkdownDemo.xcodeproj` for the demo. To run on an iPhone, select a development team for the Demo target in Xcode; a signed build also needs a provisioning profile for `com.jackcaow.smoothmarkdown.demo`. CI compiles package tests and the Demo for generic iOS devices; runtime UI acceptance is performed on a physical iPhone.

### Local DeepSeek development Key

The Demo reads `DEEPSEEK_API_KEY` at launch. To use it on a connected physical iPhone without adding the Key to Git, save it once in macOS Keychain with `security add-generic-password -a "$USER" -s smooth-markdown-deepseek-dev -w` (the command prompts securely), then run `tools/run_demo_on_device_with_deepseek.sh <iPhone-UDID>` after installing the signed Demo. The script injects the Key into that launch only. The repository and screenshots contain no Key.

### Demo navigation

The demo starts with the Flutter example's **Basic Formatting** page. **Examples** opens the ten Markdown samples copied from `example/lib/main.dart`; their manifest and SHA-256 checksums are bundled with the app. Selecting a feature demo pushes a page with Back, preserving the selected example, theme, and language when returning, as in Flutter's example. The navigation bar keeps the sample selector and theme menu; the duplicate subtitle strip below it has been removed. Navigation entries translate with the language choice. The toolbar opens the exact Markdown source, a native editor initialized with that source, and six theme presets: Default Light, Default Dark, GitHub, GitHub Dark, VS Code, and VS Code Dark. The navigation sheet also offers the six Flutter language choices (zh, en, ja, es, fr, ko), plus native Structured Mermaid, Selection, and Performance demos. Markdown source samples retain their original text.

Run `python3 tools/check_flutter_example_parity.py` from this repository to verify the eight bundled fixture groups against the sibling Flutter `example/lib` sources. Pass `--flutter-example-lib /path/to/example/lib` for a different checkout. The command checks the ten home examples, five static demo pages, forty Mermaid diagrams, streaming chunks, AI prompts, Chat List replies, conversation content, and all six Flutter language dictionaries. The Demo reads the synced localization fixture at runtime; native-only labels retain their local translations.

The Flutter special-page entries are present: Math, Streaming, Footnotes, HTML, Chat List, AI Chat, Conversation List, Plugins, and Mermaid. Math, Streaming, Footnotes, and HTML use synced Flutter fixtures; Streaming has Start/Reset and 50 ms chunks, while HTML has its switch and 40 ms word stream; toggling HTML keeps the current stream and reprojects its accumulated source. Chat List has Flutter's welcome text and four local replies: it waits 500 ms for a separate assistant bubble and streams 3–5 character chunks every 20–49 ms. Cache Statistics shows live parse-cache entries, capacity, utilization, and Clear Cache. AI Chat and Chat List keep active replies in a 50 ms throttled accumulator owned by the page; lazy bubble recycling resumes the current text, and completed replies become stable Markdown. AI Chat defaults to DeepSeek and keeps the six Flutter quick prompts in an on-demand navigation menu. The welcome explanation is available in Help, leaving the chat and composer as the main view. Settings accept a runtime DeepSeek Key, model, and thinking toggle; Qwen remains an optional provider. A real request needs a valid Key and network access, while an empty Key uses mock streaming.

Conversation List loads the 12 conversations and 29 exact Markdown messages from Flutter, with unread counts, relative timestamps, light/dark switching, detail bubbles, copy-all, and per-message copy actions. On iOS, long-pressing a prose bubble opens Copy/Select Text actions; Select Text selects the pressed rendered paragraph and opens the native edit menu. Code blocks, images, tables, and other separate render surfaces keep their own selection behavior. Flutter's list row long-press handler is commented out and the page has no swipe or multi-select action. Plugin System uses the synced fixture with clickable mentions and hashtags, two-second feedback, emoji, admonitions, and source expansion. Mermaid has Flutter's 40-diagram gallery and navigation controls; Structured Mermaid remains a parser-focused native view. The Editor page pushes from the toolbar or drawer and returns to the previous sample, uses Flutter's initial fixture, defaults to Blocks mode, and exposes demo image pick, Markdown import/export, PDF export, and four wikilink suggestions. Flutter's 18 default slash commands and search aliases work in formatted paragraphs; Find stays in Blocks mode for visible paragraph, heading, list-item, and quote-line text, highlights matches in native fields, and scrolls the active row into view; Source mode searches the raw Markdown. Cmd+F opens Find, and Cmd+Shift+Return toggles Focus. Focus hides the editor toolbar while retaining the Demo introduction and any open Find bar; iOS keeps a small touch exit button over the document. Custom commands, Find inside table cells, list continuation fields, plugin views, and other Flutter editor shortcuts remain open.

`MermaidDiagramView` and `MermaidPlugin` accept `onNodeTap` and expose accessible hit targets for rendered nodes; the gallery shows the source node ID. `InteractiveMermaidDiagramView` adds a native two-axis viewport with fit-to-view, pinch/pan, double-tap zoom or fit reset, and the same source ID callback; the gallery uses Flutter's 600-point viewer height. The inline diagram keeps its horizontal scrolling. Blocks mode now preserves untouched table source bytes when editing one cell and maps the Source selection after semantic edits. Advanced Mermaid layout and full formatted editing remain open.

The older `--accessibility-fixture`, `--inline-editor-fixture`, `--list-editor-fixture`, and `--host-io-fixture` launch arguments still open their focused test surfaces. The main example navigation and compact DeepSeek chat are covered by focused UI tests on a physical iPhone 17; see [physical-device screenshots](benchmarks/ios-demo-compact-physical-20260929.md).

The public components include `SmoothMarkdownView`, `StreamMarkdownView`, `MarkdownEditorController`, and `SmoothMarkdownEditor` on iOS. Set `SmoothMarkdownView(scrollable: false)` inside a host-owned vertical scroll view such as the chat list to keep one vertical scroll owner. The reader and stream views accept `onImageTapWithMetadata`, which receives the original source, alt text, and title for Markdown, HTML, inline, remote, and bundled images; the existing URL-only `onImageTap` remains available. If both callbacks are set, both run. A host may supply `imageBuilder: (source, alt, title) -> AnyView` on either reader to replace safe image content while keeping the same tap and accessibility wrapper; unsafe image sources never reach that callback. HTML is disabled by default. `CodeBlockOptions` controls the copy button, language tag, and highlighting in enhanced mode. Set `useEnhancedComponents: true` on the reader or stream for decorated H1/H2 headings, quoted blocks, external links, code copy/language/highlighting controls, and built-in AI cards; both default to standard components. `SmoothMarkdownEditor` defaults this option to `true` in Preview and Split modes and accepts `useEnhancedComponents: false` to opt out. The optional `onCodeCopy` callback receives the exact copied code and its language. Initial highlighting covers Swift, Kotlin, Java, Dart, JavaScript, TypeScript, Python, JSON, and shell scripts; unknown languages render as plain code. Pass a new `streamID` when replacing an active async sequence so the view resets its accumulated document. Swift Markdown parses GFM to a markup tree; SwiftUI renders each block directly. The [Flutter source and tests](https://github.com/JackCaow/flutter-smooth-markdown) remain the behavior reference.

To replace a parsed block or inline node while keeping native rendering for unmatched nodes, register a `MarkdownWidgetBuilder` and pass the registry to `SmoothMarkdownView` or `StreamMarkdownView`:

```swift
import Markdown
import SwiftUI

struct CustomHeading: MarkdownWidgetBuilder {
    func canBuild(_ node: Markup) -> Bool { node is Heading }
    func build(_ node: Markup, context: MarkdownRenderContext) -> AnyView {
        AnyView(Text("Custom heading").foregroundColor(.purple))
    }
}

let builders = BuilderRegistry()
builders.register("header", builder: CustomHeading())
SmoothMarkdownView(markdown: "# Hello\n\nNormal paragraph", builderRegistry: builders)
SmoothMarkdownEditor(controller: editorController, builderRegistry: builders)
```

Registry lookup checks the exact Flutter-compatible key first (`header`, `paragraph`, `code_block`, `blockquote`, `list`, `list_item`, `table`, `horizontal_rule`, `html_block`, `text`, `bold`, `italic`, `strikethrough`, `link`, `inline_code`, `image`, `hard_break`), then calls `canBuild` on remaining registered builders in insertion order. Other parsed node types use their Swift type name as the key. A rejected or unregistered node uses the next capable builder or its native renderer. `context.renderBlock` and `context.renderInline` render nested children through the same registry; `context.inlineStyle` exposes inherited Markdown emphasis and link styling. Plugin results use this same registry: implement the `MarkdownPluginNode` overloads of `canBuild` and `build`, register under the plugin ID (for example `mention` or `admonition`), and use `context.renderMarkdown` to render plugin content with the same registry. Unmatched plugin results still use their plugin's `render` method.

The pre-parsed extensions also dispatch through `MarkdownExtensionNode`. Implement its `canBuild` and `build` overloads and register `inline_math`, `block_math`, `footnote_reference`, `footnote_definition`, or `details`. The node exposes the formula or body as `content`, and footnote labels, details summary/open state as `attributes`. `context.renderMarkdown?(node.content)` renders nested definition/details Markdown through the same registry. When HTML is enabled, style content runs dispatch under `bold`, `italic`, `strikethrough`, `underline`, `highlight`, `subscript`, `superscript`, `kbd`, or `styled_span`; the `tag` attribute identifies the HTML element, and any tag attributes are forwarded. Nested HTML styles use the innermost matching builder. Stateful opening/closing HTML tokens are never dispatched by themselves. Native rendering remains the fallback whenever no extension builder accepts the node.

With no matching custom builder, iOS keeps its existing native TextKit selection and copy behavior. A matched custom inline or block view becomes its own selection surface; the host view controls its selection and copy behavior, and cross-block native selection stops at that override. Long custom inline HTML style runs are layout items, so hosts should render a wrapping view if they replace a long span. Table row containers still do not dispatch as registry nodes; table cells do.

`MarkdownStyleSheet` provides host-theme defaults and `light()`, `dark()`, `github(dark:)`, and `vscode(dark:)` presets. Change its public properties to customize colors, fonts, and spacing:

```swift
var style = MarkdownStyleSheet.github(dark: true)
style.linkColor = .cyan
style.blockSpacing = 16
SmoothMarkdownView(markdown: content, styleSheet: style)
```

The demo's Theme menu switches among all presets. `horizontalRuleThickness`, `tableHeaderBackgroundColor`, `listBulletFont`, and `listBulletColor` customize rules, table headers, and list markers. With `enableHTML: true`, `<sub>` and `<sup>` use 75% of the native body size and separate `subscriptStyle` and `superscriptStyle` overrides. The light and dark presets include Flutter's table header colors. Flutter's stylesheet also offers more specialized text styles; its odd and even table row decoration fields are currently declared but unused by the Flutter renderer.
