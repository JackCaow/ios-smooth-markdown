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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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

    private var exampleIcon: String {
        DemoNavigationIcon.example(currentExample?.id ?? "")
    }

    var body: some View {
        NavigationStack(path: $routePath) {
            VStack(spacing: 0) {
                header(title: title, icon: exampleIcon)
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
                ToolbarItem(placement: .topBarLeading) {
                    Button(DemoLocalizations.text("examples", in: language), systemImage: "line.3.horizontal") { showNavigation = true }
                        .accessibilityIdentifier("open-examples")
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
                                    isDark: theme.isDark,
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
                case let .editor(session):
                    editorPage(session)
                }
            }
        }
        .preferredColorScheme(theme.isDark ? .dark : .light)
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

    private func header(title: String, icon: String) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    headerIdentity(title: title, icon: icon)
                    themeBadge
                }
            } else {
                HStack(spacing: 12) {
                    headerIdentity(title: title, icon: icon)
                    Spacer(minLength: 4)
                    themeBadge
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? 12 : 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(theme.isDark ? .white : Color.primary)
        .background(theme.isDark ? Color(red: 22 / 255, green: 27 / 255, blue: 34 / 255)
                                 : Color.blue.opacity(0.16))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.isDark ? Color(red: 48 / 255, green: 54 / 255, blue: 61 / 255)
                                   : Color.gray.opacity(0.3))
                .frame(height: 1)
        }
    }

    private func headerIdentity(title: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 21))
                .accessibilityHidden(true)
            Text(title)
                .font(DemoTypography.pageTitle)
                .accessibilityIdentifier("demo-current-title")
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var themeBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: theme.isDark ? "moon.fill" : "sun.max.fill")
                .font(DemoTypography.metadata)
                .accessibilityHidden(true)
            Text(theme.localizedTitle(in: language))
                .font(DemoTypography.metadata)
                .accessibilityLabel("\(theme.localizedTitle(in: language)) · \(language.nativeName)")
                .accessibilityIdentifier("demo-current-theme")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(theme.isDark ? Color(red: 33 / 255, green: 38 / 255, blue: 45 / 255)
                                 : Color.white.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
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
                .overlay(alignment: .bottomTrailing) {
                    Button {
                        showSource = true
                    } label: {
                        Image(systemName: "chevron.left.forwardslash.chevron.right")
                            .font(.system(size: 21, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(width: 56, height: 56)
                            .background(Color.blue, in: Circle())
                            .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
                    }
                    .accessibilityLabel(DemoLocalizations.text("source", in: language))
                    .accessibilityIdentifier("view-markdown-source")
                    .padding(20)
                }
        }
    }

    private func featurePage(_ feature: DemoFeature) -> some View {
        VStack(spacing: 0) {
            header(title: feature.pageTitle(in: language), icon: DemoNavigationIcon.feature(feature))
            featureContent(feature)
        }
        .navigationTitle(feature.pageTitle(in: language))
        .navigationBarTitleDisplayMode(.inline)
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
    let isDark: Bool
    let onOpenEditor: () -> Void
    let onOpenFeature: (DemoFeature) -> Void

    var body: some View {
        NavigationStack {
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
                Section {
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
                    .accessibilityIdentifier("navigation-editor")
                }
                Section {
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
                            .listRowBackground(selected == .example(example.id) && isDark
                                               ? Color(red: 22 / 255, green: 27 / 255, blue: 34 / 255) : Color.clear)
                            .accessibilityIdentifier("example-\(example.id)")
                    }
                }
                Section(DemoLocalizations.text("drawer_demos", in: language)) {
                    ForEach(DemoFeature.allCases) { feature in
                        Button {
                            onOpenFeature(feature)
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: DemoNavigationIcon.feature(feature))
                                    .frame(width: 24)
                                VStack(alignment: .leading) {
                                    Text(feature.localizedTitle(in: language))
                                    if let subtitle = feature.localizedSubtitle(in: language) {
                                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .accessibilityIdentifier("feature-\(feature.rawValue)")
                    }
                }
                Section(DemoLocalizations.text("language", in: language)) {
                    ForEach(DemoLanguage.allCases) { candidate in
                        Button {
                            language = candidate
                            dismiss()
                        } label: {
                            Label(candidate.nativeName, systemImage: "globe")
                        }
                        .accessibilityIdentifier("language-\(candidate.rawValue)")
                    }
                }
            }
            .accessibilityIdentifier("demo-navigation-list")
            .navigationTitle(DemoLocalizations.text("examples_demos", in: language))
            .scrollContentBackground(.hidden)
            .background(isDark ? Color(red: 13 / 255, green: 17 / 255, blue: 23 / 255) : .white)
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
                    .font(.system(.body, design: .monospaced))
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
