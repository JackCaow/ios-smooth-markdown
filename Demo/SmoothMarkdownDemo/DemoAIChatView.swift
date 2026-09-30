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

/// Keeps mock chunks tied to elapsed time when Markdown layout delays the main actor.
enum MockAIChatSchedule {
    static func chunks(_ response: String, sizeUTF16: Int) -> [String] {
        let units = Array(response.utf16)
        var chunks: [String] = []
        var offset = 0
        let chunkSize = max(1, sizeUTF16)
        while offset < units.count {
            var end = min(offset + chunkSize, units.count)
            // Never split an emoji's UTF-16 surrogate pair across updates.
            if end < units.count, (0xD800...0xDBFF).contains(units[end - 1]),
               (0xDC00...0xDFFF).contains(units[end]) {
                end += 1
            }
            chunks.append(String(decoding: units[offset..<end], as: UTF16.self))
            offset = end
        }
        return chunks
    }

    static func dueChunkCount(elapsedMillis: UInt64, delayMillis: UInt64, totalChunks: Int) -> Int {
        guard totalChunks > 0 else { return 0 }
        let elapsedIntervals = elapsedMillis / max(1, delayMillis)
        return Int(min(UInt64(totalChunks - 1), elapsedIntervals)) + 1
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

private enum AIChatProvider: String, CaseIterable, Identifiable {
    case qwen = "Qwen"
    case deepSeek = "DeepSeek"

    var id: String { rawValue }
}

private enum LiveChatConfiguration {
    case qwen(QwenChatRequest)
    case deepSeek(DeepSeekChatRequest)
}

/// Counterpart of Flutter's AI Chat demo, with mock and optional live streams.
struct DemoAIChatView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let parentIsDark: Bool

    @State private var messages: [AIChatMessage] = []
    @State private var input = ""
    @State private var darkOverride: Bool?
    @State private var isStreaming = false
    @State private var streamTask: Task<Void, Never>?
    @State private var replyStreams = DemoChatReplyStreams()
    @State private var scrollRevision = 0
    @State private var showSettings = false
    @State private var showHelp = false
    @State private var source: AIChatSource?
    @State private var apiKey = ProcessInfo.processInfo.environment["QWEN_API_KEY"] ?? ""
    @State private var deepSeekAPIKey = ProcessInfo.processInfo.environment["DEEPSEEK_API_KEY"] ?? ""
    @State private var selectedProvider: AIChatProvider = .deepSeek
    @State private var selectedModel = "qwen3-235b-a22b"
    @State private var selectedDeepSeekModel = "deepseek-flash"
    @State private var enableThinking = true
    @State private var useRealAPI = true
    @FocusState private var inputFocused: Bool

    private let fixture = AIChatFixture.load()
    private let plugins = ParserPluginRegistry.builtIns()
    private let models: [(id: String, name: String)] = [
        ("qwen3-235b-a22b", "Qwen3 Max (思考模式)"),
        ("qwen-max", "Qwen Max"),
        ("qwen-plus", "Qwen Plus"),
        ("qwen-turbo", "Qwen Turbo"),
    ]
    private let deepSeekModels: [(id: String, name: String)] = [
        ("deepseek-flash", "DeepSeek Flash"),
        ("deepseek-v4-pro", "DeepSeek V4 Pro"),
    ]

    private var isDark: Bool { darkOverride ?? parentIsDark }
    private var liveAPIAvailable: Bool {
        let key = selectedProvider == .qwen ? apiKey : deepSeekAPIKey
        return useRealAPI && !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    private var modeStatus: String {
        if isStreaming { return "正在输入..." }
        guard liveAPIAvailable else { return "模拟模式" }
        if selectedProvider == .deepSeek {
            return enableThinking ? "\(selectedDeepSeekModel) (思考)" : selectedDeepSeekModel
        }
        return enableThinking && selectedModel.hasPrefix("qwen3") ? "\(selectedModel) (思考)" : selectedModel
    }
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
                        .accessibilityIdentifier("ai-chat-message-list")
                        .defaultScrollAnchor(.bottom)
                        .onChange(of: scrollRevision) { _, _ in
                            reader.scrollTo("ai-chat-bottom", anchor: .bottom)
                        }
                        .overlay {
                            if messages.isEmpty {
                                Text("发送消息，或点击右上角快捷提示词")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 24)
                                    .allowsHitTesting(false)
                                    .accessibilityIdentifier("ai-chat-empty-hint")
                            }
                        }
                    }
                    composer
                }
                .background(backgroundColor)
                .onDisappear { stopStreaming() }
                .sheet(isPresented: $showSettings) { settingsSheet }
                .sheet(isPresented: $showHelp) { helpSheet(fixture.welcome) }
                .sheet(item: $source) { item in sourceSheet(item.markdown) }
            } else {
                ContentUnavailableView("AI Chat unavailable", systemImage: "doc.questionmark",
                                       description: Text("The Flutter AI Chat fixture is missing or failed its checksum."))
                    .accessibilityIdentifier("ai-chat-fixture-error")
            }
        }
        .preferredColorScheme(isDark ? .dark : .light)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text(selectedProvider.rawValue)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                Text(modeStatus)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .accessibilityIdentifier("ai-chat-status")
                }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Section("快捷提示词") {
                        ForEach(fixture?.quickPrompts ?? []) { prompt in
                            Button(prompt.label) { send(prompt.prompt) }
                                .disabled(isStreaming)
                                .accessibilityHint(prompt.description)
                                .accessibilityIdentifier("ai-chat-prompt-\(prompt.id)")
                        }
                    }
                    Button("新对话", systemImage: "square.and.pencil") { newChat() }
                        .accessibilityIdentifier("ai-chat-new")
                    Button("切换主题", systemImage: isDark ? "sun.max" : "moon") {
                        darkOverride = !isDark
                    }
                    .accessibilityIdentifier("ai-chat-theme")
                    Button("使用说明", systemImage: "questionmark.circle") { showHelp = true }
                        .accessibilityIdentifier("ai-chat-help")
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("聊天操作")
                .accessibilityIdentifier("ai-chat-actions")
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("API 设置")
                .accessibilityIdentifier("ai-chat-settings")
            }
        }
    }

    private func bubble(_ message: AIChatMessage) -> some View {
        HStack(alignment: .top, spacing: 8) {
            if !message.isUser { avatar("sparkles", color: .indigo) }
            if message.isUser { Spacer(minLength: dynamicTypeSize.isAccessibilitySize ? 8 : 36) }
            VStack(alignment: .leading, spacing: 4) {
                if message.isStreaming, let stream = replyStreams.stream(for: message.id) {
                    DemoStreamingMarkdownBubble(stream: stream,
                                                styleSheet: bubbleStyle(isUser: false),
                                                plugins: plugins,
                                                emptyLabel: "AI 正在输入",
                                                useEnhancedComponents: true)
                } else {
                    SmoothMarkdownView(markdown: message.content,
                                       useEnhancedComponents: !message.isUser,
                                       styleSheet: bubbleStyle(isUser: message.isUser),
                                       plugins: plugins,
                                       scrollable: false)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 10) {
                    Text(message.timestamp, style: .time)
                        .font(DemoTypography.timestamp)
                        .foregroundStyle(message.isUser ? Color.white.opacity(0.7) : .secondary)
                    if !message.isUser && !message.content.isEmpty {
                        Button {
                            source = .init(markdown: message.content)
                        } label: {
                            Image(systemName: "chevron.left.forwardslash.chevron.right")
                                .font(DemoTypography.timestamp)
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
            .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? nil : 310,
                   alignment: message.isUser ? .trailing : .leading)
            if !message.isUser { Spacer(minLength: dynamicTypeSize.isAccessibilitySize ? 8 : 36) }
            if message.isUser { avatar("person.fill", color: .gray) }
        }
        .frame(maxWidth: .infinity)
    }

    private func avatar(_ symbol: String, color: Color) -> some View {
        Image(systemName: symbol)
            .font(DemoTypography.message)
            .foregroundStyle(.white)
            .frame(width: 32, height: 32)
            .background(color, in: RoundedRectangle(cornerRadius: 10))
    }

    private func bubbleStyle(isUser: Bool) -> MarkdownStyleSheet {
        var style = isDark ? MarkdownStyleSheet.dark() : .light()
        style.backgroundColor = nil
        style.contentPadding = 0
        style.blockSpacing = 8
        DemoTypography.chatMarkdown(&style)
        if isUser {
            style.textColor = .white
            style.headingColor = .white
            style.linkColor = .white
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
                Section(selectedProvider == .qwen ? "Qwen API" : "DeepSeek API") {
                    Picker("服务商", selection: $selectedProvider) {
                        ForEach(AIChatProvider.allCases) { provider in
                            Text(provider.rawValue).tag(provider)
                        }
                    }
                    .accessibilityIdentifier("ai-chat-provider")
                    if selectedProvider == .qwen {
                        SecureField("Qwen API Key", text: $apiKey)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("ai-chat-api-key")
                        Picker("选择模型", selection: $selectedModel) {
                            ForEach(models.indices, id: \.self) { index in
                                Text(models[index].name).tag(models[index].id)
                            }
                        }
                        .accessibilityIdentifier("ai-chat-model")
                        Toggle("启用思考模式", isOn: $enableThinking)
                            .disabled(!selectedModel.hasPrefix("qwen3"))
                            .accessibilityIdentifier("ai-chat-thinking")
                        Text(selectedModel.hasPrefix("qwen3") ? "显示 AI 的推理过程" : "仅 Qwen3 系列模型支持")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        SecureField("DeepSeek API Key", text: $deepSeekAPIKey)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("ai-chat-deepseek-api-key")
                        Picker("选择模型", selection: $selectedDeepSeekModel) {
                            ForEach(deepSeekModels.indices, id: \.self) { index in
                                Text(deepSeekModels[index].name).tag(deepSeekModels[index].id)
                            }
                        }
                        .accessibilityIdentifier("ai-chat-deepseek-model")
                        Toggle("启用思考模式", isOn: $enableThinking)
                            .accessibilityIdentifier("ai-chat-deepseek-thinking")
                        Text("开启时显示 AI 的推理过程。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Toggle("使用真实 API", isOn: $useRealAPI)
                        .accessibilityIdentifier("ai-chat-real-api")
                    Text("关闭或未填写 API Key 时使用模拟响应。密钥只保留在本次页面会话中。")
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier("ai-chat-settings-form")
            .navigationTitle("API 设置")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { showSettings = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
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

    private func helpSheet(_ markdown: String) -> some View {
        NavigationStack {
            ScrollView {
                SmoothMarkdownView(markdown: markdown, styleSheet: bubbleStyle(isUser: false),
                                   plugins: plugins, scrollable: false)
                    .padding(16)
                    .accessibilityIdentifier("ai-chat-help-content")
            }
            .navigationTitle("使用说明")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { showHelp = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func send(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !isStreaming, let fixture else { return }
        messages.append(.init(content: text, isUser: true))
        messages.append(.init(content: "", isUser: false, isStreaming: true))
        let messageID = messages[messages.count - 1].id
        let currentRunID = replyStreams.start(messageID: messageID)
        let liveConfiguration: LiveChatConfiguration? = liveAPIAvailable
            ? (selectedProvider == .qwen
                ? .qwen(QwenChatRequest(apiKey: apiKey, model: selectedModel,
                                        enableThinking: enableThinking))
                : .deepSeek(DeepSeekChatRequest(apiKey: deepSeekAPIKey,
                                                model: selectedDeepSeekModel,
                                                enableThinking: enableThinking)))
            : nil
        input = ""
        inputFocused = false
        isStreaming = true
        scrollRevision += 1
        streamTask = Task { @MainActor in
            if let liveConfiguration {
                do {
                    switch liveConfiguration {
                    case let .qwen(configuration):
                        try await QwenChatClient().stream(prompt: text, configuration: configuration) { fragment in
                            _ = replyStreams.append(fragment, to: messageID, in: currentRunID)
                        }
                    case let .deepSeek(configuration):
                        try await DeepSeekChatClient().stream(prompt: text, configuration: configuration) { fragment in
                            _ = replyStreams.append(fragment, to: messageID, in: currentRunID)
                        }
                    }
                    guard !Task.isCancelled,
                          let fullText = replyStreams.finish(messageID: messageID, in: currentRunID),
                          let index = messages.firstIndex(where: { $0.id == messageID }) else { return }
                    messages[index].content = fullText
                    messages[index].isStreaming = false
                    isStreaming = false
                    streamTask = nil
                    scrollRevision += 1
                } catch {
                    guard !Task.isCancelled, replyStreams.runID == currentRunID,
                          let index = messages.firstIndex(where: { $0.id == messageID }) else { return }
                    _ = replyStreams.finish(messageID: messageID, in: currentRunID)
                    messages[index].content = "⚠️ **错误**: \(error.localizedDescription)\n\n请检查 API Key 配置或网络连接。"
                    messages[index].isStreaming = false
                    isStreaming = false
                    streamTask = nil
                    scrollRevision += 1
                }
                return
            }
            let response = fixture.response(for: text)
            let chunks = MockAIChatSchedule.chunks(response, sizeUTF16: fixture.chunkSizeUTF16)
            let startedAt = ProcessInfo.processInfo.systemUptime
            var nextChunk = 0
            while nextChunk < chunks.count {
                guard !Task.isCancelled, replyStreams.runID == currentRunID else { return }
                let elapsed = UInt64(max(0, (ProcessInfo.processInfo.systemUptime - startedAt) * 1_000))
                let due = MockAIChatSchedule.dueChunkCount(elapsedMillis: elapsed,
                                                            delayMillis: fixture.delayMillis,
                                                            totalChunks: chunks.count)
                if due > nextChunk {
                    guard replyStreams.append(chunks[nextChunk..<due].joined(),
                                              to: messageID, in: currentRunID) else { return }
                    nextChunk = due
                }
                let nextDeadline = startedAt + Double(nextChunk) * Double(fixture.delayMillis) / 1_000
                let remaining = nextDeadline - ProcessInfo.processInfo.systemUptime
                do {
                    if remaining > 0 {
                        try await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
                    } else {
                        await Task.yield()
                    }
                } catch { return }
            }
            guard !Task.isCancelled,
                  let fullText = replyStreams.finish(messageID: messageID, in: currentRunID),
                  let index = messages.firstIndex(where: { $0.id == messageID }) else { return }
            messages[index].content = fullText
            messages[index].isStreaming = false
            isStreaming = false
            streamTask = nil
            scrollRevision += 1
        }
    }

    private func newChat() {
        stopStreaming()
        input = ""
        inputFocused = false
        source = nil
        messages = []
        scrollRevision += 1
    }

    private func stopStreaming() {
        streamTask?.cancel()
        streamTask = nil
        let partial = replyStreams.cancelAll()
        for index in messages.indices where messages[index].isStreaming {
            messages[index].content = partial[messages[index].id] ?? messages[index].content
            messages[index].isStreaming = false
        }
        isStreaming = false
    }
}
