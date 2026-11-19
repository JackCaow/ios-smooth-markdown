# 0.5.0 Public code highlighter

This minor release makes the enhanced code-block highlighter available to source and diff viewers outside Markdown. Parser behavior, deployment targets and bundled Rust artifacts are unchanged.

- `CodeSyntaxHighlighter.attributed(_:language:dark:enabled:colors:)` returns the same `AttributedString` used by enhanced code blocks, with the default or a custom `MarkdownSyntaxColors` palette.
- `CodeSyntaxHighlighter.normalizedLanguage(_:)` maps fence tags and file extensions such as `kt`, `tsx` or `py` to highlighter language names.

Install SwiftPM tag `0.5.0`. SwiftPM supports iOS 17+ and macOS 14+.
