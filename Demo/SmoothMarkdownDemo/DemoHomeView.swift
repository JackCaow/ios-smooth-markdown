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
    @State private var htmlEnabled = true
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
    private var title: String { currentExample?.title ?? currentFeature?.title ?? "Examples unavailable" }
    private var markdown: String? {
        currentExample?.markdown ?? currentFeature.flatMap { pageCatalog.markdown(for: $0) ?? $0.markdown }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                if let error = catalog.error {
                    ContentUnavailableView("Examples unavailable", systemImage: "doc.questionmark", description: Text(error))
                } else {
                    pageContent
                }
            }
            .navigationTitle("Smooth Markdown Demo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Examples", systemImage: "line.3.horizontal") { showNavigation = true }
                        .accessibilityIdentifier("open-examples")
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if markdown != nil {
                        Button("View Markdown Source", systemImage: "chevron.left.forwardslash.chevron.right") {
                            showSource = true
                        }
                        .accessibilityIdentifier("view-markdown-source")
                        Button("Open Editor", systemImage: "square.and.pencil") {
                            editorSession = .init(controller: MarkdownEditorController(
                                text: pageCatalog.pages["editor"] ?? markdown ?? ""))
                        }
                        .accessibilityIdentifier("open-demo-editor")
                    }
                    Menu {
                        ForEach(DemoTheme.allCases) { candidate in
                            Button(candidate.rawValue) { theme = candidate }
                        }
                    } label: {
                        Label("Theme", systemImage: "paintpalette")
                    }
                    .accessibilityIdentifier("theme-menu")
                }
            }
            .sheet(isPresented: $showNavigation) {
                DemoNavigationSheet(catalog: catalog, selected: $selected, language: $language)
                    .presentationDetents([.large])
            }
            .sheet(isPresented: $showSource) {
                DemoSourceSheet(markdown: markdown ?? "")
            }
            .sheet(item: $editorSession) { session in
                NavigationStack {
                    SmoothMarkdownEditor(controller: session.controller)
                        .navigationTitle("Markdown Editor")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Close") { editorSession = nil }
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
                Text("Theme: \(theme.rawValue) · \(language.nativeName)")
                    .font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("demo-current-theme")
            }
            Spacer()
            if currentFeature == .html {
                Toggle("HTML", isOn: $htmlEnabled).labelsHidden()
                    .accessibilityLabel("Enable HTML")
            }
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
                .accessibilityIdentifier("demo-streaming")
        } else if currentFeature == .conversationList {
            ContentUnavailableView("Conversation List", systemImage: "bubble.left.and.bubble.right",
                                   description: Text("Long-press actions, swipes, and multi-select from Flutter are not ported to this iOS demo."))
        } else if let markdown {
            VStack(spacing: 0) {
                if let linkMessage {
                    Text(linkMessage).font(.caption).accessibilityIdentifier("demo-link-message")
                }
                SmoothMarkdownView(markdown: markdown,
                                   onLinkTap: { linkMessage = "Link tapped: \($0.absoluteString)" },
                                   enableHTML: currentFeature == .html && htmlEnabled,
                                   styleSheet: theme.styleSheet, plugins: plugins)
                    .id(selected)
                    .accessibilityIdentifier("demo-reader")
            }
        } else if let error = pageCatalog.error {
            ContentUnavailableView("Demo page unavailable", systemImage: "doc.questionmark",
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
                Section("Markdown Editor") {
                    Text("Use the editor button on the selected example.")
                        .foregroundStyle(.secondary)
                }
                Section("Examples") {
                    ForEach(catalog.examples) { example in
                        Button(example.title) { choose(.example(example.id)) }
                            .accessibilityIdentifier("example-\(example.id)")
                    }
                }
                Section("Demos") {
                    ForEach(DemoFeature.allCases) { feature in
                        Button {
                            choose(.feature(feature))
                        } label: {
                            VStack(alignment: .leading) {
                                Text(feature.title)
                                if let subtitle = feature.subtitle {
                                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .accessibilityIdentifier("feature-\(feature.rawValue)")
                    }
                }
                Section("Language") {
                    ForEach(DemoLanguage.allCases) { candidate in
                        Button(candidate.nativeName) {
                            language = candidate
                            dismiss()
                        }
                        .accessibilityIdentifier("language-\(candidate.rawValue)")
                    }
                    Text("The native demo chrome is not fully localized yet; sample Markdown stays in its original language.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Examples & Demos")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Close") { dismiss() } }
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
            .navigationTitle("Markdown Source")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Close") { dismiss() } }
            }
        }
    }
}
