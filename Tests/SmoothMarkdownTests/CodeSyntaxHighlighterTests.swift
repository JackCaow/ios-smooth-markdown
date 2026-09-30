import XCTest
@testable import SmoothMarkdown

final class CodeSyntaxHighlighterTests: XCTestCase {
    func testSwiftHighlightingPreservesExactCode() {
        let code = "let name = \"A\\\"B\" // note\nprint(name, 42)\n"
        let tokens = CodeSyntaxHighlighter.tokenize(code, language: "swift")
        XCTAssertEqual(tokens.map(\.text).joined(), code)
        XCTAssertTrue(tokens.contains(.init(text: "let", kind: .keyword)))
        XCTAssertTrue(tokens.contains(.init(text: "\"A\\\"B\"", kind: .string)))
        XCTAssertTrue(tokens.contains(.init(text: "// note", kind: .comment)))
        XCTAssertTrue(tokens.contains(.init(text: "42", kind: .number)))
    }

    func testLanguageAliasesAndUnsupportedFallback() {
        XCTAssertEqual(CodeSyntaxHighlighter.normalizedLanguage(" JS "), "javascript")
        XCTAssertEqual(CodeSyntaxHighlighter.normalizedLanguage("kt"), "kotlin")
        XCTAssertEqual(CodeSyntaxHighlighter.normalizedLanguage("py"), "python")
        XCTAssertEqual(CodeSyntaxHighlighter.normalizedLanguage("bash"), "shell")
        XCTAssertEqual(CodeSyntaxHighlighter.tokenize("// raw", language: "unknown"), [.init(text: "// raw", kind: .plain)])
        XCTAssertEqual(CodeSyntaxHighlighter.tokenize("plain", language: nil), [.init(text: "plain", kind: .plain)])
    }

    func testPythonAndJSONTokensAndHighlightToggleKeepContent() {
        let python = CodeSyntaxHighlighter.tokenize("def greet(): # hi\n    return True", language: "py")
        XCTAssertTrue(python.contains(.init(text: "def", kind: .keyword)))
        XCTAssertTrue(python.contains(.init(text: "# hi", kind: .comment)))
        XCTAssertTrue(python.contains(.init(text: "True", kind: .literal)))
        let json = "{\"count\": 3, \"ok\": true}"
        let jsonTokens = CodeSyntaxHighlighter.tokenize(json, language: "json")
        XCTAssertEqual(jsonTokens.map(\.text).joined(), json)
        XCTAssertTrue(jsonTokens.contains(.init(text: "3", kind: .number)))
        XCTAssertEqual(String(CodeSyntaxHighlighter.attributed(json, language: "json", dark: false, enabled: false).characters), json)
    }

    func testPublicDefaultsAndParsedLanguage() {
        XCTAssertEqual(CodeBlockOptions(), CodeBlockOptions(showCopyButton: true, showLanguageTag: true, enableSyntaxHighlighting: true))
        let block = MarkdownSyntax.parse("```swift\nlet n = 1\n```").child(at: 0) as? CodeBlock
        XCTAssertEqual(block?.language, "swift")
        XCTAssertEqual(block?.code, "let n = 1\n")
        _ = SmoothMarkdownView(markdown: "```swift\nlet n = 1\n```", codeBlockOptions: .init(showCopyButton: false), onCodeCopy: { _, _ in })
    }
}
