import SmoothMarkdown
import SwiftUI

private struct EditorSession: Identifiable {
    let id = UUID()
    let controller: MarkdownEditorController
}

/// Native companion to the Flutter example's sample drawer and feature pages.
struct DemoHomeView: View {
    @State private var catalog = DemoExampleCatalog.load()
    private let pageCatalog = DemoPageCatalog.load()
    @State private var selected: DemoPage = .example("basic-formatting")
    @State private var theme: DemoTheme = .defaultLight
    @State private var language: DemoLanguage = .zh
    @State private var showNavigation = false
    @State private var showSource = false
    @State private var editorSession: EditorSession?
    @State private var linkMessage: String?
    private let plugins = ParserPluginRegistry.builtIns()

    private var currentExample: DemoExample? {
        guard case let .example(id) = selected else { return nil }
        return catalog.examples.first { $0.id == id }
    }
    private var currentFeature: DemoFeature? {
        guard case let .feature(feature) = selected else { return nil }
        return feature
    }
    private var title: String {
        if let currentExample { return DemoLocalizations.exampleTitle(currentExample, in: language) }
        if let currentFeature { return currentFeature.localizedTitle(in: language) }
        return DemoLocalizations.text("examples", in: language)
    }
    private var markdown: String? {
        currentExample?.markdown ?? currentFeature.flatMap { pageCatalog.markdown(for: $0) ?? $0.markdown }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                if let error = catalog.error {
                    ContentUnavailableView(DemoLocalizations.text("examples_unavailable", in: language),
                                           systemImage: "doc.questionmark", description: Text(error))
                } else {
                    pageContent
                }
            }
            .navigationTitle(DemoLocalizations.text("app_title", in: language))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(DemoLocalizations.text("examples", in: language), systemImage: "line.3.horizontal") { showNavigation = true }
                        .accessibilityIdentifier("open-examples")
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if markdown != nil {
                        Button(DemoLocalizations.text("source", in: language), systemImage: "chevron.left.forwardslash.chevron.right") {
                            showSource = true
                        }
                        .accessibilityIdentifier("view-markdown-source")
                        Button(DemoLocalizations.text("open_editor", in: language), systemImage: "square.and.pencil") {
                            let controller = MarkdownEditorController(text: pageCatalog.pages["editor"] ?? markdown ?? "")
                            controller.mode = .formatted
                            editorSession = .init(controller: controller)
                        }
                        .accessibilityIdentifier("open-demo-editor")
                    }
                    Menu {
                        ForEach(DemoTheme.allCases) { candidate in
                            Button(candidate.localizedTitle(in: language)) { theme = candidate }
                        }
                    } label: {
                        Label(DemoLocalizations.text("drawer_theme", in: language), systemImage: "paintpalette")
                    }
                    .accessibilityIdentifier("theme-menu")
                }
            }
            .sheet(isPresented: $showNavigation) {
                DemoNavigationSheet(catalog: catalog, selected: $selected, language: $language)
                    .presentationDetents([.large])
            }
            .sheet(isPresented: $showSource) {
                DemoSourceSheet(markdown: markdown ?? "", language: language)
            }
            .sheet(item: $editorSession) { session in
                NavigationStack {
                    SmoothMarkdownEditor(controller: session.controller)
                        .navigationTitle(DemoLocalizations.text("editor", in: language))
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button(DemoLocalizations.text("close", in: language)) { editorSession = nil }
                            }
                        }
                }
            }
        }
        .preferredColorScheme(theme.isDark ? .dark : .light)
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline).accessibilityIdentifier("demo-current-title")
                Text("\(DemoLocalizations.text("theme_status", in: language)): \(theme.localizedTitle(in: language)) · \(language.nativeName)")
                    .font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("demo-current-theme")
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.isDark ? Color(.secondarySystemBackground) : Color.blue.opacity(0.10))
    }

    @ViewBuilder
    private var pageContent: some View {
        if currentFeature == .performance {
            PerformanceDemoView().accessibilityIdentifier("demo-performance")
        } else if currentFeature == .mermaid {
            MermaidGalleryView().accessibilityIdentifier("demo-mermaid-gallery")
        } else if currentFeature == .streaming {
            DemoStreamingView(styleSheet: theme.styleSheet, plugins: plugins)
        } else if currentFeature == .html, let markdown {
            DemoHTMLView(markdown: markdown, styleSheet: theme.styleSheet, plugins: plugins)
        } else if currentFeature == .chatList {
            DemoChatListView(parentIsDark: theme.isDark)
        } else if currentFeature == .conversationList {
            ContentUnavailableView(DemoFeature.conversationList.localizedTitle(in: language),
                                   systemImage: "bubble.left.and.bubble.right",
                                   description: Text(DemoLocalizations.text("conversation_unported", in: language)))
        } else if let markdown {
            VStack(spacing: 0) {
                if let linkMessage {
                    Text("\(DemoLocalizations.text("link_tapped", in: language)): \(linkMessage)")
                        .font(.caption).accessibilityIdentifier("demo-link-message")
                }
                SmoothMarkdownView(markdown: markdown,
                                   onLinkTap: { linkMessage = $0.absoluteString },
                                   enableHTML: false,
                                   styleSheet: theme.styleSheet, plugins: plugins)
                    .id(selected)
                    .accessibilityIdentifier("demo-reader")
            }
        } else if let error = pageCatalog.error {
            ContentUnavailableView(DemoLocalizations.text("demo_page_unavailable", in: language),
                                   systemImage: "doc.questionmark",
                                   description: Text(error))
        }
    }
}

