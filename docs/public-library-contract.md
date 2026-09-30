# Public library contract

The structured APIs in this source revision are additive. Published 0.2.0 packages do not contain them. Existing flat reader and streaming entry points remain supported for source consumers.

## Configuration ownership

- `MarkdownRenderOptions` owns HTML, caching, scrolling, enhanced components and code control behavior.
- `MarkdownSelectionOptions` selects an explicit ownership mode. Disabled means no reader selection; document mode lets this reader own the complete selectable document. Platform-specific modes are described below.
- `MarkdownEvents` owns callbacks. A structured image interaction produces one event containing original source, alt text and title. Code copy reports source and language. Completion/error callbacks in the event group apply to streams; a static reader does not invent stream lifecycle events. Compatibility aliases are only part of the old flat API.
- `MarkdownBuilders` owns view replacement. Registry keys choose lookup priority; a fallback builder can match other node types through `canBuild`. Restrict that predicate when a builder should handle only one node type. A custom renderer may require an explicit semantic selection contract; a replacement view does not automatically become native selectable text.
- `MarkdownStreamOptions` owns stream scheduling and loading/error presentation. Streams accumulate fragments and bypass the parse cache; completion runs after a finite source ends. Cancellation must not be reported as successful completion.
- `MarkdownResourceOptions` owns encoded image transport, headers, cache policy and loading/error presentation.
- `MarkdownStrings` owns control and accessibility labels. Author-provided document text remains unchanged.

## Appearance precedence

Use `MarkdownStyleSheet.designTokens` for new customization. It groups semantic document colors, typography and component decoration. Resolution creates a separate safe copy; it does not overwrite the application's original stylesheet.

Explicit tokens take precedence over legacy decoration/text-style fields, then scalar fields, then preset defaults. Set an optional token to nil/null to restore the legacy fallback. Explicit code control options take precedence over the enhanced-component default. A nil/null code control configuration follows that default. Explicit copy labels take precedence over `MarkdownStrings`; nil/null labels inherit it.

Typography uses six named heading slots. Compatibility heading arrays are normalized to six slots at the rendering boundary. Invalid dimensions become zero, opacity is clamped to 0...1, and invalid font/line-height values fall back to safe defaults. Platform font handles remain platform-native. Use explicit font metrics when a renderer has separate native and declarative text paths.

## Registry updates

Parser and builder registries expose observable revisions. Register, unregister and clear on the same instance refresh visible readers; application code does not need to recreate the registry. A failed batch registration leaves the registry unchanged. Once a registry is attached to UI, mutate it on the UI thread. Mutation inside the implementation of an already registered plugin is not observable; replace that plugin through the registry.

## Resources

The default loader uses system APIs and bounded caches. Custom loaders return encoded bitmap/SVG bytes and must cooperate with cancellation. Headers participate in cache identity. SVG referenced images/fonts use the same loader. iOS SVG inlining is bounded to 32 references and 8 MiB in total; unresolved browser resources are blocked rather than fetched outside the configured transport. Default policy reuses cache entries; reload fetches a fresh value and replaces the cached value; no-store neither reads nor writes the library cache. A custom loader must also honor no-store in its own implementation.

Credentials must not be forwarded across origins on redirects. Transport overrides do not bypass image URL validation, byte/dimension limits or native image decoding. Keep a stable resource configuration during a document's lifetime; headers automatically isolate account cache entries. iOS provider assignment refreshes identity automatically; Android uses the loader instance as part of the cache key. Replace configuration to reload visible content.

## Syntax and failure behavior

CommonMark 0.31.2 is the base language. GFM tables, task lists, strikethrough, autolinks and tag filtering are separately tested. Footnotes, math, safe HTML and plugin syntax are extensions. HTML is opt-in. Parser conformance, visual rendering coverage and formatted-editor support are separate guarantees.

The parser preserves source ranges. Unsupported math, SVG, Mermaid and editor operations follow the documented fallback or rejection behavior rather than implying unlimited syntax support. Advanced Mermaid layouts and some specialty series/status colors remain component-specific; custom diagram builders provide a replacement path.

## Compatibility and release gates

Before release, run the library suites, official syntax fixtures, independent consumers using public imports, and the platform rendering tests. Reviewed public declaration/signature baselines are checked in CI. `tools/check_public_api.py --update` is for an intentional reviewed API change, not an automatic CI repair.

The source-built package does not promise binary ABI compatibility between compiler toolchains. Recompile consumers when updating. API removals or behavior changes require a migration note and version change. Registry publication is a separate release step; a local build or CI pass is not evidence of registry availability.

## iOS modules and selection

`SmoothMarkdownCore` contains Foundation-only AST/parser/HTML-export code. The `SmoothMarkdown` SwiftPM product re-exports it and includes readers, streaming, plugins and editor. CocoaPods has Core and UI subspecs; the default includes UI. There are no external package dependencies.

Document selection uses the native complete-document host on iOS. Block selection is an iOS-specific mode. On macOS, declarative text selection follows the platform capabilities; the iOS editor is unavailable. Shared explicit typography, heading padding, quote icon typography and quote shadows are applied to both iOS reader paths. Legacy opaque SwiftUI `Font` cannot provide UIKit metrics.

Build verification: `swift test`, `swift run --package-path Consumers/Smoke CoreConsumer`, `swift run --package-path Consumers/Smoke ReaderConsumer`, then `python3 tools/check_public_api.py`. Run the Demo simulator rendering suites before release.
