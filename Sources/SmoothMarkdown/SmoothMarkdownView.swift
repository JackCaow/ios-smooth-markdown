import Markdown
import SwiftUI

/// Renders the currently supported CommonMark and GFM blocks with SwiftUI.
public struct SmoothMarkdownView: View {
    public let markdown: String
    public let onLinkTap: ((URL) -> Void)?
    public let onImageTap: ((URL) -> Void)?

    public init(
        markdown: String,
        onLinkTap: ((URL) -> Void)? = nil,
        onImageTap: ((URL) -> Void)? = nil
    ) {
        self.markdown = markdown
        self.onLinkTap = onLinkTap
        self.onImageTap = onImageTap
    }

    public var body: some View {
        let document = MarkdownSyntax.parse(markdown)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(Array(document.children.enumerated()), id: \.offset) { _, node in
                    block(node)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        .environment(\.openURL, OpenURLAction { url in
            guard MarkdownSyntax.isSafeLink(url) else { return .discarded }
            if let onLinkTap {
                onLinkTap(url)
                return .handled
            }
            return .systemAction
        })
    }

    private func block(_ node: Markup) -> AnyView {
        AnyView(blockContent(node))
    }

    @ViewBuilder
    private func blockContent(_ node: Markup) -> some View {
        if let heading = node as? Heading {
            inline(heading)
                .font(.system(size: CGFloat(32 - (heading.level - 1) * 3), weight: .bold))
                .textSelection(.enabled)
        } else if let paragraph = node as? Paragraph {
            if let image = paragraph.childCount == 1 ? paragraph.child(at: 0) as? Markdown.Image : nil {
                imageView(image)
            } else {
                inline(paragraph).font(.body).textSelection(.enabled)
            }
        } else if let code = node as? CodeBlock {
            VStack(alignment: .leading, spacing: 6) {
                if let language = code.language, !language.isEmpty {
                    SwiftUI.Text(language).font(.caption).foregroundStyle(.secondary)
                }
                SwiftUI.Text(code.code)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        } else if let quote = node as? BlockQuote {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(quote.children.enumerated()), id: \.offset) { _, child in
                    block(child)
                }
            }
            .padding(.leading, 14)
            .overlay(alignment: .leading) {
                Rectangle().fill(Color.accentColor).frame(width: 3)
            }
        } else if let ordered = node as? OrderedList {
            list(ordered, start: Int(ordered.startIndex))
        } else if let unordered = node as? UnorderedList {
            list(unordered, start: nil)
        } else if let table = node as? Markdown.Table {
            tableView(table)
        } else if node is ThematicBreak {
            Divider().padding(.vertical, 8)
        } else if let html = node as? HTMLBlock {
            SwiftUI.Text(html.rawHTML).textSelection(.enabled)
        } else {
            SwiftUI.Text(plainText(node)).textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func list(_ node: Markup, start: Int?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(node.children.enumerated()), id: \.offset) { index, child in
                if let item = child as? Markdown.ListItem {
                    HStack(alignment: .top, spacing: 8) {
                        SwiftUI.Text(listMarker(item, index: index, start: start))
                            .frame(width: 32, alignment: .leading)
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(item.children.enumerated()), id: \.offset) { _, blockNode in
                                block(blockNode)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private func listMarker(_ item: Markdown.ListItem, index: Int, start: Int?) -> String {
        if let checkbox = item.checkbox { return checkbox == .checked ? "☑" : "☐" }
        if let start { return "\(start + index)." }
        return "•"
    }

    @ViewBuilder
    private func tableView(_ table: Markdown.Table) -> some View {
        let rows = [Array(table.head.children)] + table.body.children.map { Array($0.children) }
        ScrollView(.horizontal) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, cells in
                    HStack(spacing: 0) {
                        ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                            inline(cell)
                                .fontWeight(rowIndex == 0 ? .bold : .regular)
                                .frame(width: 150, alignment: .leading)
                                .padding(8)
                                .border(.secondary.opacity(0.4), width: 0.5)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func imageView(_ image: Markdown.Image) -> some View {
        if let source = image.source, let url = URL(string: source), MarkdownSyntax.isSafeImage(url) {
            AsyncImage(url: url) { loaded in
                loaded.resizable().scaledToFit()
            } placeholder: {
                ProgressView().frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)
            .onTapGesture { onImageTap?(url) }
            .accessibilityLabel(plainText(image))
        } else {
            SwiftUI.Text(plainText(image))
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
        if let link = node as? Markdown.Link {
            let label = plainText(link)
            guard let destination = link.destination,
                  let url = URL(string: destination), MarkdownSyntax.isSafeLink(url) else {
                return SwiftUI.Text(label)
            }
            var attributed = AttributedString(label)
            attributed.link = url
            attributed.foregroundColor = .blue
            return SwiftUI.Text(attributed)
        }
        if let image = node as? Markdown.Image {
            return SwiftUI.Text(plainText(image))
        }
        let content = inline(node)
        if node is Strong { return content.bold() }
        if node is Emphasis { return content.italic() }
        if node is Strikethrough { return content.strikethrough() }
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
