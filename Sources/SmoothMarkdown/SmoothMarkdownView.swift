import Markdown
import SwiftUI

/// Renders the currently supported CommonMark and GFM blocks with SwiftUI.
public struct SmoothMarkdownView: View {
    public let markdown: String
    public let onLinkTap: ((URL) -> Void)?
    public let onImageTap: ((URL) -> Void)?
    public let enableHTML: Bool

    public init(
        markdown: String,
        onLinkTap: ((URL) -> Void)? = nil,
        onImageTap: ((URL) -> Void)? = nil,
        enableHTML: Bool = false
    ) {
        self.markdown = markdown
        self.onLinkTap = onLinkTap
        self.onImageTap = onImageTap
        self.enableHTML = enableHTML
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

    private func block(_ node: Markup, alignment: TextAlignment? = nil) -> AnyView {
        AnyView(blockContent(node, alignment: alignment))
    }

    @ViewBuilder
    private func blockContent(_ node: Markup, alignment: TextAlignment? = nil) -> some View {
        if let heading = node as? Heading {
            inline(heading)
                .font(.system(size: CGFloat(32 - (heading.level - 1) * 3), weight: .bold))
                .multilineTextAlignment(alignment ?? .leading)
                .frame(maxWidth: .infinity, alignment: frameAlignment(alignment))
                .textSelection(.enabled)
        } else if let paragraph = node as? Paragraph {
            let meaningful = Array(paragraph.children).filter { child in
                guard let text = child as? Markdown.Text else { return true }
                return !text.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            let sole = meaningful.count == 1 ? meaningful.first : nil
            if let image = sole as? Markdown.Image {
                imageView(image)
            } else if enableHTML, let html = sole as? InlineHTML, let image = SafeHTML.imageTag(html.rawHTML) {
                imageView(image)
            } else {
                inline(paragraph).font(.body).multilineTextAlignment(alignment ?? .leading)
                    .frame(maxWidth: .infinity, alignment: frameAlignment(alignment)).textSelection(.enabled)
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
                    block(child, alignment: alignment)
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
            htmlBlock(html, alignment: alignment)
        } else {
            SwiftUI.Text(plainText(node)).textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func htmlBlock(_ html: HTMLBlock, alignment: TextAlignment?) -> some View {
        if enableHTML, let image = SafeHTML.imageTag(html.rawHTML) {
            imageView(image)
        } else if enableHTML, let alt = SafeHTML.imageAlt(html.rawHTML) {
            SwiftUI.Text(alt).textSelection(.enabled)
        } else if enableHTML, let parsed = SafeHTML.parseBlock(html.rawHTML) {
            switch parsed {
            case .rule:
                Divider().padding(.vertical, 8)
            case let .container(name, content, declared, trailing):
                let childAlignment: TextAlignment? = switch declared {
                case "left": .leading
                case "center": .center
                case "right": .trailing
                default: alignment
                }
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(MarkdownSyntax.parse(content).children.enumerated()), id: \.offset) { _, child in
                        block(child, alignment: childAlignment)
                    }
                }
                .padding(.leading, name == "blockquote" ? 14 : 0)
                .overlay(alignment: .leading) {
                    if name == "blockquote" { Rectangle().fill(Color.accentColor).frame(width: 3) }
                }
                if !trailing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ForEach(Array(MarkdownSyntax.parse(trailing).children.enumerated()), id: \.offset) { _, child in
                        block(child, alignment: alignment)
                    }
                }
            }
        } else {
            SwiftUI.Text(html.rawHTML).textSelection(.enabled)
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
        if let source = image.source {
            imageView(SafeHTML.ImageSpec(source: source, alt: plainText(image), title: image.title, width: nil, height: nil))
        } else {
            SwiftUI.Text(plainText(image))
        }
    }

    private func imageView(_ image: SafeHTML.ImageSpec) -> AnyView {
        let source = image.source
        let url = URL(string: source)
        let isNetwork = url?.scheme.map { ["http", "https"].contains($0.lowercased()) } ?? false
        let isLocal = !source.isEmpty && !source.hasPrefix("//") && !source.contains("..") &&
            !source.contains(":") && !source.contains("\\")
        let label = image.alt.isEmpty ? (image.title ?? "Image") : image.alt
        let width: CGFloat? = image.width.map { CGFloat($0) }
        let height: CGFloat? = image.height.map { CGFloat($0) }
        if isNetwork, let url {
            return AnyView(
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let loaded): loaded.resizable().scaledToFit()
                    case .failure: SwiftUI.Text(label)
                    case .empty: ProgressView()
                    @unknown default: SwiftUI.Text(label)
                    }
                }
                .frame(width: width, height: height)
                .onTapGesture { onImageTap?(url) }
                .accessibilityLabel(label)
            )
        }
        if isLocal {
            return AnyView(SwiftUI.Image(source)
                .resizable().scaledToFit()
                .frame(width: width, height: height)
                .onTapGesture { if let url { onImageTap?(url) } }
                .accessibilityLabel(label))
        }
        return AnyView(SwiftUI.Text(label))
    }

    private struct InlineStyle {
        var bold = false
        var italic = false
        var strike = false
        var link: URL?
    }

