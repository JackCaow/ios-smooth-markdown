import SmoothMarkdown
import SwiftUI
import UIKit

private struct DemoConversationFixture: Decodable {
    let source: String
    let sourceSha256: String
    let conversations: [DemoConversation]
}

private struct DemoConversation: Decodable, Identifiable {
    let id: String
    let name: String
    let avatar: String
    let avatarColorARGB: String
    let unreadCount: Int
    let lastMessage: String
    let messages: [DemoChatMessage]

    var avatarColor: Color {
        let value = UInt64(avatarColorARGB, radix: 16) ?? 0xFF0553B1
        return Color(.sRGB, red: Double((value >> 16) & 0xFF) / 255,
                     green: Double((value >> 8) & 0xFF) / 255,
                     blue: Double(value & 0xFF) / 255, opacity: 1)
    }
}

private struct DemoChatMessage: Decodable {
    let content: String
    let isMe: Bool
    let secondsAgo: Int
}

private enum DemoConversationCatalog {
    static func load(bundle: Bundle = .main) -> Result<[DemoConversation], Error> {
        let url = bundle.url(forResource: "conversations", withExtension: "json", subdirectory: "Examples/Conversations")
            ?? bundle.url(forResource: "conversations", withExtension: "json", subdirectory: "Conversations")
            ?? bundle.url(forResource: "conversations", withExtension: "json")
        guard let url else { return .failure(CatalogError.missingFixture) }
        do {
            let fixture = try JSONDecoder().decode(DemoConversationFixture.self, from: Data(contentsOf: url))
            guard fixture.conversations.count == 12,
                  fixture.conversations.reduce(0, { $0 + $1.messages.count }) == 29,
                  Set(fixture.conversations.map(\.id)).count == 12 else {
                return .failure(CatalogError.invalidFixture)
            }
            return .success(fixture.conversations)
        } catch {
            return .failure(error)
        }
    }

    private enum CatalogError: LocalizedError {
        case missingFixture, invalidFixture
        var errorDescription: String? {
            switch self {
            case .missingFixture: "Flutter conversation fixture is missing"
            case .invalidFixture: "Flutter conversation fixture is incomplete"
            }
        }
    }
}

/// Native version of Flutter's conversation_list_demo.dart, using its exact bundled messages.
struct DemoConversationListView: View {
    @State private var fixture = DemoConversationCatalog.load()
    @State private var isDark = false
    private let referenceTime = Date()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("会话列表").font(.headline)
                Spacer()
                Button {
                    isDark.toggle()
                } label: {
                    Image(systemName: isDark ? "sun.max" : "moon")
                }
                .accessibilityLabel("切换主题")
                .accessibilityIdentifier("conversation-theme")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(isDark ? Color(uiColor: .secondarySystemBackground) : .white)

