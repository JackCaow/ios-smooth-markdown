import SmoothMarkdown
import SwiftUI

/// Host callbacks and feedback for the editor page in Flutter's example app.
struct DemoEditorView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObservedObject var controller: MarkdownEditorController
    @State private var lastExport: String?
    @State private var hostMessage: String?
    @State private var showingHelp = false
    @State private var useDeviceIO = false
    @StateObject private var hostFiles = DemoEditorHostFiles()

    private let helpText = "Try the toolbar, slash commands at the start of a paragraph, wikilinks, Find, Focus, and the demo's image, import, and export callbacks."

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if dynamicTypeSize.isAccessibilitySize {
                DisclosureGroup("Editor help", isExpanded: $showingHelp) {
                    Text(helpText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Scratch-style editor preview")
                    .font(.title3.weight(.semibold))
                Text(helpText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Menu("Host I/O") {
                Toggle("Use device files and image URLs", isOn: $useDeviceIO)
            }
            .accessibilityIdentifier("editor-host-io-mode")
            SmoothMarkdownEditor(
                controller: controller,
                onPickImage: {
                    if useDeviceIO { return await hostFiles.pickImageURL() }
                    return MarkdownEditorImageSelection(url: "https://picsum.photos/640/360",
                                                        alt: "Sample image", title: "Demo image")
                },
                onImportMarkdown: {
                    if useDeviceIO { return try await hostFiles.importMarkdown() }
                    return "## Imported markdown\n\nThis came from the host callback."
                },
                onExportMarkdown: { markdown in
                    if useDeviceIO { try await hostFiles.exportMarkdown(markdown) }
                    lastExport = markdown
                },
                onExportPDF: { markdown, _ in
                    lastExport = "PDF export requested for \(markdown.utf16.count) characters"
                    hostMessage = "PDF export callback requested"
                },
                onHostIOEvent: { event in
                    switch (event.operation, event.status) {
                    case (.imagePick, .completed): hostMessage = useDeviceIO ? "Image URL inserted" : "Image picker callback requested"
                    case (.markdownImport, .completed): hostMessage = useDeviceIO ? "Markdown file imported" : "Markdown import callback requested"
                    case (.markdownExport, .completed): hostMessage = useDeviceIO ? "Markdown file exported" : "Markdown export requested"
                    case (.pdfExport, .completed): hostMessage = "PDF export callback requested"
                    case (_, .failed): hostMessage = event.errorDescription ?? "Editor action failed"
                    case (_, .cancelled): hostMessage = "Editor action cancelled"
                    default: break
                    }
                },
                wikilinkSuggestions: ["Daily Notes", "Project Plan", "Research Index", "Scratch Reference"],
                onTapWikilink: { target in hostMessage = "Wikilink: \(target)" }
            )
            if let hostMessage {
                Text(hostMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("editor-host-message")
            }
            if let lastExport {
                Text("Last export: \(lastExport.utf16.count) characters")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("editor-last-export")
            }
        }
        .padding(16)
        .fileImporter(isPresented: $hostFiles.importing,
                      allowedContentTypes: DemoMarkdownFile.readableContentTypes) { result in
            hostFiles.finishImport(result)
        }
        .fileExporter(isPresented: $hostFiles.exporting,
                      document: hostFiles.exportDocument,
                      contentType: DemoMarkdownFile.markdownType,
                      defaultFilename: "smooth-markdown") { result in
            hostFiles.finishExport(result)
        }
        .alert("Insert image URL", isPresented: $hostFiles.choosingImageURL) {
            TextField("https://example.com/image.png", text: $hostFiles.imageURL)
                .textInputAutocapitalization(.never)
            TextField("Alt text", text: $hostFiles.imageAlt)
            Button("Insert") { hostFiles.finishImageURL(insert: true) }
            Button("Cancel", role: .cancel) { hostFiles.finishImageURL(insert: false) }
        } message: {
            Text("Enter an HTTP(S) image URL. The editor validates it before insertion.")
        }
        .onDisappear { hostFiles.cancelPending() }
    }
}
