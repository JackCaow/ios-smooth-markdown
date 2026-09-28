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
        case .aiChat: "Flutter's six prompts with mock or live Qwen streaming"
        case .chatList: "Interactive local chat"
        case .conversationList: "12 conversations from Flutter example"
        case .performance: "68 KB reader fixture"
        default: nil
        }
    }
    var markdown: String? {
        switch self {
        case .math, .footnotes, .html, .plugins, .mermaid, .chatList, .aiChat: return nil
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
