import SmoothMarkdown
import SwiftUI

/// Host callbacks and feedback for the editor page in Flutter's example app.
struct DemoEditorView: View {
    @ObservedObject var controller: MarkdownEditorController
    @State private var lastExport: String?
    @State private var hostMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Scratch-style editor preview")
                .font(.title3.weight(.semibold))
            Text("Try the toolbar, slash commands at the start of a paragraph, wikilinks, Find, Focus, and the demo's image, import, and export callbacks.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            SmoothMarkdownEditor(
                controller: controller,
                onPickImage: {
                    MarkdownEditorImageSelection(url: "https://picsum.photos/640/360",
                                                 alt: "Sample image", title: "Demo image")
                },
                onImportMarkdown: {
                    "## Imported markdown\n\nThis came from the host callback."
                },
                onExportMarkdown: { markdown in
                    lastExport = markdown
                },
                onExportPDF: { markdown, _ in
                    lastExport = "PDF export requested for \(markdown.utf16.count) characters"
                    hostMessage = "PDF export callback requested"
                },
                onHostIOEvent: { event in
                    switch (event.operation, event.status) {
                    case (.imagePick, .completed): hostMessage = "Image picker callback requested"
                    case (.markdownImport, .completed): hostMessage = "Markdown import callback requested"
                    case (.markdownExport, .completed): hostMessage = "Markdown export requested"
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
    }
}
