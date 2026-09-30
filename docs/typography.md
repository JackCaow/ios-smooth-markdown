# iOS typography delivery rules

The native Demo uses Apple system text styles so its content follows the user's
Dynamic Type setting. The standard size below is the system's `large` category;
larger accessibility categories scale without a fixed font cap.

| Content | Text role at standard size | Weight |
| --- | --- | --- |
| Reader body and editor prose | `.body` (17 pt) | Regular |
| HTML subscript and superscript | 75% of `.body` (12.75 pt) | Inherits inline weight |
| Reader headings H1–H6 | `.title` / `.title2` / `.title3` / `.headline` / `.subheadline` / `.footnote` | Semibold |
| Chat message body | `.subheadline` (15 pt) | Regular |
| Demo page and chat bar title | `.title3` / `.headline` | Semibold |
| Metadata and timestamps | `.caption` / `.caption2` | Regular |

The selectable reader uses `UITextView` for a single selection range across
adjacent blocks. Its `readerParagraphTextStyle` and `readerHeadingTextStyles`
must match any custom SwiftUI paragraph and heading font roles in a
`MarkdownStyleSheet`. The Demo sets both paths together for chat bubbles.
Explicit inline point sizes scale relative to the surrounding semantic role.
HTML scripts use body-relative baseline shifts that scale with Dynamic Type;
hosts can override their separate text styles in `MarkdownStyleSheet`.
Mermaid Canvas drawings scale their geometry and node tap targets with text size.

Check the reader, source sheet, three chat demos, editor, and Mermaid gallery at
both standard and accessibility text sizes. Text may wrap or make a page taller;
buttons and text must remain reachable without clipping.

Apple references: [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility),
[UIFontMetrics](https://developer.apple.com/documentation/uikit/uifontmetrics),
[ScaledMetric](https://developer.apple.com/documentation/swiftui/scaledmetric).
