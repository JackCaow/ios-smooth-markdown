import SmoothMarkdown
import SwiftUI

private struct EditorSession: Identifiable, Hashable {
    let id = UUID()
    let controller: MarkdownEditorController

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

private enum DemoRoute: Hashable {
    case feature(DemoFeature)
    case editor(EditorSession)
}

private enum DemoNavigationIcon {
    static func example(_ id: String) -> String {
        switch id {
        case "basic-formatting": "textformat"
        case "headers": "textformat.size"
        case "lists": "list.bullet"
        case "code-blocks": "chevron.left.forwardslash.chevron.right"
        case "quotes-rules": "text.quote"
        case "links-images": "link"
        case "enhanced-ui": "sparkles"
        case "theme-showcase": "paintpalette"
        case "details-summary": "square.grid.2x2"
        default: "doc.text"
        }
    }

    static func feature(_ feature: DemoFeature) -> String {
        switch feature {
        case .math: "function"
        case .streaming: "waveform.path"
        case .footnotes: "note.text"
        case .html: "chevron.left.forwardslash.chevron.right"
        case .chatList: "message"
        case .aiChat: "sparkles"
        case .conversationList: "bubble.left.and.bubble.right"
        case .plugins: "puzzlepiece.extension"
        case .mermaid, .structured: "point.3.connected.trianglepath.dotted"
        case .selection: "text.cursor"
        case .performance: "speedometer"
        }
    }
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
                if let error = catalog.error {
                    ContentUnavailableView(DemoLocalizations.text("examples_unavailable", in: language),
                                           systemImage: "doc.questionmark", description: Text(error))
                } else {
                    pageContent
                }
            }
            .background(theme.isDark ? Color(red: 13 / 255, green: 17 / 255, blue: 23 / 255) : .white)
            .navigationTitle("Smooth Markdown Demo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(theme.isDark ? Color(red: 22 / 255, green: 27 / 255, blue: 34 / 255) : .white,
                               for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Smooth Markdown Demo")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .accessibilityAddTraits(.isHeader)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button(DemoLocalizations.text("examples", in: language), systemImage: "line.3.horizontal") {
                        withAnimation(.easeOut(duration: 0.2)) { showNavigation = true }
                    }
                        .accessibilityIdentifier("open-examples")
                        .accessibilityValue(title)
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if markdown != nil {
                        Button(DemoLocalizations.text("open_editor", in: language), systemImage: "square.and.pencil") {
                            openEditor()
                        }
                        .accessibilityIdentifier("open-demo-editor")
                    }
                    Menu {
                        ForEach(DemoTheme.allCases) { candidate in
                            Button {
                                theme = candidate
                            } label: {
                                Label(candidate.localizedTitle(in: language),
                                      systemImage: candidate == theme ? "checkmark.circle.fill" : "circle")
                            }
                        }
                    } label: {
                        Label(DemoLocalizations.text("drawer_theme", in: language), systemImage: "paintpalette")
                    }
                    .accessibilityIdentifier("theme-menu")
                    .accessibilityValue("\(theme.localizedTitle(in: language)) · \(language.nativeName)")
                }
            }
            .sheet(isPresented: $showSource) {
                DemoSourceSheet(markdown: markdown ?? "", language: language)
                    .presentationDetents([.medium, .large])
            }
            .navigationDestination(for: DemoRoute.self) { route in
                switch route {
                case let .feature(feature):
                    featurePage(feature)
                case let .editor(session):
                    editorPage(session)
                }
            }
        }
        .overlay {
            if showNavigation {
                DemoNavigationOverlay(catalog: catalog, selected: $selected, language: $language,
                                      isDark: theme.isDark,
                                      onClose: closeNavigation,
                                      onOpenEditor: {
                                          openEditorAfterNavigation = true
                                          closeNavigation()
                                      },
                                      onOpenFeature: { feature in
                                          openFeatureAfterNavigation = feature
                                          closeNavigation()
                                      })
                    .transition(.opacity)
            }
        }
        .onChange(of: showNavigation) { _, isOpen in
            guard !isOpen else { return }
            if openEditorAfterNavigation {
                openEditorAfterNavigation = false
                openEditor()
            } else if let feature = openFeatureAfterNavigation {
                openFeatureAfterNavigation = nil
                routePath.append(.feature(feature))
            }
        }
        .preferredColorScheme(theme.isDark ? .dark : .light)
    }

    private func closeNavigation() {
        withAnimation(.easeOut(duration: 0.2)) { showNavigation = false }
    }

    private func openEditor() {
        let controller = MarkdownEditorController(text: pageCatalog.pages["editor"] ?? markdown ?? "")
        controller.mode = .formatted
        routePath.append(.editor(EditorSession(controller: controller)))
    }

    private func editorPage(_ session: EditorSession) -> some View {
        DemoEditorView(controller: session.controller)
            .navigationTitle(DemoLocalizations.text("editor", in: language))
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { routePath.removeLast() } label: {
                        Label(DemoLocalizations.text("back", in: language), systemImage: "chevron.left")
                    }
                    .accessibilityIdentifier("demo-editor-back")
                }
            }
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
                               useEnhancedComponents: true,
                               styleSheet: theme.styleSheet, plugins: plugins,
                               selectable: true)
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
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    HStack {
                        Spacer()
                        Button {
                            showSource = true
                        } label: {
                            Label(DemoLocalizations.text("source", in: language),
                                  systemImage: "chevron.left.forwardslash.chevron.right")
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("view-markdown-source")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.regularMaterial)
                }
        }
    }

    private func featurePage(_ feature: DemoFeature) -> some View {
        featureContent(feature)
        .navigationTitle(feature.pageTitle(in: language))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color(uiColor: .systemBackground), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { routePath.removeLast() } label: {
                    Label(DemoLocalizations.text("back", in: language), systemImage: "chevron.left")
                }
                .accessibilityIdentifier("demo-feature-back")
            }
        }
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
        } else if feature == .selection {
            DemoSelectionControllerView(styleSheet: theme.styleSheet)
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

private struct DemoNavigationOverlay: View {
    let catalog: DemoExampleCatalog
    @Binding var selected: DemoPage
    @Binding var language: DemoLanguage
    let isDark: Bool
    let onClose: () -> Void
    let onOpenEditor: () -> Void
    let onOpenFeature: (DemoFeature) -> Void

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                DemoNavigationDrawer(catalog: catalog, selected: $selected, language: $language,
                                     isDark: isDark, onClose: onClose,
                                     onOpenEditor: onOpenEditor, onOpenFeature: onOpenFeature)
                    .frame(width: min(304, geometry.size.width - 48))
                    .frame(maxHeight: .infinity)
                    .background(isDark ? Color(red: 13 / 255, green: 17 / 255, blue: 23 / 255) : .white)
                    .clipped()
                    .transition(.move(edge: .leading))

                Button(action: onClose) {
                    Color.black.opacity(0.42)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(DemoLocalizations.text("close", in: language))
                .accessibilityIdentifier("navigation-scrim")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea(edges: .bottom)
    }

}

private struct DemoNavigationDrawer: View {
    let catalog: DemoExampleCatalog
    @Binding var selected: DemoPage
    @Binding var language: DemoLanguage
    let isDark: Bool
    let onClose: () -> Void
    let onOpenEditor: () -> Void
    let onOpenFeature: (DemoFeature) -> Void

    var body: some View {
        List {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 48))
                        Text(DemoLocalizations.text("drawer_header_title", in: language))
                            .font(.title2.bold())
                    }
                    Spacer()
                }
                .foregroundStyle(.white)
                .padding(16)
                .frame(maxWidth: .infinity, minHeight: 176, alignment: .bottomLeading)
                .background(LinearGradient(colors: isDark
                                            ? [Color(red: 22 / 255, green: 27 / 255, blue: 34 / 255),
                                               Color(red: 33 / 255, green: 38 / 255, blue: 45 / 255)]
                                            : [.blue, .purple],
                                           startPoint: .topLeading, endPoint: .bottomTrailing))
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .accessibilityIdentifier("navigation-header")
                Button(action: onOpenEditor) {
                    HStack(spacing: 14) {
                        Image(systemName: "square.and.pencil")
                            .frame(width: 24)
                        VStack(alignment: .leading) {
                            Text(DemoLocalizations.text("editor", in: language))
                            Text("Scratch-style editing preview")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                .listRowSeparator(.hidden)
                .overlay(alignment: .bottom) { Divider() }
                .accessibilityIdentifier("navigation-editor")
                ForEach(catalog.examples) { example in
                    Button { choose(.example(example.id)) } label: {
                        HStack(spacing: 14) {
                            Image(systemName: DemoNavigationIcon.example(example.id))
                                .frame(width: 24)
                                .foregroundStyle(selected == .example(example.id) ? Color.blue : .primary)
                            Text(DemoLocalizations.exampleTitle(example, in: language))
                                .fontWeight(selected == .example(example.id) ? .bold : .regular)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(selected == .example(example.id)
                                       ? (isDark ? Color(red: 22 / 255, green: 27 / 255, blue: 34 / 255)
                                          : Color.blue.opacity(0.08)) : Color.clear)
                    .overlay(alignment: .bottom) {
                        if example.id == catalog.examples.last?.id { Divider() }
                    }
                    .accessibilityIdentifier("example-\(example.id)")
                }
                Section(DemoLocalizations.text("drawer_demos", in: language)) {
                    ForEach(DemoFeature.allCases) { feature in
                        Button {
                            onOpenFeature(feature)
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: DemoNavigationIcon.feature(feature))
                                    .frame(width: 24)
                                Text(feature.localizedTitle(in: language))
                            }
                        }
                        .listRowSeparator(.hidden)
                        .accessibilityIdentifier("feature-\(feature.rawValue)")
                    }
                }
                Section(DemoLocalizations.text("language", in: language)) {
                    ForEach(DemoLanguage.allCases) { candidate in
                        Button {
                            language = candidate
                            onClose()
                        } label: {
                            Label(candidate.nativeName, systemImage: "globe")
                        }
                        .listRowSeparator(.hidden)
                        .accessibilityIdentifier("language-\(candidate.rawValue)")
                    }
                }
        }
        .listStyle(.plain)
        .accessibilityIdentifier("demo-navigation-list")
        .scrollContentBackground(.hidden)
        .background(isDark ? Color(red: 13 / 255, green: 17 / 255, blue: 23 / 255) : .white)
    }

    private func choose(_ page: DemoPage) {
        selected = page
        onClose()
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
                    .frame(maxWidth: 600, alignment: .leading)
                    .frame(maxWidth: .infinity)
                    .textSelection(.enabled)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
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
