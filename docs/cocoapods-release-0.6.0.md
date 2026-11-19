# 0.6.0 Shared Rust syntax highlighter

Syntax highlighting moves into the shared Rust core, [smooth-rust-core](https://github.com/JackCaow/smooth-rust-core) 0.2.0, which is now the source of truth for `rust-core/` in both SmoothMarkdown libraries. `tools/sync-rust-core.sh <tag>` vendors a tagged snapshot and records it in `rust-core/UPSTREAM`; CI runs `--verify`.

- 40 languages with stateful lexing across lines (interpolation, nested and documentation comments, raw strings, heredocs, JSX, embedded Markdown fences, HTML `<script>`/`<style>`, Vue and Svelte templates) and a structural pass that classifies identifiers by position. The Swift lexer is removed; `CodeSyntaxHighlighter.attributed` and `normalizedLanguage` call the core.
- `CodeSyntaxHighlighter.highlightedLines(_:language:dark:colors:tabWidth:)` highlights a whole file once and returns display lines.
- `CodeSyntaxHighlighter.diffRows(_:language:dark:colors:tabWidth:)` returns `CodeDiffRow` values for unified diffs: hunk headers, context/added/removed rows with line numbers, notes, per-side highlighting and word-level change ranges.
- `MarkdownSyntaxColors` gains optional `parameter`, `attribute`, `tag`, `constant` and `escape` accents.
- Canonical language names come from the core (`tsx`, `xml`, `scss` are distinct). Unsupported languages render as plain text.

Install SwiftPM tag `0.6.0`. SwiftPM supports iOS 17+ and macOS 14+.
