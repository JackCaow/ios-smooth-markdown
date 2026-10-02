# Opt-in inline formatting plugins

The reader can recognize these plain-text shorthands through its existing parser plugin registry:

| Plugin | Syntax | Contract |
| --- | --- | --- |
| `HighlightPlugin` | `==highlighted text==` | Nonempty content on one line; no leading/trailing whitespace or code spans. |
| `SuperscriptPlugin` | `x^2^` | Nonempty content without whitespace or code spans. |
| `SubscriptPlugin` | `H~2~O` | Numeric content between single tildes, with a letter or number immediately before and after the span. |

```swift
let plugins = ParserPluginRegistry()
try plugins.registerAll([
    HighlightPlugin(),
    SuperscriptPlugin(),
    SubscriptPlugin()
])

SmoothMarkdownView(
    markdown: "==Highlighted== x^2^ H~2~O",
    plugins: plugins,
    selectable: true
)
```

Use the same registry with `StreamMarkdownView`. The plugins are opt-in and are not automatically added by `ParserPluginRegistry.builtIns()`. Default Core and GFM parsing remains unchanged. Even with these plugins, `~deleted~`, `~~deleted~~`, and word-internal nonnumeric `a~deleted~b` keep their GFM strikethrough meaning. Subscript does not claim arbitrary `~text~` support; use the existing enabled-HTML `<sub>` path for broader subscript content.

The shared parser's inline hooks retain the original source and UTF-16 ranges. Code fences, code spans, escaped opening delimiters and link destinations remain under the normal Markdown grammar. Unclosed shorthand remains visible until its closing delimiter arrives. These plugins do not rewrite stored Markdown or enable HTML.

Built-in reader rendering uses `highlightStyle` / `highlightColor`, `superscriptStyle`, and `subscriptStyle` from the host `MarkdownStyleSheet`, including script baseline metrics and Dynamic Type. Formatting stays in native text runs so highlighting can wrap, table cells can retain the same formatting, and selectable text copies visible content without shorthand delimiters. Calling a plugin's `render` method directly uses the library's default resolved style.

An explicit `BuilderRegistry` override for a plugin result takes priority over native token rendering, including alongside HTML keycaps. Such custom views use the existing selection fallback instead of advertising a native text range.
