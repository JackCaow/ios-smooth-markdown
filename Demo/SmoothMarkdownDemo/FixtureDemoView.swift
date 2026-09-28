import SmoothMarkdown
import SwiftUI

struct FixtureDemoView: View {
    @StateObject private var controller = MarkdownEditorController(
        text: ProcessInfo.processInfo.arguments.contains("--inline-editor-fixture") ? inlineEditorFixture :
            (ProcessInfo.processInfo.arguments.contains("--list-editor-fixture") ? listEditorFixture :
                (ProcessInfo.processInfo.arguments.contains("--host-io-fixture") ? hostIOFixture : demoMarkdown)))
    @State private var showEditor = ProcessInfo.processInfo.arguments.contains("--inline-editor-fixture") ||
        ProcessInfo.processInfo.arguments.contains("--list-editor-fixture") ||
        ProcessInfo.processInfo.arguments.contains("--host-io-fixture")
    @State private var enableHTML = false
    @State private var showStructured = false
    @State private var showSelection = false
    @State private var showPerformance = false
    @State private var themeIndex = 0
    @State private var imageTapCount = 0
    @State private var lastImageTap = ""
    @State private var hostIOStatus = "idle"
    @State private var exportedMarkdown = ""
    private let plugins = ParserPluginRegistry.builtIns()
    private let themes: [(String, MarkdownStyleSheet)] = [
        ("System", .default()), ("Light", .light()), ("Dark", .dark()),
        ("GitHub", .github()), ("GitHub dark", .github(dark: true)),
        ("VS Code", .vscode()), ("VS Code dark", .vscode(dark: true)),
    ]

    var body: some View {
        if ProcessInfo.processInfo.arguments.contains("--accessibility-fixture") {
            VStack(spacing: 0) {
                Text("Image taps: \(imageTapCount)").accessibilityIdentifier("image-tap-count")
                Text(lastImageTap).accessibilityIdentifier("image-tap-metadata")
                SmoothMarkdownView(markdown: accessibilityMarkdown,
                                   onImageTapWithMetadata: { source, alt, title in
                                       imageTapCount += 1
                                       lastImageTap = "\(source)|\(alt ?? "")|\(title ?? "")"
                                   },
                                   styleSheet: .light(), plugins: plugins, enableCrossBlockSelection: false)
            }
        } else {
        VStack(spacing: 0) {
            HStack {
                Button(showEditor ? "Read" : "Open editor") { showEditor.toggle() }
                if !showEditor && !showPerformance {
                    Button(showStructured ? "Show all" : "Structured") {
                        showStructured.toggle()
                        if showStructured { showSelection = false }
                    }
                    Button(showSelection ? "Show all" : "Selection") {
                        showSelection.toggle()
                        if showSelection { showStructured = false }
                    }
                    Button(enableHTML ? "HTML on" : "Enable HTML") { enableHTML.toggle() }
                    Menu("Theme: \(themes[themeIndex].0)") {
                        ForEach(themes.indices, id: \.self) { index in
                            Button(themes[index].0) { themeIndex = index }
                        }
                    }
                }
                Button(showPerformance ? "Close perf" : "Perf") { showPerformance.toggle() }
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            if showPerformance {
                PerformanceDemoView()
            } else if showEditor {
                if ProcessInfo.processInfo.arguments.contains("--host-io-fixture") {
                    Text("Host IO: \(hostIOStatus)").accessibilityIdentifier("host-io-status")
                    Text("Exported: \(exportedMarkdown)").accessibilityIdentifier("host-io-export")
                    SmoothMarkdownEditor(controller: controller,
                                         onPickImage: { .init(url: "assets/fixture.png", alt: "Picked") },
                                         onImportMarkdown: { "# Imported" },
                                         onExportMarkdown: { exportedMarkdown = $0 },
                                         onHostIOEvent: { event in
                                             hostIOStatus = "\(event.operation)-\(event.status)"
                                         })
                } else {
                    SmoothMarkdownEditor(controller: controller)
                }
            } else {
                SmoothMarkdownView(markdown: showSelection ? selectionMarkdown :
                                   (showStructured ? structuredMarkdown : controller.text), enableHTML: enableHTML,
                                   styleSheet: themes[themeIndex].1, plugins: plugins)
            }
        }
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("--inline-editor-fixture") ||
                ProcessInfo.processInfo.arguments.contains("--list-editor-fixture") {
                controller.mode = .formatted
            }
        }
        }
    }
}
