# Enabled HTML text and disclosures

Pass `enableHTML: true` to the reader or streaming reader to enable supported HTML formatting. HTML stays disabled by default. Stored Markdown, `Document.format()` and source UTF-16 offsets are unchanged.

## Small text

`<small>` uses 80% of the resolved inline font size, falling back to the configured paragraph typography token (or the native body default). Configure its appearance with the existing public style system:

```swift
var style = MarkdownStyleSheet.default()
style.smallStyle = MarkdownInlineTextStyle(fontSize: 13, textColor: .secondary)
SmoothMarkdownView(markdown: "Text <small>small text</small>",
                   enableHTML: true, styleSheet: style)
```

Nil `smallStyle` uses the relative default. Explicit attributes override only those attributes and preserve surrounding inline marks. SwiftUI and native selectable text use the same resolver and Dynamic Type scaling. Copy includes the text without HTML wrappers.

## Details within paragraphs and list items

Enabled HTML recognizes complete `<details><summary>…</summary>…</details>` disclosures within a paragraph or list item, including the `open` attribute and nested disclosures. The disclosure occupies an available-width row; preceding and following text retain their original order and list structure. Body Markdown and supported HTML formatting are rendered normally. Code spans, HTML `<code>`, fenced/indented code and escaped opening tags remain literal. Unsupported attributes and incomplete inline disclosures do not produce a disclosure.

Inline disclosure expansion is local SwiftUI state. A paragraph or list containing an inline disclosure therefore uses the SwiftUI reader fallback and cannot participate in a continuous native text selection spanning its dynamic summary/body. The reader's opaque selection projection treats the disclosure as one source-aware atom: copying that whole atom retains the complete original `<details>…</details>` source, alongside the preceding and following text, rather than inventing a fixed range for currently visible content. This is an internal projection contract, not a promise of a native range or a new public selection API.

Existing independent block disclosures retain their expansion-aware native selection behavior. The original Markdown block forms, with `<details>` / `<details open>` and closing tags on separate lines, continue to work independently of generic HTML enablement. Inline HTML disclosures require `enableHTML: true`.
