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
    @State private var source: AIChatSource?
    @State private var apiKey = ProcessInfo.processInfo.environment["QWEN_API_KEY"] ?? ""
    @State private var deepSeekAPIKey = ProcessInfo.processInfo.environment["DEEPSEEK_API_KEY"] ?? ""
    @State private var selectedProvider: AIChatProvider = .qwen
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
        if selectedProvider == .deepSeek { return selectedDeepSeekModel }
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
                        .accessibilityIdentifier("ai-chat-message-list")
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
    }

    private var titleBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                titleIdentity
                Spacer(minLength: 0)
                actionButtons
            }
            VStack(alignment: .leading, spacing: 8) {
                titleIdentity
                actionButtons.frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(surfaceColor)
    }

    private var titleIdentity: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(LinearGradient(colors: [.indigo, .purple], startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 2) {
                Text("AI Chat Demo").font(DemoTypography.barTitle)
                Text(modeStatus)
                    .font(DemoTypography.metadata)
                    .foregroundStyle(isStreaming ? .blue : liveAPIAvailable ? .green : .orange)
                    .accessibilityIdentifier("ai-chat-status")
            }
            .layoutPriority(1)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var actionButtons: some View {
        HStack(spacing: dynamicTypeSize.isAccessibilitySize ? 4 : 8) {
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
        .labelStyle(.iconOnly)
    }

    private func quickPrompts(_ fixture: AIChatFixture) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(fixture.quickPrompts) { prompt in
                    Button(prompt.label) { send(prompt.prompt) }
                        .buttonStyle(.bordered)
                        .font(DemoTypography.metadata)
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
            if message.isUser { Spacer(minLength: dynamicTypeSize.isAccessibilitySize ? 8 : 36) }
            VStack(alignment: .leading, spacing: 4) {
                if message.isStreaming, let stream = replyStreams.stream(for: message.id) {
                    DemoStreamingMarkdownBubble(stream: stream,
                                                styleSheet: bubbleStyle(isUser: false),
                                                plugins: plugins,
                                                emptyLabel: "AI 正在输入")
                } else {
                    SmoothMarkdownView(markdown: message.content,
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
                        Text("推理内容可随流式响应展示。")
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
                                                model: selectedDeepSeekModel)))
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
            let units = Array(response.utf16)
            var offset = 0
            while offset < units.count {
                guard !Task.isCancelled, replyStreams.runID == currentRunID else { return }
                var end = min(offset + fixture.chunkSizeUTF16, units.count)
                // Preserve a surrogate pair at a UTF-16 chunk boundary so append-only
                // buffering still produces the exact fixture response at completion.
                if end < units.count, (0xD800...0xDBFF).contains(units[end - 1]),
                   (0xDC00...0xDFFF).contains(units[end]) {
                    end += 1
                }
                let fragment = String(decoding: units[offset..<end], as: UTF16.self)
                guard replyStreams.append(fragment, to: messageID, in: currentRunID) else { return }
                offset = end
                do {
                    try await Task.sleep(nanoseconds: fixture.delayMillis * 1_000_000)
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
        if let fixture {
            messages = [.init(content: fixture.welcome, isUser: false)]
        }
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
