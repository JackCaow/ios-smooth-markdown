import XCTest
import SwiftUI
@testable import SmoothMarkdown

final class MainstreamCodeHighlightTests: XCTestCase {
    func testTwentyMainstreamLanguagesAndAdditionalFences() {
        let cases = [
            ("javascript", "function run() { return true; }"), ("typescript", "interface Box { value: number }"),
            ("python", "def run():\n    return True"), ("java", "class Box { void run() {} }"),
            ("kotlin", "fun run() = true"), ("swift", "func run() -> Bool { true }"),
            ("c", "int main() { return 0; }"), ("cpp", "class Box { public: void run(); }"),
            ("csharp", "class Box { public void Run() {} }"), ("go", "func main() { return }"),
            ("rust", "fn main() { let value = 1; }"), ("php", "<?php function run() { return true; }"),
            ("ruby", "def run\nend"), ("dart", "class App { void main() {} }"),
            ("scala", "object Main { def run() = 1 }"), ("sql", "SELECT name FROM users -- ok"),
            ("shell", "if true; then echo ok; fi"), ("lua", "function run() return true end"),
            ("r", "function(x) { return(x) } # ok"), ("objectivec", "@interface Box : NSObject @end"),
            ("json", "{\"name\": 1}"), ("yaml", "name: true"), ("html", "<!-- comment -->"),
            ("css", "@media screen { color: red; }"), ("markdown", "# TODO"), ("diff", "+added\n-removed")
        ]
        for (language, code) in cases {
            XCTAssertFalse(CodeSyntaxHighlighter.tokens(code, language: language).isEmpty, language)
            XCTAssertEqual(String(CodeSyntaxHighlighter.attributed(code, language: language, dark: false, enabled: true).characters), code, language)
        }
    }
    func testAliasesAndFenceMetadata() {
        let cases = ["tsx": "tsx", "node": "javascript", "h": "c", "c++": "cpp", "c#": "csharp", "golang": "go", "rs": "rust", "phtml": "php", "rb": "ruby", "sc": "scala", "postgresql": "sql", "objective-c": "objectivec", "zsh": "shell", "jsonc": "json", "yml": "yaml", "svg": "xml", "scss": "scss", "patch": "diff", "build.gradle.kts": "kotlin"]
        for (alias, language) in cases { XCTAssertEqual(CodeSyntaxHighlighter.normalizedLanguage(alias + "\tlineNumbers"), language) }
        XCTAssertEqual(CodeSyntaxHighlighter.normalizedLanguage("typescript\nmeta"), "typescript")
        XCTAssertEqual(CodeSyntaxHighlighter.normalizedLanguage("json,meta"), "json")
    }
    func testTokenKindsDiffHeadersAndUnicodeStayExact() {
        let code = "🙂 const 名称 = run(\"值\"); Box"
        let tokens = CodeSyntaxHighlighter.tokens(code, language: "typescript")
        XCTAssertEqual(String(CodeSyntaxHighlighter.attributed(code, language: "typescript", dark: false, enabled: true).characters), code)
        XCTAssertTrue(hasToken(tokens, "run", CoreKind.function))
        XCTAssertTrue(hasToken(tokens, "Box", CoreKind.type))
        XCTAssertTrue(hasToken(tokens, "=", CoreKind.operatorKind))
        XCTAssertTrue(hasToken(tokens, ";", CoreKind.punctuationDelimiter))
        XCTAssertTrue(hasToken(CodeSyntaxHighlighter.tokens("{\"count\": 2}", language: "json"), "\"count\"", CoreKind.propertyKey))
        let diff = "--- a/file\n+++ b/file\n-old\n+new\n@@ range @@"
        let diffTokens = CodeSyntaxHighlighter.tokens(diff, language: "diff")
        XCTAssertEqual(diffTokens.filter { $0.kind == CoreKind.diffMinus }.map(\.text), ["-old"])
        XCTAssertEqual(diffTokens.filter { $0.kind == CoreKind.diffPlus }.map(\.text), ["+new"])
    }
    func testOptionalColorsAndMermaidLocalization() {
        var colors = MarkdownSyntaxColors.light()
        XCTAssertNil(colors.type); XCTAssertNil(colors.function); XCTAssertNil(colors.property)
        colors.type = .yellow; colors.function = .green; colors.property = .orange
        colors.operator = .gray; colors.punctuation = .gray; colors.diffAdd = .green; colors.diffRemove = .red
        let code = "const answer = run(\"ok\"); Box"
        let highlighted = CodeSyntaxHighlighter.attributed(code, language: "typescript", dark: false, enabled: true, colors: colors)
        XCTAssertEqual(String(highlighted.characters), code)
        XCTAssertTrue(highlighted.runs.contains { $0.foregroundColor == .green })
        XCTAssertTrue(highlighted.runs.contains { $0.foregroundColor == .yellow })
        var strings = MarkdownStrings(); strings.overrides["Unsupported Mermaid diagram"] = "暂不支持该图表"
        XCTAssertEqual(strings["Unsupported Mermaid diagram"], "暂不支持该图表")
    }
}
