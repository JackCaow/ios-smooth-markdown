import SmoothMarkdown
import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct CustomHeading: MarkdownWidgetBuilder {
    func canBuild(_ node: Markup) -> Bool { node is Heading }
    func build(_ node: Markup, context: MarkdownRenderContext) -> AnyView {
        let text = semanticText(node)
        return AnyView(VStack(alignment: .leading, spacing: 8) {
            // Preserve inline formatting and the reader's registered inline builders.
            if let render = context.renderInline { render(node).accessibilityAddTraits(.isHeader) }
            else { SwiftUI.Text(text).textSelection(.enabled) }
            Button("Copy heading") { copyHeading(text) }
                .accessibilityLabel("Copy heading: \(text)")
        }.padding(12).background(context.styleSheet.linkColor.opacity(0.08))
            .accessibilityElement(children: .contain))
    }
    private func semanticText(_ node: Markup) -> String {
        if let text = node as? Markdown.Text { return text.string }
        if let code = node as? InlineCode { return code.code }
        if let html = node as? InlineHTML { return html.rawHTML }
        if node is SoftBreak || node is LineBreak { return "\n" }
        return node.children.map(semanticText).joined()
    }
    private func copyHeading(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}

func customizedReader() -> some View {
    let registry = BuilderRegistry()
    registry.register("heading", builder: CustomHeading())
    var style = MarkdownStyleSheet.light()
    style.designTokens.mermaid.charts.seriesColors = [.purple, .orange]
    style.designTokens.mermaid.charts.ganttStatusColors[.critical] = .purple
    return SmoothMarkdownView(markdown: "# Agent **result**", styleSheet: style,
        builderRegistry: registry, selectable: true)
}
