import SmoothMarkdown
import SwiftUI

/// Shared type roles for the native example. Semantic styles follow Dynamic Type.
enum DemoTypography {
    static let barTitle = Font.headline
    static let body = Font.body
    static let message = Font.subheadline
    static let secondary = Font.subheadline
    static let metadata = Font.caption
    static let timestamp = Font.caption2

    static func chatMarkdown(_ style: inout MarkdownStyleSheet, compactHeading: Bool = false) {
        // Keep chat text compact while preserving the Flutter heading hierarchy.
        style.paragraphFont = message
        style.readerParagraphTextStyle = .subheadline
        let headingStyles: [Font.TextStyle] = compactHeading
            ? [.title3, .headline, .subheadline, .subheadline, .caption, .caption2]
            : [.title2, .title3, .headline, .subheadline, .subheadline, .caption]
        style.headingFonts = headingStyles.map { .system($0, weight: .semibold) }
        style.readerHeadingTextStyles = headingStyles
        style.codeFont = .system(.subheadline, design: .monospaced)
        style.tableHeaderFont = message.weight(.semibold)
        style.tableCellFont = message
        style.listBulletFont = message
    }
}

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
        case .aiChat: "DeepSeek chat with optional streaming and sample prompts"
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
}
