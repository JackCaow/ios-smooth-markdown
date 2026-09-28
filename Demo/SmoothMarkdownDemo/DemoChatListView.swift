import CryptoKit
import Foundation
import SmoothMarkdown
import SwiftUI

private struct ChatListFixture {
    let welcome: String
    let responses: [String]

    private struct Manifest: Decodable {
        let sha256: [String: String]
    }

    static func load(bundle: Bundle = .main) -> ChatListFixture? {
        let names = ["welcome", "code", "markdown", "performance", "table"]
        guard let manifestURL = resourceURL("manifest", extension: "json", bundle: bundle),
              let manifestData = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: manifestData) else {
            return nil
        }
        var pages: [String: String] = [:]
        for name in names {
            guard let url = resourceURL(name, extension: "md", bundle: bundle),
                  let data = try? Data(contentsOf: url),
                  let expectedHash = manifest.sha256[name],
                  SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == expectedHash,
                  let text = String(data: data, encoding: .utf8) else {
                return nil
            }
            pages[name] = text
        }
        guard let welcome = pages["welcome"],
              let code = pages["code"], let markdown = pages["markdown"],
              let performance = pages["performance"], let table = pages["table"] else {
            return nil
        }
        return .init(welcome: welcome, responses: [code, markdown, performance, table])
    }

    private static func resourceURL(_ name: String, extension ext: String, bundle: Bundle) -> URL? {
        bundle.url(forResource: name, withExtension: ext, subdirectory: "Examples/ChatList")
            ?? bundle.url(forResource: name, withExtension: ext, subdirectory: "ChatList")
    }
}

private struct DemoChatMessage: Identifiable {
    let id = UUID()
    var content: String
    let isUser: Bool
    let timestamp = Date()
    var isStreaming = false
}

/// Mirrors Flutter example/lib/chat_list_demo.dart with local responses and simulated typing.
struct DemoChatListView: View {
    let parentIsDark: Bool

    @State private var messages: [DemoChatMessage] = []
    @State private var input = ""
    @State private var darkOverride: Bool?
    @State private var isWaiting = false
    @State private var isStreaming = false
    @State private var replyTask: Task<Void, Never>?
    @State private var scrollRevision = 0
    @State private var showCacheExplanation = false
    @FocusState private var inputFocused: Bool

    private let fixture = ChatListFixture.load()
    private var isDark: Bool { darkOverride ?? parentIsDark }
    private var bubbleColor: Color { isDark ? Color(red: 0.173, green: 0.173, blue: 0.18) : .white }
    private var backgroundColor: Color { isDark ? Color(red: 0.11, green: 0.11, blue: 0.118) : Color(red: 0.949, green: 0.949, blue: 0.969) }

