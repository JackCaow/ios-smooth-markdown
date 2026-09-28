import SmoothMarkdown
import XCTest

final class SafeHTMLTests: XCTestCase {
    func testLexesBoundedTagsAndKeepsFirstAttribute() {
        let tag = SafeHTML.lexTag("<IMG src='https://x/a.png' ALT=first alt=second loading>")
        XCTAssertEqual(tag?.name, "img")
        XCTAssertEqual(tag?.attributes["src"], "https://x/a.png")
        XCTAssertEqual(tag?.attributes["alt"], "first")
        XCTAssertEqual(tag?.attributes["loading"], "")
        XCTAssertNil(SafeHTML.lexTag("<img src='unterminated>"))
        XCTAssertNil(SafeHTML.lexTag("<a " + String(repeating: "x", count: 513) + ">"))
    }

    func testRejectsObfuscatedSchemesAndDistinguishesImages() {
        XCTAssertTrue(SafeHTML.isSafeLink("#section"))
        XCTAssertTrue(SafeHTML.isSafeLink("//cdn.example.com/a"))
        XCTAssertFalse(SafeHTML.isSafeLink("java\tscript:alert(1)"))
        XCTAssertFalse(SafeHTML.isSafeLink("data:text/plain,x"))
        XCTAssertTrue(SafeHTML.isSafeImageSource("assets/icon.png"))
        XCTAssertFalse(SafeHTML.isSafeImageSource("//cdn.example.com/a.png"))
        XCTAssertFalse(SafeHTML.isSafeImageSource("mailto:a@b.com"))
    }

    func testAcceptsOnlyBoundedStyles() {
        XCTAssertEqual(SafeHTML.color("#f00"), 0xFFFF0000)
        XCTAssertEqual(SafeHTML.color("red"), 0xFFFF0000)
        XCTAssertNil(SafeHTML.color("#ff000080"))
        XCTAssertEqual(SafeHTML.fontSize("18pt"), 24)
        XCTAssertNil(SafeHTML.fontSize("200px"))
        XCTAssertEqual(SafeHTML.legacyFontSize("3"), 16)
        XCTAssertEqual(SafeHTML.cssDeclarations("color:red; position:fixed; color:blue")["color"], "red")
    }

    func testWithholdsOnlyPartialTagsOutsideCode() {
        XCTAssertEqual(SafeHTML.safeRenderPrefix("lead <font colo"), "lead ")
        XCTAssertEqual(SafeHTML.safeRenderPrefix("Use `List<T` here. <font colo"), "Use `List<T` here. ")
        XCTAssertEqual(SafeHTML.safeRenderPrefix("Use `List<T` here."), "Use `List<T` here.")
        XCTAssertEqual(SafeHTML.safeRenderPrefix("```dart\nList<T items;\n```"), "```dart\nList<T items;\n```")
        XCTAssertEqual(SafeHTML.safeRenderPrefix("count 5 <3"), "count 5 <3")
    }

    func testParsesNestedWhitelistedBlocksAndTrailingSibling() {
        let block = SafeHTML.parseBlock("<div align='center'>outer <div>inner</div> tail</div> after")
        XCTAssertEqual(block, .container(name: "div", content: "outer <div>inner</div> tail", alignment: "center", trailing: " after"))
        XCTAssertEqual(SafeHTML.parseBlock("<hr>"), .rule)
        XCTAssertNil(SafeHTML.parseBlock("<script>alert(1)</script>"))
    }
}
