import SmoothMarkdown
import SwiftUI
import UIKit

struct FixtureDemoView: View {
    @StateObject private var controller = MarkdownEditorController(text: editorFixtureText())
    @State private var showEditor = ProcessInfo.processInfo.arguments.contains("--cross-block-editor-fixture") ||
        ProcessInfo.processInfo.arguments.contains("--list-text-endpoint-fixture") ||
        ProcessInfo.processInfo.arguments.contains("--inline-editor-fixture") ||
        ProcessInfo.processInfo.arguments.contains("--visible-inline-editor-fixture") ||
        ProcessInfo.processInfo.arguments.contains("--list-editor-fixture") ||
        ProcessInfo.processInfo.arguments.contains("--selection-list-editor-fixture") ||
        ProcessInfo.processInfo.arguments.contains("--empty-list-editor-fixture") ||
        ProcessInfo.processInfo.arguments.contains("--nested-list-editor-fixture") ||
        ProcessInfo.processInfo.arguments.contains("--formatted-find-fixture") ||
        ProcessInfo.processInfo.arguments.contains("--host-io-fixture")
    @State private var enableHTML = false
    @State private var showStructured = false
    @State private var showSelection = false
    @State private var showPerformance = false
    @State private var themeIndex = 0
    @State private var imageTapCount = 0
    @State private var lastImageTap = ""
    @State private var clipboardPreview = ""
    @State private var codeCopyCount = 0
    @State private var codeCopyPayload = ""
    @State private var hostCodeTapCount = 0
    @State private var hostIOStatus = "idle"
    @State private var exportedMarkdown = ""
    private let plugins = ParserPluginRegistry.builtIns()
    private let themes: [(String, MarkdownStyleSheet)] = [
        ("System", .default()), ("Light", .light()), ("Dark", .dark()),
        ("GitHub", .github()), ("GitHub dark", .github(dark: true)),
        ("VS Code", .vscode()), ("VS Code dark", .vscode(dark: true)),
    ]

