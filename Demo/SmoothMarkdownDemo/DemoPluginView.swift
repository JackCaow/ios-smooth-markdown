import SmoothMarkdown
import SwiftUI

/// Interactive companion to Flutter's Plugin System Demo. The Markdown source
/// comes from the checked Flutter fixture rather than a second hand copy.
struct DemoPluginView: View {
    let markdown: String
    let styleSheet: MarkdownStyleSheet

    @State private var sourceExpanded = false
    @State private var feedback: String?
    @State private var feedbackTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("插件系统演示")
                        .font(.title2.bold())
                    Text("展示 Flutter Smooth Markdown 的插件系统功能")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 0) {
                    SmoothMarkdownView(markdown: markdown,
                                       styleSheet: styleSheet,
                                       plugins: pluginRegistry,
                                       scrollable: false)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("plugin-demo-reader")

                    Divider()

                    DisclosureGroup("查看 Markdown 源码", isExpanded: $sourceExpanded) {
                        Text(markdown)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(.top, 12)
                            .accessibilityIdentifier("plugin-demo-source")
                    }
                    .font(.subheadline)
                    .padding(16)
                    .accessibilityIdentifier("plugin-demo-source-toggle")
                }
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color(.separator), lineWidth: 1)
                }
            }
            .padding(16)
        }
        .overlay(alignment: .bottom) {
            if let feedback {
                Text(feedback)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(.black.opacity(0.85), in: Capsule())
                    .padding(.bottom, 18)
                    .accessibilityIdentifier("plugin-demo-feedback")
            }
        }
        .onDisappear { feedbackTask?.cancel() }
    }

    private var pluginRegistry: ParserPluginRegistry {
        let registry = ParserPluginRegistry()
        try! registry.register(DemoMentionPlugin { showFeedback("点击了用户: @\($0)") })
        try! registry.register(DemoHashtagPlugin { showFeedback("点击了标签: #\($0)") })
        try! registry.register(EmojiPlugin())
        try! registry.register(AdmonitionPlugin())
        return registry
    }

    private func showFeedback(_ message: String) {
        feedbackTask?.cancel()
        feedback = message
        feedbackTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            if !Task.isCancelled { feedback = nil }
        }
    }
}

/// Demo-specific renderers retain the library's parsing rules while adding
/// the callbacks that Flutter supplies through its custom BuilderRegistry.
private struct DemoMentionPlugin: InlineParserPlugin {
    let id = "mention"
    let name = "Mention Demo Plugin"
    let priority = 10
    let triggerCharacter: Character = "@"
    let onTap: (String) -> Void
    private let parser = MentionPlugin()

    func canParse(_ text: String, at index: String.Index) -> Bool {
        parser.canParse(text, at: index)
    }

    func parse(_ text: String, at index: String.Index) -> InlinePluginMatch? {
        parser.parse(text, at: index)
    }

    func render(_ match: InlinePluginMatch) -> AnyView {
        let username = match.attributes["username"] ?? String(match.text.dropFirst())
        return AnyView(Button {
            onTap(username)
        } label: {
            Text(match.text)
                .font(.body.weight(.medium))
                .foregroundStyle(.blue)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("plugin-mention-\(username)"))
    }
}

private struct DemoHashtagPlugin: InlineParserPlugin {
    let id = "hashtag"
    let name = "Hashtag Demo Plugin"
    let priority = 10
    let triggerCharacter: Character = "#"
    let onTap: (String) -> Void
    private let parser = HashtagPlugin()

    func canParse(_ text: String, at index: String.Index) -> Bool {
        parser.canParse(text, at: index)
    }

    func parse(_ text: String, at index: String.Index) -> InlinePluginMatch? {
        parser.parse(text, at: index)
    }

    func render(_ match: InlinePluginMatch) -> AnyView {
        let tag = match.attributes["tag"] ?? String(match.text.dropFirst())
        return AnyView(Button {
            onTap(tag)
        } label: {
            Text(match.text)
                .font(.body.weight(.medium))
                .foregroundStyle(.purple)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.purple.opacity(0.1), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("plugin-hashtag-\(tag)"))
    }
}
