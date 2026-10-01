import SmoothMarkdownCore
let parser = MarkdownCoreParser()
precondition(parser.parse("# Hello").children.first?.kind == .heading(1))
precondition(parser.renderHTML("**bold**") == "<p><strong>bold</strong></p>\n")
precondition(parser.renderHTML("- [x] Done").contains("checked"))
print("Public core consumer passed without SwiftUI or UIKit")
