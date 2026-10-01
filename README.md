# Smooth Markdown for iOS

A native SwiftUI Markdown reader, streaming reader, and editor. The included `Demo` app provides sample documents and feature pages.

The library is under active development. It supports common Markdown and GFM content; advanced rendering and editing still have [documented limits](docs/reference.md).

## Install

Requires **iOS 17+** and Swift 5.9+. The package has **no third-party dependencies**. The library-owned Rust parser produces a Swift AST through a C bridge; SVG and math rendering use Apple frameworks. The static parser binary is included, so app developers do not need Rust or Cargo.

In Xcode, use **File → Add Package Dependencies**, enter `https://github.com/JackCaow/ios-smooth-markdown`, choose **0.3.2** or later, and add the **SmoothMarkdown** product to your app target. For a `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/JackCaow/ios-smooth-markdown", from: "0.3.2")
],
targets: [
    .target(name: "YourApp", dependencies: [
        .product(name: "SmoothMarkdown", package: "ios-smooth-markdown")
    ])
]
```

CocoaPods `0.3.1` is published to the public Specs registry. Add this to your `Podfile`, then run `pod install --repo-update`:

```ruby
pod 'SmoothMarkdown', '~> 0.3.1'
```

The `Demo` app is for exploration and is not required by the package. If your network cannot access the default CocoaPods CDN, use the official Git Specs source: `source 'https://github.com/CocoaPods/Specs.git'`. See the [release verification](docs/cocoapods-release-0.3.1.md).

For parsing and HTML export without UI frameworks, choose the `SmoothMarkdownCore` SwiftPM product and `import SmoothMarkdownCore`. For CocoaPods, use `pod 'SmoothMarkdown/Core', '~> 0.3.1'` and `import SmoothMarkdown`. The default pod subspec includes UI and its Core dependency. Both distributions include the owned static XCFramework; neither downloads an external parser dependency. CocoaPods supports iOS 17+. For macOS 14+, use SwiftPM, which includes both Apple Silicon and Intel slices.

### SVG and math

The native SVG path uses SwiftUI Canvas/CoreGraphics for common shapes and paints. Complex SVGs, including embedded fonts, use Apple's `WKWebView` with JavaScript disabled; referenced resources may be fetched. External raster images in the Canvas path use a bounded `URLSession` download and a 32 MiB in-memory cache. The implementation rendered all 96 valid SVGs in SwiftDraw 0.29's 97-sample fixture set and rejected its intentionally malformed sample. Browser SVG output can differ from the old renderer's pixels.

Math uses a native TeX-subset parser and Apple's WebKit MathML renderer for layout. A SwiftUI renderer remains visible while a formula is prepared or if WebKit cannot render it. Neither path adds a package dependency.

## Syntax coverage

The shared owned parser passes all **652 CommonMark 0.31.2** official examples with exact HTML output and source-range checks, plus **24 official GFM extension examples** for tables, strikethrough, autolinks, task lists, and tag filtering. Additional extensions include footnotes, math, HTML rendering, and custom parser plugins. Rendering and editing limits are listed in the [reference](docs/reference.md).

Version `0.3.1` includes the grouped options, resource loading, localized labels, design tokens and independent parsing core introduced in `0.3.0`. It adds native incremental stream sessions, bounded tail transport and background parsing with latest-prefix coalescing. Final publication, cancellation and worker cleanup are verified. Reader, streaming, editor syntax recognition, plugins and HTML export use the shared owned parser. Existing flat entry points remain supported. See the [public library contract](docs/public-library-contract.md) and [migration guide](docs/public-api-migration.md).

Version `0.3.2` adds backslash formula delimiters, broader native code highlighting, localized Mermaid fallback and corrected system typography tokens. The public API keeps existing entry points.

## Quick start

[中文接入手册](docs/integration-guide.zh-CN.md)：安装、样式、流式回复、图片、插件、编辑器及最新固定提交接入。

### Render a document

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

The reader scrolls vertically by default. In a chat list or another parent scroll view, set `scrollable: false` so the parent owns scrolling.

### Render an async stream

```swift
import SmoothMarkdown
import SwiftUI

struct ReplyView: View {
    let chunks: AsyncStream<String>

    var body: some View {
        StreamMarkdownView(
            chunks: chunks,
            onComplete: { fullMarkdown in
                print("Received \(fullMarkdown.count) characters")
            },
            scrollable: false
        )
    }
}
```

Pass an `AsyncSequence<String>` of Markdown chunks. The view accumulates updates with a 50 ms default throttle. Change `streamID` when replacing an active stream to clear the previous content.

### Edit Markdown

