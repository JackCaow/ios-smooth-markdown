import Foundation

/// Undoable semantic transactions over the initial source-preserving block model.
public final class MarkdownDocumentEditor {
    public private(set) var document: MarkdownDocument
    private var undoStack: [MarkdownDocument] = []
    private var redoStack: [MarkdownDocument] = []

    public init(document: MarkdownDocument) { self.document = document }
    public convenience init(markdown: String, codec: MarkdownDocumentCodec = .init()) {
        self.init(document: codec.parse(markdown))
    }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    @discardableResult
    public func replaceBlockContent(id: String, with content: String) -> Bool {
        guard let block = document.blockById(id), let replacement = block.replacingContent(content) else { return false }
        return apply(document.replacingBlock(replacement))
    }

    @discardableResult
    public func moveTopLevelBlock(id: String, to index: Int) -> Bool {
        apply(document.movingBlock(id, to: index))
    }

    @discardableResult
    public func undo() -> Bool {
        guard let previous = undoStack.popLast() else { return false }
        redoStack.append(document)
        document = previous
        return true
    }

    @discardableResult
    public func redo() -> Bool {
        guard let next = redoStack.popLast() else { return false }
        undoStack.append(document)
        document = next
        return true
    }

    private func apply(_ next: MarkdownDocument) -> Bool {
        guard next != document else { return false }
        undoStack.append(document)
        redoStack.removeAll()
        document = next
        return true
    }
}
