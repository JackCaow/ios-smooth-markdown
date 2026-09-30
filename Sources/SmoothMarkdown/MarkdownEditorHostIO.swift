import Foundation
import Markdown
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Image metadata returned by an app's picker or upload flow.
public struct MarkdownEditorImageSelection: Equatable {
    public let url: String
    public let alt: String
    public let title: String?

    public init(url: String, alt: String = "", title: String? = nil) {
        self.url = url
        self.alt = alt
        self.title = title
    }
}

public enum MarkdownEditorHostIOOperation: Equatable { case imagePick, markdownImport, markdownExport, pdfExport }
public enum MarkdownEditorHostIOStatus: Equatable { case started, completed, cancelled, failed }

public enum MarkdownEditorImagePickStatus: Equatable { case picking, inserted, cancelled, failed }

public struct MarkdownEditorImagePickEvent: Equatable {
    public let status: MarkdownEditorImagePickStatus
    public let selection: MarkdownEditorImageSelection?
    public let errorDescription: String?

    public init(status: MarkdownEditorImagePickStatus, selection: MarkdownEditorImageSelection? = nil,
                errorDescription: String? = nil) {
        self.status = status
        self.selection = selection
        self.errorDescription = errorDescription
    }
}

/// The host can display progress, cancellation, and errors without parsing editor state.
public struct MarkdownEditorHostIOEvent: Equatable {
    public let operation: MarkdownEditorHostIOOperation
    public let status: MarkdownEditorHostIOStatus
    public let image: MarkdownEditorImageSelection?
    public let errorDescription: String?

    public init(operation: MarkdownEditorHostIOOperation, status: MarkdownEditorHostIOStatus,
                image: MarkdownEditorImageSelection? = nil, errorDescription: String? = nil) {
        self.operation = operation
        self.status = status
        self.image = image
        self.errorDescription = errorDescription
    }
}

/// Async app-owned I/O. Only a successful picker/import changes the source document.
@MainActor
public final class MarkdownEditorHostIO {
    public typealias ImagePicker = () async throws -> MarkdownEditorImageSelection?
    public typealias MarkdownImporter = () async throws -> String?
    public typealias MarkdownExporter = (String) async throws -> Void
    /// Receives the exact Markdown source and an HTML fragment for host-owned PDF or print export.
    public typealias PDFExporter = (String, String) async throws -> Void

    private let controller: MarkdownEditorController
    private let onPickImage: ImagePicker?
    private let onImportMarkdown: MarkdownImporter?
    private let onExportMarkdown: MarkdownExporter?
    private let onExportPDF: PDFExporter?
    private let onImagePickEvent: ((MarkdownEditorImagePickEvent) -> Void)?
    private let onEvent: ((MarkdownEditorHostIOEvent) -> Void)?

    public init(controller: MarkdownEditorController,
                onPickImage: ImagePicker? = nil,
                onImportMarkdown: MarkdownImporter? = nil,
                onExportMarkdown: MarkdownExporter? = nil,
                onExportPDF: PDFExporter? = nil,
                onImagePickEvent: ((MarkdownEditorImagePickEvent) -> Void)? = nil,
                onEvent: ((MarkdownEditorHostIOEvent) -> Void)? = nil) {
        self.controller = controller
        self.onPickImage = onPickImage
        self.onImportMarkdown = onImportMarkdown
        self.onExportMarkdown = onExportMarkdown
        self.onExportPDF = onExportPDF
        self.onImagePickEvent = onImagePickEvent
        self.onEvent = onEvent
    }

    @discardableResult
    public func pickImage() async -> Bool {
        guard let onPickImage else { return false }
        let source = controller.text
        let range = controller.selection
        emit(.imagePick, .started)
        do {
            guard let image = try await onPickImage(), !Task.isCancelled else {
                emit(.imagePick, .cancelled)
                return false
            }
            guard controller.insertHostedImage(image, at: range, ifTextIs: source) else {
                emit(.imagePick, .failed, error: "Invalid image source or document changed")
                return false
            }
            emit(.imagePick, .completed, image: image)
            return true
        } catch is CancellationError {
            emit(.imagePick, .cancelled)
            return false
        } catch {
            emit(.imagePick, .failed, error: String(describing: error))
            return false
        }
    }

    @discardableResult
    public func importMarkdown() async -> Bool {
        guard let onImportMarkdown else { return false }
        let source = controller.text
        let range = controller.selection
        emit(.markdownImport, .started)
        do {
            guard let markdown = try await onImportMarkdown(), !Task.isCancelled else {
                emit(.markdownImport, .cancelled)
                return false
            }
            guard !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                emit(.markdownImport, .cancelled)
                return false
            }
            guard controller.insertHostedMarkdownBlock(markdown, at: range, ifTextIs: source) else {
                emit(.markdownImport, .failed, error: "Document changed or selection is invalid")
                return false
            }
            emit(.markdownImport, .completed)
            return true
        } catch is CancellationError {
            emit(.markdownImport, .cancelled)
            return false
        } catch {
            emit(.markdownImport, .failed, error: String(describing: error))
            return false
        }
    }

    @discardableResult
    public func exportMarkdown() async -> Bool {
        let source = controller.text
        emit(.markdownExport, .started)
        do {
            if let onExportMarkdown {
                try await onExportMarkdown(source)
            } else {
                #if canImport(UIKit)
                UIPasteboard.general.string = source
                #elseif canImport(AppKit)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(source, forType: .string)
                #endif
            }
            emit(.markdownExport, .completed)
            return true
        } catch is CancellationError {
            emit(.markdownExport, .cancelled)
            return false
        } catch {
            emit(.markdownExport, .failed, error: String(describing: error))
            return false
        }
    }

    @discardableResult
    public func exportPDF() async -> Bool {
        let source = controller.text
        let html = NativeMarkdownHTMLSerializer.format(source)
        emit(.pdfExport, .started)
        do {
            if let onExportPDF {
                try await onExportPDF(source, html)
            } else {
                #if canImport(UIKit)
                UIPasteboard.general.string = html
                #elseif canImport(AppKit)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(html, forType: .string)
                #endif
            }
            emit(.pdfExport, .completed)
            return true
        } catch is CancellationError {
            emit(.pdfExport, .cancelled)
            return false
        } catch {
            emit(.pdfExport, .failed, error: String(describing: error))
            return false
        }
    }

    private func emit(_ operation: MarkdownEditorHostIOOperation, _ status: MarkdownEditorHostIOStatus,
                      image: MarkdownEditorImageSelection? = nil, error: String? = nil) {
        onEvent?(.init(operation: operation, status: status, image: image, errorDescription: error))
        if operation == .imagePick {
            let imageStatus: MarkdownEditorImagePickStatus = switch status {
            case .started: .picking
            case .completed: .inserted
            case .cancelled: .cancelled
            case .failed: .failed
            }
            onImagePickEvent?(.init(status: imageStatus, selection: image, errorDescription: error))
        }
    }
}
