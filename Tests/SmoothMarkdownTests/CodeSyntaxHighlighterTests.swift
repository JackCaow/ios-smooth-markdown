import XCTest
import SwiftUI
@testable import SmoothMarkdown

/// Core token kinds used in assertions (smooth-rust-core `Kind`).
enum CoreKind {
    static let boolean: UInt8 = 2, comment: UInt8 = 3, constantBuiltin: UInt8 = 6, diffMinus: UInt8 = 8, diffPlus: UInt8 = 9
    static let function: UInt8 = 13, functionDefinition: UInt8 = 14, keyword: UInt8 = 16, keywordControl: UInt8 = 17
    static let keywordDeclaration: UInt8 = 18, number: UInt8 = 23, operatorKind: UInt8 = 24, propertyKey: UInt8 = 27
    static let punctuationDelimiter: UInt8 = 30, string: UInt8 = 37, type: UInt8 = 46, typeBuiltin: UInt8 = 47, parameter: UInt8 = 49
}

func hasToken(_ tokens: [(text: String, kind: UInt8)], _ text: String, _ kind: UInt8) -> Bool {
    tokens.contains { $0.text == text && $0.kind == kind }
}

final class CodeSyntaxHighlighterTests: XCTestCase {
    func testSwiftHighlightingPreservesExactCode() {
        let code = "let name = \"A\\\"B\" // note\nfunc greet(person: String) { print(name, 42) }\n"
        let tokens = CodeSyntaxHighlighter.tokens(code, language: "swift")
        XCTAssertTrue(hasToken(tokens, "let", CoreKind.keywordDeclaration))
        XCTAssertTrue(hasToken(tokens, "// note", CoreKind.comment))
        XCTAssertTrue(hasToken(tokens, "42", CoreKind.number))
        XCTAssertTrue(hasToken(tokens, "greet", CoreKind.functionDefinition))
        XCTAssertTrue(hasToken(tokens, "person", CoreKind.parameter))
        XCTAssertTrue(hasToken(tokens, "String", CoreKind.typeBuiltin))
        XCTAssertEqual(String(CodeSyntaxHighlighter.attributed(code, language: "swift", dark: false, enabled: true).characters), code)
    }

    func testLanguageNamesAndUnsupportedFallback() {
        XCTAssertEqual(CodeSyntaxHighlighter.normalizedLanguage(" JS "), "javascript")
        XCTAssertEqual(CodeSyntaxHighlighter.normalizedLanguage("kt"), "kotlin")
        XCTAssertEqual(CodeSyntaxHighlighter.normalizedLanguage("py"), "python")
        XCTAssertEqual(CodeSyntaxHighlighter.normalizedLanguage("bash"), "shell")
        XCTAssertEqual(CodeSyntaxHighlighter.normalizedLanguage("Dockerfile"), "dockerfile")
        XCTAssertNil(CodeSyntaxHighlighter.normalizedLanguage("unknown"))
        XCTAssertTrue(CodeSyntaxHighlighter.tokens("// raw", language: "unknown").isEmpty)
        XCTAssertEqual(String(CodeSyntaxHighlighter.attributed("plain", language: nil, dark: false, enabled: true).characters), "plain")
    }

    func testPythonAndJSONTokensAndHighlightToggleKeepContent() {
        let python = CodeSyntaxHighlighter.tokens("def greet(): # hi\n    return True", language: "py")
        XCTAssertTrue(hasToken(python, "def", CoreKind.keywordDeclaration))
        XCTAssertTrue(hasToken(python, "# hi", CoreKind.comment))
        XCTAssertTrue(hasToken(python, "True", CoreKind.boolean))
        let json = "{\"count\": 3, \"ok\": true}"
        let jsonTokens = CodeSyntaxHighlighter.tokens(json, language: "json")
        XCTAssertTrue(hasToken(jsonTokens, "3", CoreKind.number))
        XCTAssertTrue(hasToken(jsonTokens, "\"count\"", CoreKind.propertyKey))
        XCTAssertEqual(String(CodeSyntaxHighlighter.attributed(json, language: "json", dark: false, enabled: false).characters), json)
    }

    func testPublicDefaultsAndParsedLanguage() {
        XCTAssertEqual(CodeBlockOptions(), CodeBlockOptions(showCopyButton: true, showLanguageTag: true, enableSyntaxHighlighting: true))
        let block = MarkdownSyntax.parse("```swift\nlet n = 1\n```").child(at: 0) as? CodeBlock
        XCTAssertEqual(block?.language, "swift")
        XCTAssertEqual(block?.code, "let n = 1\n")
        _ = SmoothMarkdownView(markdown: "```swift\nlet n = 1\n```", codeBlockOptions: .init(showCopyButton: false), onCodeCopy: { _, _ in })
    }

    func testLanguageLiteralsUseTheLiteralColor() {
        let colors = MarkdownSyntaxColors(keyword: .red, literal: .yellow)
        for (language, source, literal) in [("javascript", "a = true ?? undefined", "undefined"), ("python", "a = True or None", "None"), ("swift", "let a = false ?? nil", "nil")] {
            let attributed = CodeSyntaxHighlighter.attributed(source, language: language, dark: false, enabled: true, colors: colors)
            XCTAssertEqual(String(attributed.characters), source)
            XCTAssertEqual(attributed[attributed.range(of: literal)!].foregroundColor, .yellow, language)
        }
    }
}

final class CodeLinesAndDiffTests: XCTestCase {
    func testLinesKeepMultilineCommentColors() {
        let colors = MarkdownSyntaxColors(keyword: .red, string: .blue, comment: .green)
        let lines = CodeSyntaxHighlighter.highlightedLines("val a = 1 /* open\n\tstill */ val b\n", language: "kt", dark: false, colors: colors)
        XCTAssertEqual(lines.map { String($0.characters) }, ["val a = 1 /* open", "    still */ val b"])
        XCTAssertEqual(lines[1][lines[1].range(of: "still")!].foregroundColor, .green)
        XCTAssertEqual(lines[1][lines[1].range(of: "val")!].foregroundColor, .red)
    }

    func testDiffRowsCarryNumbersAndWordChanges() {
        let patch = "diff --git a/a.js b/a.js\n--- a/a.js\n+++ b/a.js\n@@ -3,2 +3,2 @@\n const x = 1\n-let total = price * 2\n+let total = price * 3\n"
        let rows = CodeSyntaxHighlighter.diffRows(patch, language: "a.js", dark: false)
        XCTAssertEqual(rows.map(\.kind), [.hunk, .context, .removed, .added])
        XCTAssertEqual(rows.map(\.lineNumber), [nil, 3, 4, 4])
        XCTAssertEqual(String(rows[3].text.characters), "let total = price * 3")
        XCTAssertEqual(rows[3].changed.map { String(rows[3].text[$0].characters) }, "3")
    }
}
