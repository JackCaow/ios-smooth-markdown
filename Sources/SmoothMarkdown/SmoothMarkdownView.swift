import Markdown
import SwiftUI

/// Initial native renderer for basic Markdown blocks.
public struct SmoothMarkdownView: View {
    public let markdown: String

    public init(markdown: String) {
        self.markdown = markdown
    }

    public var body: some View {
        let document = Document(parsing: markdown)
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(document.children.enumerated()), id: \.offset) { _, node in
                    block(node)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
    }

    @ViewBuilder
    private func block(_ node: Markup) -> some View {
        if let heading = node as? Heading {
            inline(heading)
                .font(.system(size: CGFloat(32 - (heading.level - 1) * 3), weight: .bold))
        } else if let paragraph = node as? Paragraph {
            inline(paragraph)
                .font(.body)
        } else if let code = node as? CodeBlock {
            SwiftUI.Text(code.code)
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        } else if let quote = node as? BlockQuote {
            SwiftUI.Text("❝  " + plainText(quote))
                .foregroundStyle(.secondary)
        } else {
            SwiftUI.Text(plainText(node))
        }
    }

    private func inline(_ node: Markup) -> SwiftUI.Text {
        node.children.reduce(SwiftUI.Text("")) { result, child in
            result + inlineNode(child)
        }
    }

    private func inlineNode(_ node: Markup) -> SwiftUI.Text {
        if let text = node as? Markdown.Text {
            return SwiftUI.Text(text.string)
        }
        if let code = node as? InlineCode {
            return SwiftUI.Text(code.code).font(.system(.body, design: .monospaced))
        }
        if node is SoftBreak || node is LineBreak {
            return SwiftUI.Text("\n")
        }
        let content = inline(node)
        if node is Strong { return content.bold() }
        if node is Emphasis { return content.italic() }
        if node is Strikethrough { return content.strikethrough() }
        if node is Markdown.Link { return content.foregroundColor(.blue).underline() }
        return content
    }

    private func plainText(_ node: Markup) -> String {
        if let text = node as? Markdown.Text { return text.string }
        if let code = node as? InlineCode { return code.code }
        if let code = node as? CodeBlock { return code.code }
        if node is SoftBreak || node is LineBreak { return "\n" }
        return node.children.map(plainText).joined()
    }
}
