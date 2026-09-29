import Foundation

/// TextKit reserves one invisible character for each visual image block.
/// These helpers keep selection offsets in UTF-16 and omit only image anchors
/// when the system Copy action requests plain text.
enum ReaderImageSelectionProjection {
    static let anchorCharacter: unichar = 0x2588

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
