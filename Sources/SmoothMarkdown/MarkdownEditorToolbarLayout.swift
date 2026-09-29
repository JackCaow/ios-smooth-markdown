/// The order in which host toolbar slots and native controls appear.
enum MarkdownEditorToolbarSection: Hashable {
    case leading(Int)
    case history
    case commands
    case trailing(Int)
}

struct MarkdownEditorToolbarLayout {
    let showToolbar: Bool
    let focusMode: Bool
    let leadingCount: Int
    let trailingCount: Int

    var sections: [MarkdownEditorToolbarSection] {
        guard showToolbar && !focusMode else { return [] }
        return (0..<leadingCount).map(MarkdownEditorToolbarSection.leading)
            + [.history, .commands]
            + (0..<trailingCount).map(MarkdownEditorToolbarSection.trailing)
    }
}
