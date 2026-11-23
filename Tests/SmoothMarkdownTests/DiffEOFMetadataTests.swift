import XCTest
import SwiftUI
import SmoothMarkdown

final class DiffEOFMetadataTests: XCTestCase {
    func testEOFNotesPreserveReplacementRangesAndCommentColors() throws {
        let patch = #"""
        @@ -1,2 +1,2 @@
         /* start
        -🐢 old value */
        \ No newline at end of file
        +🐢 new value */
        \ No newline at end of file
        """#
        let colors = MarkdownSyntaxColors(comment: .green)
        let rows = CodeSyntaxHighlighter.diffRows(patch, language: "swift", dark: false, colors: colors)
        XCTAssertEqual(rows.map(\.kind), [.hunk, .context, .removed, .note, .added, .note])
        XCTAssertEqual(rows.map(\.lineNumber), [nil, 1, 2, nil, 2, nil])

        let edits = rows.filter { $0.kind == .removed || $0.kind == .added }
        for (row, expected) in zip(edits, ["old", "new"]) {
            let word = try XCTUnwrap(row.text.range(of: expected))
            XCTAssertEqual(row.text[word].foregroundColor, .green)
            XCTAssertEqual(row.changed.map { String(row.text[$0].characters) }, expected)
        }
        for note in rows.filter({ $0.kind == .note }) {
            XCTAssertEqual(String(note.text.characters), "No newline at end of file")
            XCTAssertNil(note.changed)
        }
    }
}
