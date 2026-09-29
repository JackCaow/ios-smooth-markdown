import Foundation

/// TextKit reserves one invisible character for each visual image block.
/// These helpers keep selection offsets in UTF-16 and omit only image anchors
/// when the system Copy action requests plain text.
enum ReaderImageSelectionProjection {
    static let anchorCharacter: unichar = 0x2588

    /// A style or width update may replace attributedText while the user is
    /// dragging a selection. Keep its UTF-16 range only if the source text is
    /// unchanged; offsets into new Markdown must never be reused.
    static func retainedRange(_ selection: NSRange, oldText: String, newText: String) -> NSRange? {
        guard oldText == newText else { return nil }
        let length = (newText as NSString).length
        guard selection.location != NSNotFound, selection.location >= 0,
              selection.location <= length, selection.length >= 0,
              selection.length <= length - selection.location else { return nil }
        return selection
    }

    static func crossesImage(from anchor: Int, to focus: Int, imageAnchors: [Int]) -> Bool {
        imageAnchors.contains { min(anchor, focus) <= $0 && max(anchor, focus) > $0 }
    }

    static func copiedText(_ selected: String, selectionStart: Int, imageAnchors: [Int]) -> String? {
        let copy = NSMutableString(string: selected)
        let end = selectionStart + copy.length
        for anchor in imageAnchors.sorted(by: >) where selectionStart <= anchor && anchor < end {
            let relative = anchor - selectionStart
            guard relative < copy.length, copy.character(at: relative) == anchorCharacter else { return nil }
            if relative > 0, relative + 1 < copy.length,
               copy.character(at: relative - 1) == 10,
               copy.character(at: relative + 1) == 10 {
                copy.replaceCharacters(in: NSRange(location: relative - 1, length: 3), with: "\n")
            } else {
                copy.deleteCharacters(in: NSRange(location: relative, length: 1))
            }
        }
        return copy as String
    }
}
