# iOS custom appearance and components

## Chart token contract

`MarkdownMermaidTokens.charts` owns `MarkdownMermaidChartTokens`. The same semantic
field names are used across the native libraries; colors and dimensions remain native types.

| Field | Scope |
| --- | --- |
| `seriesColors` | Cyclic palette for pie, timeline, radar and XY series; empty preserves defaults |
| `ganttStatusColors` | Overrides individual Gantt status colors; missing keys inherit defaults |
| `kanbanPriorityColors` | Overrides individual Kanban priorities; missing keys inherit defaults |
| `todayColor`, `todayLineWidth` | Gantt Today marker and its label |
| `overLimitColor`, `atLimitColor`, `belowLimitColor` | Kanban WIP state colors |
| `gridColor`, `gridWidth` | Radar/XY/Gantt grid painting |
| `columnBackground`, `cardBackground` | Kanban column/card fills |
| `sectorBorderColor`, `sectorBorderWidth` | Pie slice separators |
| `seriesLineWidth` | Radar/XY series strokes |
| `pointRadius` | Radar/XY data markers; nil preserves each platform's previous markers |
| `fillOpacity` | Radar series fill and XY bars |
| `barCornerRadius`, `taskCornerRadius` | XY bars and Gantt task bars |
| `columnCornerRadius`, `cardCornerRadius`, `borderWidth` | Kanban decoration; iOS Gantt task borders also use `borderWidth` |
| `priorityStripeWidth` | Kanban task priority stripe |

Null/nil overrides and empty palettes/maps preserve each platform's previous appearance.
They do not enforce pixel-identical defaults. Palette indexes wrap in series order.
`normalized()` returns a safe copy: invalid/negative dimensions become zero, opacity
is clamped to 0...1, and Android `Color.Unspecified` entries are ignored. Transparent
colors are valid explicit overrides. Existing base palettes and source style directives
retain their existing precedence; chart overrides control the listed chart roles.

These are appearance tokens. They do not select a new layout algorithm or make arbitrary
fonts fit fixed chart geometry. Use a custom renderer for different chart structures.

```swift
var style = MarkdownStyleSheet.light()
style.designTokens.mermaid.charts.seriesColors = [.indigo, .orange]
style.designTokens.mermaid.charts.ganttStatusColors[.critical] = .red
style.designTokens.mermaid.charts.kanbanPriorityColors[.high] = .orange
style.designTokens.mermaid.charts.seriesLineWidth = 3
style.designTokens.mermaid.charts.cardCornerRadius = 12
// Use this stylesheet for readers/streams, or pass its Mermaid tokens to a standalone view.
```

## Custom component with native interaction

The complete compilable example is
[`CustomHeading.swift`](../Consumers/Smoke/Sources/ReaderConsumer/CustomHeading.swift).
It registers a heading builder, delegates inline rendering to `context.renderInline`
to preserve formatting, uses the enclosing reader stylesheet, and adds an explicit
semantic Copy action and an accessible label. `selectable: true` enables the reader's
native text selection within the delegated text surface.

**Selection boundary:** arbitrary custom SwiftUI views do not automatically join the
iOS complete-document TextKit selection host. The example supports native local text
selection and explicit heading copy. If uninterrupted document selection is essential,
keep the built-in heading renderer and customize its design tokens instead.

Compile the example using public imports only:

```sh
swift run --package-path Consumers/Smoke ReaderConsumer
```

## Appearance ownership and compatibility

Reader and stream appearance use `MarkdownStyleSheet`. Source/formatted editor controls
and toolbar chrome use `MarkdownEditorTheme`; editor Preview/Split use the reader style.
Host app navigation and conversation controls belong to the app. This separation is
intentional; pass both styles when customizing an editor.

This change is not in the existing published tag. Build the current source branch until
a release includes it. Existing source calls retain their defaults. Android's added
data-class field changes constructor and `copy` JVM signatures: recompile the consumer
and dependent precompiled modules when upgrading; replacing only the AAR is not ABI-safe.
Swift source packages also require recompilation; no new binary compatibility promise
is made.