    private func inline(_ node: Markup) -> SwiftUI.Text {
        var tags: [SafeHTML.Tag] = []
        return inlineChildren(node, style: InlineStyle(), tags: &tags)
    }

    private func inlineChildren(_ node: Markup, style: InlineStyle, tags: inout [SafeHTML.Tag]) -> SwiftUI.Text {
        var output = SwiftUI.Text("")
        for child in node.children {
            if let html = child as? InlineHTML {
                if enableHTML, let tag = SafeHTML.lexTag(html.rawHTML), tag.end == (html.rawHTML as NSString).length {
                    if tag.isClosing {
                        if let match = tags.lastIndex(where: { $0.name == tag.name }) { tags.removeSubrange(match...) }
                    } else if SafeHTML.voidTags.contains(tag.name) {
                        if tag.name == "br" { output = output + segment("\n", style: style, tags: tags) }
                        if tag.name == "img" { output = output + segment(tag.attributes["alt"] ?? "", style: style, tags: tags) }
                    } else if !tag.isSelfClosing {
                        tags.append(tag)
                    }
                } else {
                    output = output + segment(html.rawHTML, style: style, tags: tags)
                }
                continue
            }
            if let text = child as? Markdown.Text {
                output = output + segment(text.string, style: style, tags: tags)
            } else if let code = child as? InlineCode {
                output = output + segment(code.code, style: style, tags: tags, code: true)
            } else if child is SoftBreak || child is LineBreak {
                output = output + segment("\n", style: style, tags: tags)
            } else if let image = child as? Markdown.Image {
                output = output + segment(plainText(image), style: style, tags: tags)
            } else {
                var nested = style
                if child is Strong { nested.bold = true }
                if child is Emphasis { nested.italic = true }
                if child is Strikethrough { nested.strike = true }
                if let link = child as? Markdown.Link, let destination = link.destination,
                   let url = URL(string: destination), MarkdownSyntax.isSafeLink(url) { nested.link = url }
                output = output + inlineChildren(child, style: nested, tags: &tags)
            }
        }
        return output
    }

    private func segment(_ value: String, style: InlineStyle, tags: [SafeHTML.Tag], code: Bool = false) -> SwiftUI.Text {
        var bold = style.bold
        var italic = style.italic
        var strike = style.strike
        var underline = false
        var monospaced = code
        var baseline: CGFloat = 0
        var foreground: Color?
        var background: Color?
        var fontSize: CGFloat?
        var link = style.link
        if enableHTML {
            for tag in tags {
                switch tag.name {
                case "b", "strong": bold = true
                case "i", "em": italic = true
                case "s", "del", "strike": strike = true
                case "u", "ins": underline = true
                case "mark": background = .yellow.opacity(0.4)
                case "sub": baseline = -4
                case "sup": baseline = 4
                case "code", "kbd": monospaced = true
                case "a":
                    if let href = tag.attributes["href"], SafeHTML.isSafeLink(href) { link = URL(string: href) }
                case "font", "span":
                    let css = tag.name == "span" ? SafeHTML.cssDeclarations(tag.attributes["style"] ?? "") : [:]
                    if let value = tag.name == "font" ? tag.attributes["color"] : css["color"],
                       let color = SafeHTML.color(value) { foreground = colorFromARGB(color) }
                    if let value = css["background-color"], let color = SafeHTML.color(value) { background = colorFromARGB(color) }
                    if let size = tag.name == "font" ? tag.attributes["size"].flatMap(SafeHTML.legacyFontSize)
                        : css["font-size"].flatMap(SafeHTML.fontSize) { fontSize = CGFloat(size) }
                default: break
                }
            }
        }
        var attributed = AttributedString(value)
        if let background { attributed.backgroundColor = background }
        if let link { attributed.link = link }
        var result = SwiftUI.Text(attributed)
        if bold { result = result.bold() }
        if italic { result = result.italic() }
        if strike { result = result.strikethrough() }
        if underline { result = result.underline() }
        if monospaced { result = result.font(.system(.body, design: .monospaced)) }
        if baseline != 0 { result = result.baselineOffset(baseline) }
        if let fontSize { result = result.font(.system(size: fontSize)) }
        if let foreground { result = result.foregroundColor(foreground) }
        else if link != nil { result = result.foregroundColor(.blue) }
        return result
    }

    private func colorFromARGB(_ value: UInt32) -> Color {
        Color(.sRGB, red: Double((value >> 16) & 0xFF) / 255,
              green: Double((value >> 8) & 0xFF) / 255,
              blue: Double(value & 0xFF) / 255, opacity: 1)
    }

    private func frameAlignment(_ alignment: TextAlignment?) -> Alignment {
        switch alignment {
        case .center: .center
        case .trailing: .trailing
        default: .leading
        }
    }

    private func plainText(_ node: Markup) -> String {
        if let text = node as? Markdown.Text { return text.string }
        if let code = node as? InlineCode { return code.code }
        if let code = node as? CodeBlock { return code.code }
        if node is SoftBreak || node is LineBreak { return "\n" }
        return node.children.map(plainText).joined()
    }

}
