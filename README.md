# Smooth Markdown for iOS

A native SwiftUI Markdown reader, streaming reader, and editor. The included `Demo` app provides sample documents and feature pages.

The library is under active development. It supports common Markdown and GFM content; advanced rendering and editing still have [documented limits](docs/reference.md).

## Install

Requires **iOS 17+** and Swift Package Manager. In Xcode, use **File → Add Package Dependencies**, enter:

```text
https://github.com/JackCaow/ios-smooth-markdown
```

Add the **SmoothMarkdown** product to your app target and select version **0.1.0** or later. If you maintain a `Package.swift`, add:

```swift
dependencies: [
    .package(url: "https://github.com/JackCaow/ios-smooth-markdown", from: "0.1.0")
],
targets: [
    .target(name: "YourApp", dependencies: [
        .product(name: "SmoothMarkdown", package: "ios-smooth-markdown")
    ])
]
```

The `Demo` app is for exploration and is not required by the package.

### SVG images

SVG images use a SwiftUI Canvas/CoreGraphics path for common vector shapes and paints. Complex SVGs, including embedded web fonts, use Apple's `WKWebView` with JavaScript disabled. That path retains browser-grade SVG rendering without an external SVG package, but creates a WebKit view and may fetch resources referenced by the SVG. External raster images in the Canvas path use a bounded `URLSession` download and a 32 MiB in-memory cache. The native and WebKit paths were checked against SwiftDraw 0.29's 97 sample SVGs: 96 valid documents render, and the intentionally malformed sample is rejected. Browser rendering can differ from SwiftDraw where its output differs from SVG source semantics.

## Quick start

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

SmoothMarkdownView(
    markdown: source,
    onTapLink: { url in openLink(url) },
    styleSheet: style,
    scrollable: false
)
```

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

Licensed under [MIT](LICENSE).
