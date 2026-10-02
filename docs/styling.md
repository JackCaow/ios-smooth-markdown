# Styling the iOS library

Start with a `MarkdownStyleSheet` preset, then change only the values your app needs. Pass that value to each reader or streaming view. Configuration is scoped to the view; no global singleton or dependency is required.

The grouped design token APIs below are included in version 0.3.0. Install the 0.3.0 tag using the [installation guide](../README.md#install); existing legacy stylesheet fields remain supported.

## Document styles and component tokens

`MarkdownStyleSheet` controls document colors, semantic fonts, inline styles, spacing, table borders and code block decoration. Its `designTokens` groups provide the preferred new configuration, including semantic document colors, explicit typography, enhanced components and built-in plugins. Explicit tokens override legacy fields; resetting an optional token restores its legacy fallback. See the [public contract](public-library-contract.md) for the complete precedence rules.

```swift
import SwiftUI
import SmoothMarkdown

var style = MarkdownStyleSheet.github(dark: false)
style.textColor = .primary
style.linkColor = .indigo
style.blockSpacing = 12
style.designTokens.typography.paragraph = MarkdownFontToken(size: 16)
style.designTokens.typography.paragraphLineHeight = 1.5
style.designTokens.heading.accentColor = .indigo
style.designTokens.heading.barWidth = 3
style.designTokens.code.copyLabel = "Copy code"
style.designTokens.details.cornerRadius = 12
style.designTokens.keyboard.backgroundColor = .secondary.opacity(0.12)

SmoothMarkdownView(
    markdown: source,
    useEnhancedComponents: true,
    styleSheet: style
)
```

Use `MarkdownFontToken(fontName:size:weight:monospaced:)` when custom font metrics must match between SwiftUI text and native selectable text. Registered font names are supported; iOS custom fonts must also be included in your application. Fonts scale with Dynamic Type. The typography token group accepts six heading fonts and six line height ratios, ordered H1 through H6. An opaque SwiftUI `Font` assigned to legacy font properties cannot expose its metrics to UIKit; use the explicit font token for consistent selection rendering.

| Group | Controls |
| --- | --- |
| `document` | Semantic text, link, code, quote, table and rule colors |
| `typography` | Paragraph and heading font metrics, line height ratios |
| `heading` | Decoration bar, underline, accent and padding |
| `quote` | Background, icon, border accent and shadow |
| `code` | Header, syntax colors, copy controls and overflow indicator |
| `link` | External link icon; text and underline use `linkStyle` |
| `details` | Disclosure container, summary and body spacing |
| `keyboard` | Keycap colors, font size, spacing and border |
| `math` | Formula font, scale, color and block spacing |
| `plugins` | Mention/hashtag inline styles and admonition/AI panels |
| `mermaid` | Diagram base palette, label font and fence viewport |

Decorative headings, quotes, links and enhanced code controls use `useEnhancedComponents: true`. Document styles and enabled parser plugins remain configurable independently. Legacy stylesheet properties retain their documented behavior; component token colors that are nil inherit existing defaults.

### Rendering scope

On iOS, explicit typography font tokens, heading padding, quote `iconSize`/`iconTypography` and shadows are shared by ordinary and selectable readers. Legacy opaque `iconFont` applies to SwiftUI only; use `iconTypography` for both paths. External link icon offsets also apply to both paths. Keycaps use native glyph decoration even in the ordinary iOS reader. Code overflow indicators use the operating system scrollbar appearance.

## Plugin styles

Register only the extensions you need, then configure the corresponding token group:

```swift
let plugins = ParserPluginRegistry()
try plugins.register(MentionPlugin())
try plugins.register(AdmonitionPlugin())
try plugins.register(ThinkingPlugin())

var style = MarkdownStyleSheet.light()
style.designTokens.plugins.mentionStyle = MarkdownInlineTextStyle(
    fontSize: 17, textColor: .indigo, bold: true
)
style.designTokens.plugins.admonition.cornerRadius = 12
style.designTokens.plugins.admonition.accentColors["warning"] = .orange
style.designTokens.plugins.thinking.backgroundColor = .secondary.opacity(0.08)
style.designTokens.plugins.thinking.titleFont = .subheadline.weight(.semibold)
style.designTokens.plugins.thinking.contentPadding = EdgeInsets(
    top: 8, leading: 16, bottom: 12, trailing: 16
)
```

Pass both `styleSheet: style` and `plugins: plugins` to the reader. AI panel groups are `thinking`, `artifact` and `toolCall`. Each exposes fonts, colors, padding, radius and decoration; tool call status colors are keyed by `ToolCallStatus`. Set border or divider width to zero to hide it. Styling does not enable plugins automatically or execute tool calls.

## Mermaid

`MermaidPalette` is public and mutable. Override a preset or create an RGB palette using `0xRRGGBB` values.

```swift
var palette = MermaidTheme.forest.palette
palette.nodeFill = 0xFFFFFF
palette.text = 0x202020
style.designTokens.mermaid = MarkdownMermaidTokens(
    colors: palette,
    font: .system(size: 12),
    maxHeight: 500
)

let plugins = ParserPluginRegistry()
try plugins.register(MermaidPlugin())
```

Flowchart, class, state, ER and mindmap edges use rounded bends by default. Git branch connections use cubic curves for rounded/curved modes; straight mode remains direct. Configure routing and line details through the same tokens:

```swift
style.designTokens.mermaid.edgeRouting = .curved // .rounded or .straight
style.designTokens.mermaid.cornerRadius = 12
style.designTokens.mermaid.strokeWidth = 1.5
style.designTokens.mermaid.arrowSize = 10
style.designTokens.mermaid.labelPadding = 4
```

Fences reserve their measured viewport height and clip their own painting. Short diagrams are centered; diagrams larger than the viewport remain reachable by scrolling on both axes. Padding separates the fence from surrounding prose.

Custom palette tokens take precedence over named fence themes. Standalone `MermaidDiagramView` also accepts `style: MarkdownMermaidTokens`. The `maxHeight` and `outerPadding` values configure fences; standalone hosts provide their own viewport modifiers. Graph layout geometry and some specialty chart series/status palettes remain diagram-specific. The existing `font` override changes drawn text; native geometry uses the documented default font metrics, so oversized custom fonts require visual validation and can exceed node bounds.

## Editor appearance

The editor has a separate `MarkdownEditorTheme` because source editing, toolbars and table editing are different controls from the reader.

```swift
var editorTheme = MarkdownEditorTheme()
editorTheme.sourceFontSize = 16
editorTheme.sourceTextColor = .primary
editorTheme.toolbarColor = .secondary.opacity(0.08)
editorTheme.blockBorderRadius = 10

SmoothMarkdownEditor(
    controller: controller,
    editorTheme: editorTheme
)
```

Alternatively apply `.markdownEditorTheme(editorTheme)` to an enclosing view. A reader stylesheet is not an editor theme. See the editor API for available source, toolbar, block, table and selection appearance fields.