private struct DemoNavigationSheet: View {
    @Environment(\.dismiss) private var dismiss
    let catalog: DemoExampleCatalog
    @Binding var selected: DemoPage
    @Binding var language: DemoLanguage

    var body: some View {
        NavigationStack {
            List {
                Section(DemoLocalizations.text("editor", in: language)) {
                    Text(DemoLocalizations.text("editor_hint", in: language))
                        .foregroundStyle(.secondary)
                }
                Section(DemoLocalizations.text("drawer_header_title", in: language)) {
                    ForEach(catalog.examples) { example in
                        Button(DemoLocalizations.exampleTitle(example, in: language)) { choose(.example(example.id)) }
                            .accessibilityIdentifier("example-\(example.id)")
                    }
                }
                Section(DemoLocalizations.text("drawer_demos", in: language)) {
                    ForEach(DemoFeature.allCases) { feature in
                        Button {
                            choose(.feature(feature))
                        } label: {
                            VStack(alignment: .leading) {
                                Text(feature.localizedTitle(in: language))
                                if let subtitle = feature.localizedSubtitle(in: language) {
                                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .accessibilityIdentifier("feature-\(feature.rawValue)")
                    }
                }
                Section(DemoLocalizations.text("language", in: language)) {
                    ForEach(DemoLanguage.allCases) { candidate in
                        Button(candidate.nativeName) {
                            language = candidate
                            dismiss()
                        }
                        .accessibilityIdentifier("language-\(candidate.rawValue)")
                    }
                }
            }
            .navigationTitle(DemoLocalizations.text("examples_demos", in: language))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button(DemoLocalizations.text("close", in: language)) { dismiss() } }
            }
        }
    }

    private func choose(_ page: DemoPage) {
        selected = page
        dismiss()
    }
}

private struct DemoSourceSheet: View {
    @Environment(\.dismiss) private var dismiss
    let markdown: String
    let language: DemoLanguage

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(markdown)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding()
                    .accessibilityIdentifier("markdown-source-content")
            }
            .navigationTitle(DemoLocalizations.text("source_title", in: language))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button(DemoLocalizations.text("close", in: language)) { dismiss() } }
            }
        }
    }
}