```swift
import SmoothMarkdown
import SwiftUI

struct ComposeView: View {
    @StateObject private var controller = MarkdownEditorController(text: "# Draft")

    var body: some View {
        SmoothMarkdownEditor(controller: controller, onSave: { markdown in
            print("Save:", markdown)
        })
    }
}
```

The editor supports Source, Preview, Split, and Blocks modes. Its controller starts in Source mode; set `controller.mode = .formatted` to start in Blocks mode. Your app supplies file picking, export, and sharing behavior through the editor's optional host callbacks.

## Features and customization

| Need | Entry point |
| --- | --- |
| Style colors, fonts, and spacing | `MarkdownStyleSheet`, passed as `styleSheet:` |
| Customize enhanced components and plugins | `styleSheet.designTokens` |
| Group rendering, selection and callbacks | `MarkdownRenderOptions`, `MarkdownSelectionOptions`, `MarkdownEvents` |
| Configure image transport and control labels | `MarkdownResourceOptions`, `MarkdownStrings` |
| Handle link and image taps | `onTapLink`, `onTapImage` on reader or stream |
| Enable native text selection | `selectable: true`; optional `SmoothSelectionController` |
| Render supported HTML | `enableHTML: true` (off by default) |
| Use decorated code, headings, and links | `useEnhancedComponents: true` |
| Parse mentions, emoji, Mermaid, and other extensions | Pass a `ParserPluginRegistry` |
| Replace parsed views | Pass a `BuilderRegistry` |
| Customize editor appearance | `MarkdownEditorTheme` |

For example:

```swift
var style = MarkdownStyleSheet.github(dark: true)
style.linkColor = .cyan
style.designTokens.typography.paragraph = MarkdownFontToken(size: 16)
style.designTokens.typography.paragraphLineHeight = 1.5
style.designTokens.heading.accentColor = .cyan
style.designTokens.code.copyLabel = "Copy code"

SmoothMarkdownView(
    markdown: source,
    onTapLink: { url in openLink(url) },
    useEnhancedComponents: true,
    styleSheet: style,
    scrollable: false
)
```

For font metrics shared by SwiftUI and native selectable text, use `designTokens.typography` with explicit `MarkdownFontToken` values. Component styles are scoped to each reader. Mermaid palettes and editor appearance have dedicated configuration; see the [styling guide](docs/styling.md) for complete examples and supported customization boundaries.

The string-based tap callbacks are convenient when the host app stores URLs as strings. Existing URL-based `onLinkTap` and `onImageTap` callbacks remain available.

## Run the demo

The iOS demo contains Markdown samples, streaming and chat pages, a Mermaid gallery, an editor, themes, and localized UI. Install XcodeGen, then from the repository root:

```sh
cd Demo
xcodegen generate
open SmoothMarkdownDemo.xcodeproj
```

Select the **SmoothMarkdownDemo** scheme and an iOS Simulator. For a physical iPhone, configure your development team and a provisioning profile for the Demo target. AI Chat uses mock streaming without a Key; live provider setup is described in the [demo notes](docs/reference.md#local-deepseek-development-key).

## Compatibility and limits

- `Package.swift` declares iOS 17+ and macOS 14+. The editor is iOS-specific; use the reader APIs for macOS.
- HTML and parser plugins are opt-in. The reader recognizes supported math without a separate enable switch.
- Mermaid and formatted editing support a defined subset of syntax and actions. Custom renderers can interrupt continuous native text selection. See the [detailed reference](docs/reference.md) before relying on those behaviors.

## Development and further reading

Run `swift test` for package tests. The demo project is generated from `Demo/project.yml` with XcodeGen.

- [Detailed API, implementation, and demo reference](docs/reference.md)
- [Custom block builders](docs/custom-blocks.md)
- [Typography](docs/typography.md)
- [Public configuration contract](docs/public-library-contract.md)
- [Owned parser and binary distribution](docs/rust-parser.md)

Licensed under [MIT](LICENSE).

### Streaming performance

Eligible `StreamMarkdownView` streams reuse committed native AST and Markup blocks, share each published parse with the visible/selection projection, and retain stable block view identity. Plugins, formulas/footnotes, enabled HTML and details keep their full-document compatibility path; references invalidate earlier blocks. Large single containers may see no improvement. Eligible streams parse and decode on a serial background worker. Pending updates coalesce complete source prefixes; the final prefix is published before `onComplete`. Native AST state advances even when an intermediate UI update is skipped. Markup adaptation and UI publication remain on the main thread. Compatibility paths still run on the UI thread to preserve plugin behavior.

See [same-input parser measurements](benchmarks/README.md) and [raw evidence](benchmarks/evidence/ios-stream-parser-performance.json). Host parse timings exclude SwiftUI layout/drawing and do not establish device frame-rate improvement.
