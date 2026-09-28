import SmoothMarkdown
import SwiftUI

enum DemoTheme: String, CaseIterable, Identifiable {
    case defaultLight = "Default Light"
    case defaultDark = "Default Dark"
    case github = "GitHub"
    case githubDark = "GitHub Dark"
    case vscode = "VS Code"
    case vscodeDark = "VS Code Dark"

    var id: String { rawValue }
    var isDark: Bool { self == .defaultDark || self == .githubDark || self == .vscodeDark }
    var styleSheet: MarkdownStyleSheet {
        switch self {
        case .defaultLight: .light()
        case .defaultDark: .dark()
        case .github: .github()
        case .githubDark: .github(dark: true)
        case .vscode: .vscode()
        case .vscodeDark: .vscode(dark: true)
        }
    }
}

enum DemoLanguage: String, CaseIterable, Identifiable {
    case zh, en, ja, es, fr, ko
    var id: String { rawValue }
    var nativeName: String {
        switch self {
        case .zh: "中文"
        case .en: "English"
        case .ja: "日本語"
        case .es: "Español"
        case .fr: "Français"
        case .ko: "한국어"
        }
    }
}

enum DemoFeature: String, CaseIterable, Identifiable {
    case math, streaming, footnotes, html, chatList, aiChat, conversationList, plugins, mermaid
    case structured, selection, performance

    var id: String { rawValue }
    var title: String {
        switch self {
        case .math: "Math Formulas"
        case .streaming: "Streaming Markdown"
        case .footnotes: "Footnotes"
        case .html: "HTML Tags"
        case .chatList: "Chat List"
        case .aiChat: "AI Chat"
        case .conversationList: "Conversation List"
        case .plugins: "Plugin System"
        case .mermaid: "Mermaid Diagrams"
        case .structured: "Structured Mermaid"
        case .selection: "Selection"
        case .performance: "Performance"
        }
    }
    var subtitle: String? {
        switch self {
        case .aiChat: "Local plugin fixture; no Qwen API"
        case .chatList: "Static messages"
        case .conversationList: "Interaction demo not ported"
        case .performance: "68 KB reader fixture"
        default: nil
        }
    }
    var markdown: String? {
        switch self {
        case .math, .footnotes, .html, .plugins, .mermaid: return nil
        case .chatList:
            return """
            # Chat List

            **User:** Show a Markdown sample.

            **Assistant:** Here is a native rendered answer with **emphasis**, a list, and code:

            - First item
            - Second item

            ```swift
            print("Hello")
            ```
            """
        case .aiChat:
            return """
            # AI Chat Plugin Fixture

            This page renders local AI syntax. No model request is made.

            <thinking>Compare the available options before answering.</thinking>

            <artifact identifier="demo" type="code" language="swift" title="Hello.swift">print("Hello")</artifact>

            <tool_use><tool_name>search</tool_name><tool_id>demo-1</tool_id><input>{"query":"Markdown"}</input></tool_use>
            """
        case .structured: return structuredMarkdown
        case .selection: return selectionMarkdown
        case .streaming, .conversationList, .performance: return nil
        }
    }
}

enum DemoPage: Hashable {
    case example(String)
    case feature(DemoFeature)
}

/// Deterministic chunks used by the native streaming example.
struct DemoStreamChunks: AsyncSequence {
    typealias Element = String
    let markdown: String

    struct AsyncIterator: AsyncIteratorProtocol {
        let characters: [Character]
        var offset = 0
        mutating func next() async -> String? {
            guard !Task.isCancelled, offset < characters.count else { return nil }
            try? await Task.sleep(nanoseconds: 40_000_000)
            let end = Swift.min(offset + 18, characters.count)
            defer { offset = end }
            return String(characters[offset..<end])
        }
    }
    func makeAsyncIterator() -> AsyncIterator { .init(characters: Array(markdown)) }
}

struct DemoStreamingView: View {
    let styleSheet: MarkdownStyleSheet
    let plugins: ParserPluginRegistry
    @State private var runID = UUID()
    @State private var status = "Ready"
    private let markdown = """
    # AI Assistant Response

    This is **Markdown streaming** with a live heading, list, and code block.

    - First chunked item
    - Second chunked item

    ```swift
    print("Streaming complete")
    ```
    """

    var body: some View {
        VStack {
            HStack {
                Button("Start Stream") { status = "Streaming"; runID = UUID() }
                Text(status).accessibilityIdentifier("stream-demo-status")
                Spacer()
            }
            .padding(.horizontal)
            StreamMarkdownView(chunks: DemoStreamChunks(markdown: markdown), streamID: runID.uuidString,
                               onComplete: { value in status = value == markdown ? "Complete" : "Mismatch" },
                               styleSheet: styleSheet, plugins: plugins)
        }
    }
}
