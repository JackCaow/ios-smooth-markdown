#if os(iOS)
import SwiftUI

/// Host actions for a top-level block explicitly selected by `customBlockMatcher`.
/// The source snapshot is checked again before replace or delete, so an old
/// editor cannot overwrite newer document changes.
@available(iOS 17.0, *)
@MainActor
public struct MarkdownEditorCustomBlockContext {
    public let blockID: String
    public let blockKind: MarkdownSemanticBlock
    public let markdown: String
    public let plainText: String
    public let isEditing: Bool
    public let edit: () -> Void
    public let replaceMarkdown: (String) -> Bool
    public let finishEditing: () -> Void
    public let delete: () -> Bool

    init(blockID: String, blockKind: MarkdownSemanticBlock, markdown: String, plainText: String,
         isEditing: Bool, edit: @escaping () -> Void,
         replaceMarkdown: @escaping (String) -> Bool, finishEditing: @escaping () -> Void,
         delete: @escaping () -> Bool) {
        self.blockID = blockID
        self.blockKind = blockKind
        self.markdown = markdown
        self.plainText = plainText
        self.isEditing = isEditing
        self.edit = edit
        self.replaceMarkdown = replaceMarkdown
        self.finishEditing = finishEditing
        self.delete = delete
    }
}

/// Return nil to keep the built-in Blocks row. The host wraps its view in AnyView.
@available(iOS 17.0, *)
public typealias MarkdownEditorCustomBlockBuilder = @MainActor (MarkdownEditorCustomBlockContext) -> AnyView?

#endif