    var body: some View {
        Group {
            if let fixture {
                VStack(spacing: 0) {
                    titleBar
                    ScrollViewReader { reader in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 8) {
                                ForEach(messages) { message in
                                    bubble(message)
                                        .id(message.id)
                                }
                                Color.clear.frame(height: 1).id("chat-bottom")
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 16)
                        }
                        .defaultScrollAnchor(.bottom)
                        .onChange(of: scrollRevision) { _, _ in
                            reader.scrollTo("chat-bottom", anchor: .bottom)
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
                .onDisappear {
                    replyTask?.cancel()
                    replyTask = nil
                    isWaiting = false
                    isStreaming = false
                }
                .alert("Cache Statistics Unavailable", isPresented: $showCacheExplanation) {
                    Button("Close", role: .cancel) {}
                } message: {
                    Text("The native iOS library does not expose cache statistics or a clear-cache API. The numbers shown in the Flutter example do not measure this app.")
                }
            } else {
                ContentUnavailableView("Chat demo unavailable", systemImage: "doc.questionmark",
                                       description: Text("The Flutter chat fixture is missing or failed its checksum."))
                    .accessibilityIdentifier("chat-fixture-error")
            }
        }
        .preferredColorScheme(isDark ? .dark : .light)
        .accessibilityIdentifier("chat-list-demo")
    }

    private var titleBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "brain.head.profile")
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(.blue, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("AI Assistant").font(.headline)
                Text(isStreaming ? "Typing..." : "Online")
                    .font(.caption)
                    .foregroundStyle(isStreaming ? .blue : .green)
                    .accessibilityIdentifier("chat-assistant-status")
            }
            Spacer()
            Button {
                darkOverride = !isDark
            } label: {
                Image(systemName: isDark ? "sun.max" : "moon")
            }
            .accessibilityLabel("Toggle theme")
            .accessibilityIdentifier("chat-toggle-theme")
            Button {
                showCacheExplanation = true
            } label: {
                Image(systemName: "chart.bar")
            }
            .accessibilityLabel("Cache Statistics")
            .accessibilityIdentifier("chat-cache-statistics")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(isDark ? Color(red: 0.173, green: 0.173, blue: 0.18) : .white)
    }

    private func bubble(_ message: DemoChatMessage) -> some View {
        HStack(alignment: .top, spacing: 8) {
            if !message.isUser { avatar("brain.head.profile", color: .blue) }
            if message.isUser { Spacer(minLength: 36) }
            VStack(alignment: .leading, spacing: 4) {
                if message.content.isEmpty && message.isStreaming {
                    ProgressView().accessibilityLabel("Assistant is typing")
                } else {
                    SmoothMarkdownView(markdown: message.content,
                                       styleSheet: bubbleStyle(isUser: message.isUser),
                                       scrollable: false)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(message.timestamp, style: .time)
                    .font(.system(size: 11))
                    .foregroundStyle(message.isUser ? Color.white.opacity(0.7) : .secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(message.isUser ? Color(red: 0, green: 0.478, blue: 1) : bubbleColor,
                        in: RoundedRectangle(cornerRadius: 20))
            .frame(maxWidth: 310,
                   alignment: message.isUser ? .trailing : .leading)
            .accessibilityIdentifier(message.isUser ? "chat-user-bubble" : "chat-assistant-bubble")
            if !message.isUser { Spacer(minLength: 36) }
            if message.isUser { avatar("person.fill", color: .gray) }
        }
        .frame(maxWidth: .infinity)
    }

    private func avatar(_ symbol: String, color: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 16))
            .foregroundStyle(.white)
            .frame(width: 32, height: 32)
            .background(color, in: Circle())
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
            TextField("Message AI Assistant...", text: $input, axis: .vertical)
                .lineLimit(1...5)
                .submitLabel(.send)
                .onSubmit(send)
                .focused($inputFocused)
                .disabled(isWaiting || isStreaming)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(backgroundColor, in: Capsule())
                .accessibilityIdentifier("chat-message-input")
            Button(action: send) {
                Image(systemName: isStreaming ? "stop.fill" : "arrow.up")
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(isWaiting || isStreaming || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .gray : .blue,
                                in: Circle())
            }
            .disabled(isWaiting || isStreaming || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("Send message")
            .accessibilityIdentifier("chat-send")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(isDark ? Color(red: 0.173, green: 0.173, blue: 0.18) : .white)
    }

    private func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isWaiting, !isStreaming, let fixture else { return }
        messages.append(.init(content: text, isUser: true))
        input = ""
        inputFocused = false
        isWaiting = true
        scrollRevision += 1
        replyTask = Task { @MainActor in
            do { try await Task.sleep(nanoseconds: 500_000_000) } catch { return }
            guard !Task.isCancelled else { return }
            isWaiting = false
            isStreaming = true
            let answer = fixture.responses.randomElement() ?? fixture.responses[0]
            messages.append(.init(content: "", isUser: false, isStreaming: true))
            let index = messages.count - 1
            // The generated message has its own stable identity; earlier bubbles remain unchanged.
            let messageID = messages[index].id
            scrollRevision += 1
            let characters = Array(answer)
            var offset = 0
            while offset < characters.count {
                guard !Task.isCancelled else { return }
                let end = min(offset + Int.random(in: 3...5), characters.count)
                guard let currentIndex = messages.firstIndex(where: { $0.id == messageID }) else { return }
                messages[currentIndex].content += String(characters[offset..<end])
                offset = end
                scrollRevision += 1
                do {
                    try await Task.sleep(nanoseconds: UInt64(Int.random(in: 20...49)) * 1_000_000)
                } catch { return }
            }
            if let currentIndex = messages.firstIndex(where: { $0.id == messageID }) {
                messages[currentIndex].isStreaming = false
            }
            isStreaming = false
            replyTask = nil
        }
    }
}