    var body: some View {
        if ProcessInfo.processInfo.arguments.contains("--reader-code-range-fixture") {
            VStack(spacing: 0) {
                Button("Show clipboard") { clipboardPreview = UIPasteboard.general.string ?? "" }
                Text("Copied: \(clipboardPreview)").accessibilityIdentifier("code-range-clipboard")
                Text("Code callbacks: \(codeCopyCount)").accessibilityIdentifier("code-copy-callback-count")
                Text("Code callback payload: \(codeCopyPayload)").accessibilityIdentifier("code-copy-callback-payload")
                SmoothMarkdownView(markdown: "Before code.\n\n```swift\nlet answer = 42\n```\n\nAfter code.",
                                   onCodeCopy: { code, language in
                                       codeCopyCount += 1
                                       codeCopyPayload = "\(code.replacingOccurrences(of: "\n", with: "↵"))|\(language ?? "")"
                                   },
                                   styleSheet: .light(), selectable: true)
            }
        } else if ProcessInfo.processInfo.arguments.contains("--reader-code-custom-fixture") {
            VStack(spacing: 0) {
                Text("Host taps: \(hostCodeTapCount)").accessibilityIdentifier("host-code-tap-count")
                SmoothMarkdownView(markdown: "Before code.\n\n```swift\nlet answer = 42\n```\n\nAfter code.",
                                   codeBuilder: { code, _ in
                                       AnyView(VStack(alignment: .leading) {
                                           Text("Host code: \(code.trimmingCharacters(in: .whitespacesAndNewlines))")
                                           Button("Host code action") { hostCodeTapCount += 1 }
                                       })
                                   }, styleSheet: .light(), selectable: true)
            }
        } else if ProcessInfo.processInfo.arguments.contains("--reader-code-no-copy-fixture") {
            SmoothMarkdownView(markdown: "Before code.\n\n```swift\nlet answer = 42\n```\n\nAfter code.",
                               codeBlockOptions: .init(showCopyButton: false),
                               styleSheet: .light(), selectable: true)
        } else if ProcessInfo.processInfo.arguments.contains("--reader-math-range-fixture") {
            VStack(spacing: 0) {
                Button("Show clipboard") { clipboardPreview = UIPasteboard.general.string ?? "" }
                Text("Copied: \(clipboardPreview)").accessibilityIdentifier("math-range-clipboard")
                SmoothMarkdownView(markdown: "Before formula.\n\n$$\nE=mc^2\n$$\n\nAfter formula.",
                                   styleSheet: .light(), selectable: true)
            }
        } else if ProcessInfo.processInfo.arguments.contains("--reader-math-standalone-fixture") {
            VStack(spacing: 0) {
                Button("Show clipboard") { clipboardPreview = UIPasteboard.general.string ?? "" }
                Text("Copied: \(clipboardPreview)").accessibilityIdentifier("math-range-clipboard")
                SmoothMarkdownView(markdown: "$$E=mc^2$$", styleSheet: .light(), selectable: true)
            }
        } else if ProcessInfo.processInfo.arguments.contains("--reader-table-range-fixture") {
            VStack(spacing: 0) {
                Button("Show clipboard") { clipboardPreview = UIPasteboard.general.string ?? "" }
                Text("Copied: \(clipboardPreview)").accessibilityIdentifier("table-range-clipboard")
                SmoothMarkdownView(markdown: "Before table.\n\n| Name | Value |\n| --- | --- |\n| Alpha | 42 |\n\nAfter table.",
                                   styleSheet: .light(), selectable: true)
            }
        } else if ProcessInfo.processInfo.arguments.contains("--reader-multi-image-range-fixture") {
            VStack(spacing: 0) {
                Text("Image taps: \(imageTapCount)").accessibilityIdentifier("image-tap-count")
                Button("Show clipboard") { clipboardPreview = UIPasteboard.general.string ?? "" }
                Text("Copied: \(clipboardPreview)").accessibilityIdentifier("image-range-clipboard")
                SmoothMarkdownView(markdown: "Before image.\n\n![Bundled vector](native-vector.svg)\n\nMiddle text.\n\n![Bundled vector](native-vector.svg)\n\nAfter image.",
                                   onImageTapWithMetadata: { _, _, _ in imageTapCount += 1 },
                                   styleSheet: .light(), selectable: true)
            }
        } else if ProcessInfo.processInfo.arguments.contains("--reader-image-range-fixture") {
            VStack(spacing: 0) {
                Text("Image taps: \(imageTapCount)").accessibilityIdentifier("image-tap-count")
                Button("Show clipboard") { clipboardPreview = UIPasteboard.general.string ?? "" }
                Text("Copied: \(clipboardPreview)").accessibilityIdentifier("image-range-clipboard")
                SmoothMarkdownView(markdown: "Before image.\n\n![Bundled vector](native-vector.svg \"Vector title\")\n\nAfter image.",
                                   onImageTapWithMetadata: { _, _, _ in imageTapCount += 1 },
                                   styleSheet: .light(), selectable: true)
            }
        } else if ProcessInfo.processInfo.arguments.contains("--accessibility-fixture") {
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
                                   styleSheet: themes[themeIndex].1, plugins: plugins,
                                   selectable: true)
            }
        }
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("--cross-block-editor-fixture") ||
                ProcessInfo.processInfo.arguments.contains("--list-text-endpoint-fixture") ||
                ProcessInfo.processInfo.arguments.contains("--inline-editor-fixture") ||
                ProcessInfo.processInfo.arguments.contains("--visible-inline-editor-fixture") ||
                ProcessInfo.processInfo.arguments.contains("--list-editor-fixture") ||
                ProcessInfo.processInfo.arguments.contains("--selection-list-editor-fixture") ||
                ProcessInfo.processInfo.arguments.contains("--empty-list-editor-fixture") ||
                ProcessInfo.processInfo.arguments.contains("--nested-list-editor-fixture") ||
                ProcessInfo.processInfo.arguments.contains("--formatted-find-fixture") {
                controller.mode = .formatted
            }
        }
        }
    }
}

private func editorFixtureText() -> String {
    let arguments = ProcessInfo.processInfo.arguments
    if arguments.contains("--cross-block-editor-fixture") { return crossBlockEditorFixture }
    if arguments.contains("--list-text-endpoint-fixture") {
        return "Lead\n\n- BeforeX\n- middle\n- YAfter\n\nTail"
    }
    if arguments.contains("--inline-editor-fixture") { return inlineEditorFixture }
    if arguments.contains("--visible-inline-editor-fixture") {
        return "Start **bold** end\n\n# Next [link](https://example.com) end"
    }
    if arguments.contains("--empty-list-editor-fixture") { return emptyListEditorFixture }
    if arguments.contains("--nested-list-editor-fixture") { return nestedListEditorFixture }
    if arguments.contains("--formatted-find-fixture") {
        return "- Parent\n  target continuation\n- target next\n\n| target header | Other |\n| --- | --- |\n| target body | x |\n\n$$\ntarget raw\n$$"
    }
    if arguments.contains("--list-editor-fixture") { return listEditorFixture }
    if arguments.contains("--selection-list-editor-fixture") { return "- First\n- Second\n- Third" }
    if arguments.contains("--host-io-fixture") { return hostIOFixture }
    return demoMarkdown
}
