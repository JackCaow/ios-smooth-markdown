import CryptoKit
import Foundation
import SmoothMarkdown
import SwiftUI

/// Mock conversation data extracted from Flutter's `ai_chat_demo.dart`.
private struct AIChatFixture: Decodable {
    struct QuickPrompt: Decodable, Identifiable {
        let id: String
        let label: String
        let description: String
        let prompt: String
        let response: String
        let responseSha256: String
    }

    let chunkSizeUTF16: Int
    let delayMillis: UInt64
    let welcome: String
    let welcomeSha256: String
    let quickPrompts: [QuickPrompt]
    let genericResponseTemplate: String

    static func load(bundle: Bundle = .main) -> Self? {
        guard let url = bundle.url(forResource: "ai-chat", withExtension: "json", subdirectory: "Examples/AIChat")
            ?? bundle.url(forResource: "ai-chat", withExtension: "json", subdirectory: "AIChat")
            ?? bundle.url(forResource: "ai-chat", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let fixture = try? JSONDecoder().decode(Self.self, from: data),
              fixture.chunkSizeUTF16 == 5,
              fixture.delayMillis == 20,
              fixture.quickPrompts.count == 6,
              Set(fixture.quickPrompts.map(\.id)).count == 6,
              digest(fixture.welcome) == fixture.welcomeSha256,
              fixture.quickPrompts.allSatisfy({ digest($0.response) == $0.responseSha256 }) else {
            return nil
        }
        return fixture
    }

    func response(for text: String) -> String {
        if let prompt = quickPrompts.first(where: { text.contains($0.prompt) || $0.prompt.contains(text) }) {
            return prompt.response
        }
        return genericResponseTemplate.replacingOccurrences(of: "{{prompt}}", with: text)
    }

    private static func digest(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

private struct AIChatMessage: Identifiable {
    let id = UUID()
    var content: String
    let isUser: Bool
    let timestamp = Date()
    var isStreaming = false
}

private struct AIChatSource: Identifiable {
    let id = UUID()
    let markdown: String
}

/// Local counterpart of Flutter's AI Chat demo. The mock path needs no API key.
struct DemoAIChatView: View {
    let parentIsDark: Bool

    @State private var messages: [AIChatMessage] = []
    @State private var input = ""
    @State private var darkOverride: Bool?
    @State private var isStreaming = false
    @State private var streamTask: Task<Void, Never>?
    @State private var runID = UUID()
    @State private var scrollRevision = 0
    @State private var showSettings = false
    @State private var source: AIChatSource?
    @FocusState private var inputFocused: Bool

    private let fixture = AIChatFixture.load()
    private let plugins = ParserPluginRegistry.builtIns()

    private var isDark: Bool { darkOverride ?? parentIsDark }
    private var backgroundColor: Color {
        isDark ? Color(red: 0.11, green: 0.11, blue: 0.118) : Color(red: 0.949, green: 0.949, blue: 0.969)
    }
    private var surfaceColor: Color {
        isDark ? Color(red: 0.173, green: 0.173, blue: 0.18) : .white
    }

    var body: some View {
        Group {
            if let fixture {
                VStack(spacing: 0) {
                    titleBar
                    quickPrompts(fixture)
                    ScrollViewReader { reader in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 8) {
                                ForEach(messages) { message in
                                    bubble(message)
                                        .id(message.id)
                                }
                                Color.clear.frame(height: 1).id("ai-chat-bottom")
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 16)
                        }
                        .defaultScrollAnchor(.bottom)
                        .onChange(of: scrollRevision) { _, _ in
                            reader.scrollTo("ai-chat-bottom", anchor: .bottom)
                        }
                    }
                    composer
                }
                .background(backgroundColor)
                .onAppear {
                    if messages.isEmpty {
                        messages = [.init(content: fixture.welcome, isUser: false)]
                    }
                }
                .onDisappear { stopStreaming() }
                .sheet(isPresented: $showSettings) { settingsSheet }
                .sheet(item: $source) { item in sourceSheet(item.markdown) }
            } else {
                ContentUnavailableView("AI Chat unavailable", systemImage: "doc.questionmark",
                                       description: Text("The Flutter AI Chat fixture is missing or failed its checksum."))
                    .accessibilityIdentifier("ai-chat-fixture-error")
            }
        }
        .preferredColorScheme(isDark ? .dark : .light)
        .accessibilityIdentifier("ai-chat-demo")
    }

    private var titleBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(LinearGradient(colors: [.indigo, .purple], startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 2) {
                Text("AI Chat Demo").font(.headline)
                Text(isStreaming ? "正在输入..." : "模拟模式")
                    .font(.caption)
                    .foregroundStyle(isStreaming ? .blue : .orange)
                    .accessibilityIdentifier("ai-chat-status")
            }
            Spacer()
            Button {
                newChat()
            } label: {
                Image(systemName: "square.and.pencil")
            }
            .accessibilityLabel("新对话")
            .accessibilityIdentifier("ai-chat-new")
            Button {
                darkOverride = !isDark
            } label: {
                Image(systemName: isDark ? "sun.max" : "moon")
            }
            .accessibilityLabel("切换主题")
            .accessibilityIdentifier("ai-chat-theme")
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .accessibilityLabel("API 设置")
            .accessibilityIdentifier("ai-chat-settings")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(surfaceColor)
    }

    private func quickPrompts(_ fixture: AIChatFixture) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(fixture.quickPrompts) { prompt in
                    Button(prompt.label) { send(prompt.prompt) }
                        .buttonStyle(.bordered)
                        .font(.caption)
                        .disabled(isStreaming)
                        .accessibilityHint(prompt.description)
                        .accessibilityIdentifier("ai-chat-prompt-\(prompt.id)")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(surfaceColor)
    }

    private func bubble(_ message: AIChatMessage) -> some View {
        HStack(alignment: .top, spacing: 8) {
            if !message.isUser { avatar("sparkles", color: .indigo) }
            if message.isUser { Spacer(minLength: 36) }
            VStack(alignment: .leading, spacing: 4) {
                if message.content.isEmpty && message.isStreaming {
                    ProgressView().accessibilityLabel("AI 正在输入")
                } else {
                    SmoothMarkdownView(markdown: message.content,
                                       styleSheet: bubbleStyle(isUser: message.isUser),
                                       plugins: plugins,
                                       scrollable: false)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 10) {
                    Text(message.timestamp, style: .time)
                        .font(.system(size: 11))
                        .foregroundStyle(message.isUser ? Color.white.opacity(0.7) : .secondary)
                    if !message.isUser && !message.content.isEmpty {
                        Button {
                            source = .init(markdown: message.content)
                        } label: {
                            Image(systemName: "chevron.left.forwardslash.chevron.right")
                                .font(.system(size: 11))
                        }
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("查看 Markdown 源码")
                        .accessibilityIdentifier("ai-chat-source")
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(message.isUser ? Color(red: 0, green: 0.478, blue: 1) : surfaceColor,
                        in: RoundedRectangle(cornerRadius: 20))
            .frame(maxWidth: 310, alignment: message.isUser ? .trailing : .leading)
            .accessibilityIdentifier(message.isUser ? "ai-chat-user-bubble" : "ai-chat-assistant-bubble")
            if !message.isUser { Spacer(minLength: 36) }
            if message.isUser { avatar("person.fill", color: .gray) }
        }
        .frame(maxWidth: .infinity)
    }

    private func avatar(_ symbol: String, color: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 15))
            .foregroundStyle(.white)
            .frame(width: 32, height: 32)
            .background(color, in: RoundedRectangle(cornerRadius: 10))
    }

    private func bubbleStyle(isUser: Bool) -> MarkdownStyleSheet {
        var style = isDark ? MarkdownStyleSheet.dark() : .light()
        style.backgroundColor = nil
        style.contentPadding = 0
        style.blockSpacing = 8
        if isUser {
            style.textColor = .white
            style.headingColor = .white
            style.linkColor = .white
            style.paragraphFont = .system(size: 15)
        }
        return style
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 12) {
            TextField("输入消息...", text: $input, axis: .vertical)
                .lineLimit(1...5)
                .submitLabel(.send)
                .onSubmit { send(input) }
                .focused($inputFocused)
                .disabled(isStreaming)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(backgroundColor, in: Capsule())
                .accessibilityIdentifier("ai-chat-input")
            Button { send(input) } label: {
                Image(systemName: "arrow.up")
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(canSend ? Color.indigo : .gray, in: Circle())
            }
            .disabled(!canSend)
            .accessibilityLabel("发送消息")
            .accessibilityIdentifier("ai-chat-send")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(surfaceColor)
    }

    private var canSend: Bool {
        !isStreaming && !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var settingsSheet: some View {
        NavigationStack {
            Form {
                Section("响应模式") {
                    Label("模拟模式", systemImage: "checkmark.circle.fill")
                    Text("本地示例可测试 Thinking、Artifact 和 Tool Call 解析。")
                        .foregroundStyle(.secondary)
                }
                Section("Qwen API") {
                    Text("真实 Qwen 请求尚未接入 iOS Demo。当前对话仅使用 Flutter 示例中的模拟响应，不会发送网络请求。")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("API 设置")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { showSettings = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func sourceSheet(_ markdown: String) -> some View {
        NavigationStack {
            ScrollView {
                Text(markdown)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding()
                    .accessibilityIdentifier("ai-chat-source-content")
            }
            .navigationTitle("Markdown 源码")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { source = nil }
                }
            }
        }
    }

    private func send(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !isStreaming, let fixture else { return }
        messages.append(.init(content: text, isUser: true))
        messages.append(.init(content: "", isUser: false, isStreaming: true))
        let messageID = messages[messages.count - 1].id
        let response = fixture.response(for: text)
        let units = Array(response.utf16)
        input = ""
        inputFocused = false
        isStreaming = true
        scrollRevision += 1
        runID = UUID()
        let currentRunID = runID
        streamTask = Task { @MainActor in
            var end = 0
            while end < units.count {
                guard !Task.isCancelled, runID == currentRunID,
                      let index = messages.firstIndex(where: { $0.id == messageID }) else { return }
                end = min(end + fixture.chunkSizeUTF16, units.count)
                // Dart String.substring indexes UTF-16 units. Decode each full prefix so a
                // surrogate pair split by a chunk boundary is corrected on the next update.
                messages[index].content = String(decoding: units.prefix(end), as: UTF16.self)
                scrollRevision += 1
                do {
                    try await Task.sleep(nanoseconds: fixture.delayMillis * 1_000_000)
                } catch { return }
            }
            guard !Task.isCancelled, runID == currentRunID,
                  let index = messages.firstIndex(where: { $0.id == messageID }) else { return }
            messages[index].content = response
            messages[index].isStreaming = false
            isStreaming = false
            streamTask = nil
        }
    }

    private func newChat() {
        stopStreaming()
        input = ""
        inputFocused = false
        source = nil
        if let fixture {
            messages = [.init(content: fixture.welcome, isUser: false)]
        }
        scrollRevision += 1
    }

    private func stopStreaming() {
        runID = UUID()
        streamTask?.cancel()
        streamTask = nil
        for index in messages.indices where messages[index].isStreaming {
            messages[index].isStreaming = false
        }
        isStreaming = false
    }
}