            switch fixture {
            case let .success(conversations):
                List(conversations) { conversation in
                    NavigationLink {
                        DemoConversationDetailView(conversation: conversation, isDark: isDark,
                                                   referenceTime: referenceTime)
                    } label: {
                        row(conversation)
                    }
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                    .listRowBackground(isDark ? Color(uiColor: .systemBackground) : .white)
                    .accessibilityIdentifier("conversation-\(conversation.id)")
                }
                .listStyle(.plain)
            case let .failure(error):
                ContentUnavailableView("会话数据不可用", systemImage: "bubble.left.and.bubble.right",
                                       description: Text(error.localizedDescription))
            }
        }
        .background(isDark ? Color(uiColor: .systemGroupedBackground) : Color(red: 0.95, green: 0.95, blue: 0.97))
        .preferredColorScheme(isDark ? .dark : .light)
    }

    private func row(_ conversation: DemoConversation) -> some View {
        HStack(alignment: .top, spacing: 12) {
            DemoConversationAvatar(conversation: conversation, size: 52)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(conversation.name)
                        .font(.system(size: 16, weight: conversation.unreadCount > 0 ? .bold : .medium))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(DemoConversationTime.relative(conversation.messages.last?.secondsAgo ?? 0,
                                                       referenceTime: referenceTime))
                        .font(.system(size: 12))
                        .foregroundStyle(conversation.unreadCount > 0 ? Color.blue : Color.secondary)
                }
                HStack {
                    Text(DemoConversationPreview.plain(conversation.lastMessage))
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    if conversation.unreadCount > 0 {
                        Text(conversation.unreadCount > 99 ? "99+" : "\(conversation.unreadCount)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color(red: 0, green: 0.48, blue: 1), in: Capsule())
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct DemoConversationDetailView: View {
    let conversation: DemoConversation
    let isDark: Bool
    let referenceTime: Date
    @State private var copied = false
    @State private var showMessageActions = false
    @State private var messageToCopy = ""
    @State private var selectPressedParagraph: (() -> Void)?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(conversation.messages.indices, id: \.self) { index in
                    bubble(conversation.messages[index], index: index)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(isDark ? Color(red: 0.11, green: 0.11, blue: 0.12) : Color(red: 0.95, green: 0.95, blue: 0.97))
        .navigationTitle(conversation.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    copy(conversation.messages.map(\.content).joined(separator: "\n\n---\n\n"))
                } label: { Image(systemName: "doc.on.doc") }
                .accessibilityLabel("复制全部文本")
                .accessibilityIdentifier("conversation-copy-all")
            }
        }
        .overlay(alignment: .bottom) {
            if copied {
                Text("已复制")
                    .font(.callout)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 12)
                    .accessibilityIdentifier("conversation-copy-feedback")
            }
        }
        .preferredColorScheme(isDark ? .dark : .light)
        .confirmationDialog("消息操作", isPresented: $showMessageActions, titleVisibility: .visible) {
            Button("复制") { copy(messageToCopy) }
            Button("选择文字") {
                let select = selectPressedParagraph
                selectPressedParagraph = nil
                // The native action sheet must leave before UITextView becomes first responder.
                DispatchQueue.main.async { select?() }
            }
        }
    }

    private func bubble(_ message: DemoChatMessage, index: Int) -> some View {
        HStack(alignment: .top, spacing: 8) {
            if message.isMe { Spacer(minLength: 28) }
            else { DemoConversationAvatar(conversation: conversation, size: 32) }
            VStack(alignment: .leading, spacing: 4) {
                SmoothMarkdownView(markdown: message.content,
                                   onTextLongPress: { selectParagraph in
                                       messageToCopy = message.content
                                       selectPressedParagraph = selectParagraph
                                       showMessageActions = true
                                   },
                                   styleSheet: messageStyle(isMe: message.isMe),
                                   selectable: true,
                                   scrollable: false)
                    .accessibilityIdentifier("conversation-message-\(index)")
                HStack(spacing: 8) {
                    Text(DemoConversationTime.clock(message.secondsAgo, referenceTime: referenceTime))
                        .font(.system(size: 11))
                        .foregroundStyle(message.isMe ? Color.white.opacity(0.7) : Color.secondary)
                    Spacer(minLength: 0)
                    Menu {
                        Button("复制", systemImage: "doc.on.doc") { copy(message.content) }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(message.isMe ? Color.white.opacity(0.7) : Color.secondary)
                            .frame(minWidth: 30, minHeight: 24)
                    }
                    .accessibilityLabel("消息操作")
                    .accessibilityIdentifier("conversation-actions-\(index)")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: 300, alignment: .leading)
            .background(message.isMe ? Color(red: 0, green: 0.48, blue: 1) :
                        (isDark ? Color(uiColor: .secondarySystemBackground) : .white),
                        in: RoundedRectangle(cornerRadius: 16))
            if !message.isMe { Spacer(minLength: 28) }
            else { DemoConversationAvatar(conversation: conversation, size: 32) }
        }
    }

    private func messageStyle(isMe: Bool) -> MarkdownStyleSheet {
        var style = isDark ? MarkdownStyleSheet.dark() : .light()
        style.backgroundColor = .clear
        style.contentPadding = 0
        style.blockSpacing = 8
        if isMe {
            style.textColor = .white
            style.headingColor = .white
            style.linkColor = .white
            style.codeTextColor = .white
            style.inlineCodeTextColor = .white
            style.codeBackground = .black.opacity(0.2)
            style.inlineCodeBackground = .black.opacity(0.2)
            style.quoteBarColor = .white.opacity(0.7)
            style.tableBorderColor = .white.opacity(0.6)
        }
        return style
    }

    private func copy(_ text: String) {
        UIPasteboard.general.string = text
        copied = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            copied = false
        }
    }
}

private struct DemoConversationAvatar: View {
    let conversation: DemoConversation
    let size: CGFloat

    var body: some View {
        Text(conversation.avatar)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(conversation.avatarColor.gradient, in: Circle())
            .accessibilityHidden(true)
    }
}

private enum DemoConversationTime {
    static func relative(_ secondsAgo: Int, referenceTime: Date) -> String {
        let minutes = secondsAgo / 60
        if minutes < 1 { return "刚刚" }
        if secondsAgo < 3_600 { return "\(minutes)分钟前" }
        if secondsAgo < 86_400 { return "\(secondsAgo / 3_600)小时前" }
        if secondsAgo < 604_800 { return "\(secondsAgo / 86_400)天前" }
        let date = referenceTime.addingTimeInterval(-Double(secondsAgo))
        return "\(Calendar.current.component(.month, from: date))/\(Calendar.current.component(.day, from: date))"
    }

    static func clock(_ secondsAgo: Int, referenceTime: Date) -> String {
        let date = referenceTime.addingTimeInterval(-Double(secondsAgo))
        return date.formatted(date: .omitted, time: .shortened)
    }
}

private enum DemoConversationPreview {
    static func plain(_ markdown: String) -> String {
        let substitutions: [(String, String)] = [
            (#"```[\s\S]*?```"#, "[代码]"),
            (#"`[^`]+`"#, ""),
            (#"\$\$[\s\S]*?\$\$"#, "[公式]"),
            (#"\$[^$]+\$"#, ""),
            (#"<[^>]+>"#, ""),
            (#"!\[.*?\]\(.*?\)"#, "[图片]"),
            (#"\[([^\]]*)\]\(.*?\)"#, "$1"),
            (#"[#*>|\-]"#, ""),
            (#"\n+"#, " "),
        ]
        return substitutions.reduce(markdown) { value, pair in
            value.replacingOccurrences(of: pair.0, with: pair.1, options: .regularExpression)
        }.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
