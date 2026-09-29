import SmoothMarkdown
import SwiftUI

let demoMarkdown = """
# Smooth Markdown iOS

A **native** renderer with *inline formatting* and [links](https://github.com/JackCaow/flutter-smooth-markdown).

```mermaid
xychart-beta
  title "Native metrics"
  x-axis [Jan, Feb, Mar]
  y-axis "Score" 0 --> 100
  bar [35, 58, 77]
  line [28, 50, 83]
```

```mermaid
radar-beta
  title Native skills
  axis Parser, Canvas, Tests, Docs
  curve iOS["iOS"]{8, 7, 9, 6}
  curve Flutter["Flutter"]{9, 8, 9, 8}
  max 10
  ticks 4
```

```mermaid
gantt
  title Release plan
  dateFormat YYYY-MM-DD
  section Build
    Parser :done, p1, 2024-01-01, 10d
    Native views :active, p2, after p1, 14d
  section Ship
    Demo :milestone, m1, after p2, 0d
```

```mermaid
kanban
  title Native work
  todo[To Do] wip:2
    task1[Parser tests] @{ assigned: "Alice", priority: "High" }
  doing[In Progress]
    task2[Canvas rendering] @{ assigned: "Bob", ticket: "IOS-2" }
  done[Done]
    task3[Research]
```

Plugins: hello @john_doe, explore #swiftui, and wave :wave:.

::: tip Native plugins
Mention, hashtag, emoji, admonition, thinking, artifact, and tool-call parsers are enabled in this demo.
:::

<thinking>
Compare the available options before answering.
</thinking>

<artifact identifier="sample-code" type="code" language="swift" title="Greeting.swift">
print("Hello from an artifact")
</artifact>

<tool_use>
<tool_name>search</tool_name>
<tool_id>demo-1</tool_id>
<input>{"query":"SwiftUI Markdown"}</input>
</tool_use>
```mermaid
flowchart TD
  A[Start] --> B{Ready?}
  B -->|Yes| C[Done]
  B -.->|No| D(Retry)
```

```mermaid
sequenceDiagram
  participant U as User
  participant S as Server
  U->>S: Request
  S-->>U: Response
```

```mermaid
pie showData
  title Native chart
  "Swift" : 45
  "Kotlin" : 35
  "Dart" : 20
```

```mermaid
timeline
  title Project milestones
  2024 : Research
  2025 : Native readers
       : More Markdown
  2026 : Diagram support
```

Inline math: $E=mc^2$ and $\\frac{a}{b}$.

$$
\\sum_{i=1}^{n} i = \\frac{n(n+1)}{2}
$$

```swift
let message = "A long code line stays on one line and scrolls horizontally instead of wrapping inside the code panel."
print(message) // Copy this block
```

<details>
<summary>Tap to expand **features**</summary>
Hidden **formatted** content.
- First item
- Second item
</details>

<details open>
<summary>Already expanded</summary>
Visible content by default.
</details>

Inline SVG: before ![Bundled vector](native-vector.svg) after.

![Bundled vector](native-vector.svg)

![Remote SVG](https://upload.wikimedia.org/wikipedia/commons/0/02/SVG_logo.svg)

> The source editor now supports formatting commands and preview.

Footnotes have named[^note] and numeric[^2] references.

[^note]: A **formatted** footnote
    With a continuation line
[^2]: A second footnote

HTML: <b>bold</b> and <span style="color:red">red</span>.

Mixed Markdown: before ![inline GitHub logo](https://github.githubassets.com/images/modules/logos_page/GitHub-Mark.png) after the image.

Mixed HTML: before <img src="https://github.githubassets.com/images/modules/logos_page/GitHub-Mark.png" alt="inline HTML logo" width="32" height="32"> after the image.

<div align="center">Centered **Markdown**</div>

<img src="https://github.githubassets.com/images/modules/logos_page/GitHub-Mark.png" alt="HTML GitHub logo" width="64" height="64">

- [x] Render headings and emphasis
- [ ] Complete formatted-block editing

| Platform | Renderer |
| --- | --- |
| iOS | SwiftUI |

![GitHub logo](https://github.githubassets.com/images/modules/logos_page/GitHub-Mark.png)

```swift
SmoothMarkdownView(markdown: "Hello")
```
"""

let structuredMarkdown = """
# Structured Mermaid

```mermaid
graph LR
  A[Outside] --> B[Done]
  subgraph group [Grouped work]
    C[Inside]
    C --> D[Review]
  end
```

```mermaid
stateDiagram-v2
  [*] --> Pending
  Pending --> Paid: payment
  Paid --> [*]
```

```mermaid
classDiagram
  Animal <|-- Duck
  class Duck {
    +String beakColor
    +swim()
  }
  Pond o-- Duck : contains
```

```mermaid
erDiagram
  CUSTOMER ||--o{ ORDER : places
  CUSTOMER {
    int id PK
    string name
  }
```
"""

let selectionMarkdown = """
# Select across blocks

First paragraph with a [safe link](https://example.com).

Second paragraph has **bold text** and another sentence.

- First list item
- Second list item

> A quoted line joins the same selection range.

![Bundled vector](native-vector.svg)

```swift
print("Code keeps its own copy button")
```
"""

let accessibilityMarkdown = """
# Accessible heading

This paragraph has a [sample link](https://example.com).

- First list item
- Second list item

> Quoted guidance

| Name | Value |
| --- | --- |
| Alpha | 42 |

![Bundled vector](native-vector.svg "Vector title")

Inline ![Inline icon](native-vector.svg) in text.

Footnote text[^a].

[^a]: Footnote explanation.

<details>
<summary>More information</summary>
Expanded explanation.
</details>

```swift
print("Accessible code")
```

```mermaid
pie showData
title Work split
"Reader" : 60
"Editor" : 40
```
"""

let inlineEditorFixture = "Alpha"
let crossBlockEditorFixture = "First\n\nSecond\n\nThird"
let listEditorFixture = "7. First\n8. Second\n\n- [ ] Task"
let emptyListEditorFixture = "- First\n- "
let nestedListEditorFixture = "- Parent\n  - Child\n    continuation\n- Sibling"
let hostIOFixture = "Intro"
