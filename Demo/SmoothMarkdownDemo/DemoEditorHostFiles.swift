import Combine
import Foundation
import SmoothMarkdown
import SwiftUI
import UniformTypeIdentifiers

/// A UTF-8 Markdown file offered to the system document exporter.
struct DemoMarkdownFile: FileDocument {
    static let markdownType = UTType(filenameExtension: "md", conformingTo: .plainText) ?? .plainText
    static var readableContentTypes: [UTType] { [markdownType, .plainText] }
    static var writableContentTypes: [UTType] { [markdownType] }

    let markdown: String

    init(markdown: String) { self.markdown = markdown }

    init(configuration: ReadConfiguration) throws {
        guard let bytes = configuration.file.regularFileContents,
              let markdown = String(data: bytes, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        self.markdown = markdown
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(markdown.utf8))
    }
}

/// Bridges SwiftUI's document sheets and URL alert to the editor's public
/// async callbacks. Dismissal resumes the waiting operation as cancellation.
@MainActor
final class DemoEditorHostFiles: ObservableObject {
    @Published var importing = false
    @Published var exporting = false
    @Published var choosingImageURL = false
    @Published var imageURL = ""
    @Published var imageAlt = ""
    @Published var exportDocument: DemoMarkdownFile?

    private var importWaiter: CheckedContinuation<String?, Error>?
    private var exportWaiter: CheckedContinuation<Void, Error>?
    private var imageWaiter: CheckedContinuation<MarkdownEditorImageSelection?, Never>?

    enum RequestError: LocalizedError {
        case busy
        case invalidUTF8

        var errorDescription: String? {
            switch self {
            case .busy: "Another document operation is in progress"
            case .invalidUTF8: "The selected file is not UTF-8 Markdown"
            }
        }
    }

    func importMarkdown() async throws -> String? {
        guard importWaiter == nil else { throw RequestError.busy }
        return try await withCheckedThrowingContinuation { waiter in
            importWaiter = waiter
            importing = true
        }
    }

    func finishImport(_ result: Result<URL, Error>) {
        guard let waiter = importWaiter else { return }
        importWaiter = nil
        importing = false
        switch result {
        case let .success(url):
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let bytes = try Data(contentsOf: url)
                guard let markdown = String(data: bytes, encoding: .utf8) else {
                    throw RequestError.invalidUTF8
                }
                waiter.resume(returning: markdown)
            } catch {
                waiter.resume(throwing: error)
            }
        case let .failure(error):
            if Self.isUserCancellation(error) { waiter.resume(returning: nil) }
            else { waiter.resume(throwing: error) }
        }
    }

    func exportMarkdown(_ markdown: String) async throws {
        guard exportWaiter == nil else { throw RequestError.busy }
        try await withCheckedThrowingContinuation { (waiter: CheckedContinuation<Void, Error>) in
            exportWaiter = waiter
            exportDocument = DemoMarkdownFile(markdown: markdown)
            exporting = true
        }
    }

    func finishExport(_ result: Result<URL, Error>) {
        guard let waiter = exportWaiter else { return }
        exportWaiter = nil
        exporting = false
        exportDocument = nil
        switch result {
        case .success: waiter.resume()
        case let .failure(error):
            waiter.resume(throwing: Self.isUserCancellation(error) ? CancellationError() : error)
        }
    }

    func pickImageURL() async -> MarkdownEditorImageSelection? {
        guard imageWaiter == nil else { return nil }
        return await withCheckedContinuation { waiter in
            imageWaiter = waiter
            imageURL = ""
            imageAlt = ""
            choosingImageURL = true
        }
    }

    func finishImageURL(insert: Bool) {
        guard let waiter = imageWaiter else { return }
        imageWaiter = nil
        choosingImageURL = false
        waiter.resume(returning: insert ? .init(url: imageURL, alt: imageAlt) : nil)
    }

    func cancelPending() {
        importing = false
        exporting = false
        choosingImageURL = false
        exportDocument = nil
        if let waiter = importWaiter { importWaiter = nil; waiter.resume(returning: nil) }
        if let waiter = exportWaiter { exportWaiter = nil; waiter.resume(throwing: CancellationError()) }
        if let waiter = imageWaiter { imageWaiter = nil; waiter.resume(returning: nil) }
    }

    private static func isUserCancellation(_ error: Error) -> Bool {
        error is CancellationError ||
            ((error as NSError).domain == NSCocoaErrorDomain &&
             (error as NSError).code == NSUserCancelledError)
    }
}
