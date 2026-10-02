# Migrating public configuration

Version 0.3.0 adds the grouped configuration APIs. Existing flat entry points remain available. The grouped entry point is selected by supplying `renderOptions`; ordinary calls without this argument keep their old meaning.

## Reader

```swift
var labels = MarkdownStrings()
labels.copy = "复制"
labels.copied = "已复制"
SmoothMarkdownView(
    markdown: source,
    renderOptions: .init(useEnhancedComponents: true),
    selectionOptions: .init(mode: .document),
    styleSheet: style,
    resourceOptions: .init(headers: authenticatedHeaders),
    strings: labels
)
```

Import `SmoothMarkdown` and `SwiftUI`. The streaming counterpart accepts the same groups. Keep the resource configuration in application state when using a custom loader.

For parser-only use, add the `SmoothMarkdownCore` product, import it, and call `MarkdownCoreParser().parse(source)` or `.renderHTML(source)`. CocoaPods Core-only consumers import `SmoothMarkdown` and depend on the `SmoothMarkdown/Core` subspec.

## Appearance

Move new color overrides into `designTokens.document`, fonts into `designTokens.typography`, and component decoration into its named token group. Existing fields continue to supply fallbacks. Removing a token override restores that original fallback.

Keep one event handler per action in the new API. The old callback aliases may intentionally both run when both are supplied; do not copy that pattern to the structured API.

## Registries and validation

Registry mutations are observable; remove workarounds that recreate instances solely to refresh readers. Invalid visual values are normalized at consumption. Update old tests that expected a crash for negative/NaN dimensions to assert the safe resolved value instead.

See the [public library contract](public-library-contract.md) for precedence, syntax, module boundaries and release gates.

## Mermaid graph additions

`MermaidKind` adds `gitGraph` and `mindmap`; callers with exhaustive switches must handle these cases. `MarkdownMermaidTokens` preserves its existing initializer and adds mutable `edgeRouting`, `cornerRadius`, `strokeWidth`, `arrowSize` and `labelPadding` properties. Existing callers receive rounded graph edges by default. No external package dependency is introduced.
