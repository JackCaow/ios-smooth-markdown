import SmoothMarkdown
import SwiftUI

private struct EditorSession: Identifiable {
    let id = UUID()
    let controller: MarkdownEditorController
}

private enum DemoRoute: Hashable {
    case feature(DemoFeature)
    case editor(UUID)
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
    @State private var openEditorAfterNavigation = false
    @State private var openFeatureAfterNavigation: DemoFeature?
    @State private var routePath: [DemoRoute] = []
    @State private var linkMessage: String?
    private let plugins = ParserPluginRegistry.builtIns()

    private var currentExample: DemoExample? {
        guard case let .example(id) = selected else { return nil }
        return catalog.examples.first { $0.id == id }
    }
    private var title: String {
        if let currentExample { return currentExample.title }
        return DemoLocalizations.text("examples", in: language)
    }
    private var markdown: String? {
        currentExample?.markdown
    }

    var body: some View {
        NavigationStack(path: $routePath) {
            VStack(spacing: 0) {
                header(title: title)
                if let error = catalog.error {
                    ContentUnavailableView(DemoLocalizations.text("examples_unavailable", in: language),
                                           systemImage: "doc.questionmark", description: Text(error))
                } else {
                    pageContent
                }
            }
            .navigationTitle("Smooth Markdown Demo")
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
                            openEditor()
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
            .sheet(isPresented: $showNavigation, onDismiss: {
                if openEditorAfterNavigation {
                    openEditorAfterNavigation = false
                    openEditor()
                } else if let feature = openFeatureAfterNavigation {
                    openFeatureAfterNavigation = nil
                    routePath.append(.feature(feature))
                }
            }) {
                DemoNavigationSheet(catalog: catalog, selected: $selected, language: $language,
                                    onOpenEditor: {
                                        openEditorAfterNavigation = true
                                        showNavigation = false
                                    },
                                    onOpenFeature: { feature in
                                        openFeatureAfterNavigation = feature
                                        showNavigation = false
                                    })
                    .presentationDetents([.large])
            }
            .sheet(isPresented: $showSource) {
                DemoSourceSheet(markdown: markdown ?? "", language: language)
            }
            .navigationDestination(for: DemoRoute.self) { route in
                switch route {
                case let .feature(feature):
                    featurePage(feature)
                case let .editor(id):
                    if let session = editorSession, session.id == id {
                        editorPage(session)
                    }
                }
            }
        }
        .preferredColorScheme(theme.isDark ? .dark : .light)
    }

    private func openEditor() {
        let controller = MarkdownEditorController(text: pageCatalog.pages["editor"] ?? markdown ?? "")
        controller.mode = .formatted
        let session = EditorSession(controller: controller)
        editorSession = session
        routePath.append(.editor(session.id))
    }

    private func editorPage(_ session: EditorSession) -> some View {
        DemoEditorView(controller: session.controller)
            .navigationTitle(DemoLocalizations.text("editor", in: language))
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        routePath.removeLast()
                    } label: {
                        Label(DemoLocalizations.text("back", in: language), systemImage: "chevron.left")
                    }
                    .accessibilityIdentifier("demo-editor-back")
                }
            }
    }

    private func header(title: String) -> some View {
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
        if let markdown {
            SmoothMarkdownView(markdown: markdown,
                               onLinkTap: { url in
                                   let tapped = url.absoluteString
                                   linkMessage = tapped
                                   Task { @MainActor in
                                       try? await Task.sleep(for: .seconds(2))
                                       if linkMessage == tapped { linkMessage = nil }
                                   }
                               },
                               enableHTML: false,
                               styleSheet: theme.styleSheet, plugins: plugins)
                .id(selected)
                .accessibilityIdentifier("demo-reader")
                .overlay(alignment: .bottom) {
                    if let linkMessage {
                        Text("\(DemoLocalizations.text("link_tapped", in: language)): \(linkMessage)")
                            .font(.caption)
                            .padding(10)
                            .background(.regularMaterial, in: Capsule())
                            .padding(.bottom, 12)
                            .accessibilityIdentifier("demo-link-message")
                    }
                }
        }
    }

    private func featurePage(_ feature: DemoFeature) -> some View {
        VStack(spacing: 0) {
            header(title: feature.pageTitle(in: language))
            featureContent(feature)
        }
        .navigationTitle(feature.pageTitle(in: language))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    routePath.removeLast()
                } label: {
                    Label(DemoLocalizations.text("back", in: language), systemImage: "chevron.left")
                }
                .accessibilityIdentifier("demo-feature-back")
            }
        }
        .accessibilityIdentifier("demo-feature-page")
    }

    @ViewBuilder
    private func featureContent(_ feature: DemoFeature) -> some View {
        let featureMarkdown = pageCatalog.markdown(for: feature) ?? feature.markdown
        if feature == .performance {
            PerformanceDemoView().accessibilityIdentifier("demo-performance")
        } else if feature == .mermaid {
            MermaidGalleryView().accessibilityIdentifier("demo-mermaid-gallery")
        } else if feature == .streaming {
            DemoStreamingView(styleSheet: theme.styleSheet, plugins: plugins)
        } else if feature == .html, let featureMarkdown {
            DemoHTMLView(markdown: featureMarkdown, styleSheet: theme.styleSheet, plugins: plugins)
        } else if feature == .chatList {
            DemoChatListView(parentIsDark: theme.isDark)
        } else if feature == .aiChat {
            DemoAIChatView(parentIsDark: theme.isDark)
        } else if feature == .conversationList {
            DemoConversationListView()
        } else if feature == .plugins, let featureMarkdown {
            DemoPluginView(markdown: featureMarkdown, styleSheet: theme.styleSheet)
        } else if let featureMarkdown {
            SmoothMarkdownView(markdown: featureMarkdown,
                               enableHTML: false,
                               styleSheet: theme.styleSheet, plugins: plugins)
                .accessibilityIdentifier("demo-reader")
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
    let onOpenEditor: () -> Void
    let onOpenFeature: (DemoFeature) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button(action: onOpenEditor) {
                        VStack(alignment: .leading) {
                            Text(DemoLocalizations.text("editor", in: language))
                            Text("Scratch-style editing preview")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("navigation-editor")
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
                            onOpenFeature(feature)
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
