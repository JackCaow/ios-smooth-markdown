import SmoothMarkdown
import SwiftUI
let reader = SmoothMarkdownView(markdown: "# Hello", selectable: true)
let plugins = ParserPluginRegistry()
try plugins.register(MentionPlugin())
var style = MarkdownStyleSheet.light()
style.designTokens.typography.paragraph = MarkdownFontToken(size: 16)
let styled = SmoothMarkdownView(markdown: "@reader", styleSheet: style, plugins: plugins)
let structured = SmoothMarkdownView(markdown: "# Hello", renderOptions: .init(useEnhancedComponents: true), selectionOptions: .init(mode: .document), styleSheet: style)
let chunks = AsyncStream<String> { $0.yield("Hello"); $0.finish() }
let stream = StreamMarkdownView(chunks: chunks, renderOptions: .init(scrollable: false), resourceOptions: .init(headers: ["X-Consumer": "smoke"]))
_ = [AnyView(reader), AnyView(styled), AnyView(structured), AnyView(stream)]
print("Public legacy and structured reader/stream consumers compiled using public imports only")
