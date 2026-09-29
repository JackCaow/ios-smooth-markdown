import XCTest
@testable import SmoothMarkdown

final class EditorHostIOTests: XCTestCase {
    private enum FixtureError: Error { case failed }

    @MainActor
    func testImageSelectionUsesSelectedAltAndOneUndoStep() async {
        let controller = MarkdownEditorController(text: "Selected")
        controller.setSelection(NSRange(location: 0, length: 8))
        var events: [MarkdownEditorImagePickEvent] = []
        let io = MarkdownEditorHostIO(controller: controller,
                                      onPickImage: { .init(url: "assets/a(b).png", title: "Picked") },
                                      onImagePickEvent: { events.append($0) })
        let inserted = await io.pickImage()
        XCTAssertTrue(inserted)
        XCTAssertEqual(controller.text, "![Selected](assets/a%28b%29.png \"Picked\")")
        XCTAssertEqual(controller.selection.location, (controller.text as NSString).length)
        XCTAssertEqual(events.map(\.status), [.picking, .inserted])
        XCTAssertEqual(events.last?.selection?.url, "assets/a(b).png")
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, "Selected")
        XCTAssertFalse(controller.canUndo)
        XCTAssertTrue(controller.redo())
        XCTAssertEqual(controller.text, "![Selected](assets/a%28b%29.png \"Picked\")")
    }

    @MainActor
    func testImportAtCapturedSelectionAndExportExactSource() async {
        let controller = MarkdownEditorController(text: "Intro")
        controller.setSelection(NSRange(location: 5, length: 0))
        var exported = ""
        let io = MarkdownEditorHostIO(controller: controller,
                                      onImportMarkdown: { " # Imported\n\nBody " },
                                      onExportMarkdown: { exported = $0 })
        let imported = await io.importMarkdown()
        XCTAssertTrue(imported)
        XCTAssertEqual(controller.text, "Intro\n\n# Imported\n\nBody")
        XCTAssertEqual(controller.selection.location, (controller.text as NSString).length)
        let exportedSuccessfully = await io.exportMarkdown()
        XCTAssertTrue(exportedSuccessfully)
        XCTAssertEqual(exported, controller.text)
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, "Intro")
        XCTAssertFalse(controller.canUndo)
    }

    @MainActor
    func testCancellationErrorsAndInvalidImageNeverChangeSource() async {
        let controller = MarkdownEditorController(text: "Original")
        let originalSelection = controller.selection
        var events: [MarkdownEditorHostIOEvent] = []
        let cancelled = MarkdownEditorHostIO(controller: controller,
                                             onPickImage: { nil }, onImportMarkdown: { nil },
                                             onEvent: { events.append($0) })
        let cancelledImage = await cancelled.pickImage()
        let cancelledImport = await cancelled.importMarkdown()
        XCTAssertFalse(cancelledImage)
        XCTAssertFalse(cancelledImport)
        let emptyImport = MarkdownEditorHostIO(controller: controller,
                                               onImportMarkdown: { "   " },
                                               onEvent: { events.append($0) })
        let ignoredEmptyImport = await emptyImport.importMarkdown()
        XCTAssertFalse(ignoredEmptyImport)
        let failed = MarkdownEditorHostIO(controller: controller,
                                          onPickImage: { throw FixtureError.failed },
                                          onImportMarkdown: { throw FixtureError.failed },
                                          onExportMarkdown: { _ in throw FixtureError.failed },
                                          onEvent: { events.append($0) })
        let failedImage = await failed.pickImage()
        let failedImport = await failed.importMarkdown()
        let failedExport = await failed.exportMarkdown()
        XCTAssertFalse(failedImage)
        XCTAssertFalse(failedImport)
        XCTAssertFalse(failedExport)
        let unsafe = MarkdownEditorHostIO(controller: controller,
                                          onPickImage: { .init(url: "javascript:alert(1)") },
                                          onEvent: { events.append($0) })
        let unsafeImage = await unsafe.pickImage()
        XCTAssertFalse(unsafeImage)
        XCTAssertEqual(controller.text, "Original")
        XCTAssertEqual(controller.selection, originalSelection)
        XCTAssertFalse(controller.canUndo)
        XCTAssertEqual(events.filter { $0.status == .cancelled }.count, 3)
        XCTAssertEqual(events.filter { $0.status == .failed }.count, 4)
    }

    @MainActor
    func testStaleAsyncResultAndInvalidUTF16RangeAreRejected() {
        let controller = MarkdownEditorController(text: "😀 text")
        XCTAssertFalse(controller.insertHostedMarkdownBlock("# New", at: NSRange(location: 1, length: 0), ifTextIs: "😀 text"))
        XCTAssertFalse(controller.insertHostedImage(.init(url: "assets/a.png"), at: NSRange(location: 1, length: 0), ifTextIs: "😀 text"))
        controller.insertMarkdown(" later")
        XCTAssertFalse(controller.insertHostedMarkdownBlock("# New", at: NSRange(location: 0, length: 0), ifTextIs: "😀 text"))
        XCTAssertEqual(controller.text, "😀 text later")
    }

    @MainActor
    func testPDFExportProvidesSourceAndHTMLWithoutEditingDocument() async {
        let source = "# Hello\n\nA **bold** word."
        let controller = MarkdownEditorController(text: source)
        var exportedMarkdown = ""
        var exportedHTML = ""
        var events: [MarkdownEditorHostIOEvent] = []
        let io = MarkdownEditorHostIO(controller: controller,
                                      onExportPDF: { markdown, html in
                                          exportedMarkdown = markdown
                                          exportedHTML = html
                                      },
                                      onEvent: { events.append($0) })

        let exported = await io.exportPDF()
        XCTAssertTrue(exported)
        XCTAssertEqual(exportedMarkdown, source)
        XCTAssertTrue(exportedHTML.contains("<h1>Hello</h1>"))
        XCTAssertTrue(exportedHTML.contains("<strong>bold</strong>"))
        XCTAssertEqual(controller.text, source)
        XCTAssertFalse(controller.canUndo)
        XCTAssertEqual(events.map(\.operation), [.pdfExport, .pdfExport])
        XCTAssertEqual(events.map(\.status), [.started, .completed])
    }

    @MainActor
    func testFailedPDFCallbackReportsFailureAndPreservesSource() async {
        let controller = MarkdownEditorController(text: "Original")
        var events: [MarkdownEditorHostIOEvent] = []
        let io = MarkdownEditorHostIO(controller: controller,
                                      onExportPDF: { _, _ in throw FixtureError.failed },
                                      onEvent: { events.append($0) })
        let exported = await io.exportPDF()
        XCTAssertFalse(exported)
        XCTAssertEqual(controller.text, "Original")
        XCTAssertEqual(events.map(\.status), [.started, .failed])
        XCTAssertNotNil(events.last?.errorDescription)
    }

    @MainActor
    func testDelayedImagePickerUsesCapturedSelectionAndRejectsStaleDocument() async {
        let controller = MarkdownEditorController(text: "Alpha Beta")
        controller.setSelection(NSRange(location: 0, length: 5))
        let pickerStarted = expectation(description: "picker started")
        var reply: CheckedContinuation<MarkdownEditorImageSelection?, Never>?
        var events: [MarkdownEditorHostIOStatus] = []
        let io = MarkdownEditorHostIO(controller: controller,
            onPickImage: {
                await withCheckedContinuation { continuation in
                    reply = continuation
                    pickerStarted.fulfill()
                }
            }, onEvent: { events.append($0.status) })
        let operation = Task { await io.pickImage() }
        await fulfillment(of: [pickerStarted], timeout: 5)
        controller.setSelection(NSRange(location: 10, length: 0))
        reply?.resume(returning: .init(url: "assets/delayed.png"))
        let inserted = await operation.value
        XCTAssertTrue(inserted)
        XCTAssertEqual(controller.text, "![Alpha](assets/delayed.png)\n\n Beta")
        XCTAssertEqual(events, [.started, .completed])
        XCTAssertTrue(controller.undo())
        XCTAssertEqual(controller.text, "Alpha Beta")
        XCTAssertFalse(controller.canUndo)

        controller.setSelection(NSRange(location: 0, length: 5))
        let staleStarted = expectation(description: "second picker started")
        reply = nil
        let staleIO = MarkdownEditorHostIO(controller: controller,
            onPickImage: {
                await withCheckedContinuation { continuation in
                    reply = continuation
                    staleStarted.fulfill()
                }
            }, onEvent: { events.append($0.status) })
        let staleOperation = Task { await staleIO.pickImage() }
        await fulfillment(of: [staleStarted], timeout: 5)
        controller.replaceRange(NSRange(location: 0, length: 0), with: "New ")
        let changed = controller.text
        let changedSelection = controller.selection
        reply?.resume(returning: .init(url: "assets/stale.png"))
        let staleInserted = await staleOperation.value
        XCTAssertFalse(staleInserted)
        XCTAssertEqual(controller.text, changed)
        XCTAssertEqual(controller.selection, changedSelection)
        XCTAssertEqual(Array(events.suffix(2)), [.started, .failed])
    }

    @MainActor
    func testDelayedImportCancellationKeepsSelectionAndHistory() async {
        let controller = MarkdownEditorController(text: "Before 😀 After")
        let selected = NSRange(location: 7, length: 2)
        controller.setSelection(selected)
        let started = expectation(description: "import started")
        var reply: CheckedContinuation<String?, Never>?
        var events: [MarkdownEditorHostIOStatus] = []
        let io = MarkdownEditorHostIO(controller: controller,
            onImportMarkdown: {
                await withCheckedContinuation { continuation in
                    reply = continuation
                    started.fulfill()
                }
            }, onEvent: { events.append($0.status) })
        let operation = Task { await io.importMarkdown() }
        await fulfillment(of: [started], timeout: 5)
        reply?.resume(returning: nil)
        let imported = await operation.value
        XCTAssertFalse(imported)
        XCTAssertEqual(controller.text, "Before 😀 After")
        XCTAssertEqual(controller.selection, selected)
        XCTAssertFalse(controller.canUndo)
        XCTAssertEqual(events, [.started, .cancelled])
    }
}
