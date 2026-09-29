import Markdown
import SwiftUI
import XCTest
@testable import SmoothMarkdown

#if os(iOS)
import UIKit
#endif

@MainActor
final class HTMLDecorationTests: XCTestCase {
    func testFlutterLightDarkPresetsAndLegacyHighlightColor() {
        let light = MarkdownStyleSheet.light()
        let lightMark = light.resolvedHTMLStyle(.init(), underline: false, highlight: true)
        XCTAssertEqual(lightMark.backgroundColor, rgb(0xFFF176))
        XCTAssertEqual(lightMark.textColor, rgb(0x212121))
        XCTAssertEqual(light.resolvedHTMLStyle(.init(), underline: true, highlight: false).underline, true)

        let dark = MarkdownStyleSheet.dark()
        let darkMark = dark.resolvedHTMLStyle(.init(), underline: false, highlight: true)
        XCTAssertEqual(darkMark.backgroundColor, rgb(0x4D4400))
        XCTAssertNil(darkMark.textColor)
        XCTAssertEqual(dark.textColor, rgb(0xB3B3B3))

        var custom = MarkdownStyleSheet.light()
        custom.highlightColor = .green
        XCTAssertEqual(custom.resolvedHTMLStyle(.init(), underline: false, highlight: true).backgroundColor,
                       .green)
        custom.highlightStyle = .init(textColor: .purple, backgroundColor: .orange)
        let explicit = custom.resolvedHTMLStyle(.init(), underline: false, highlight: true)
        XCTAssertEqual(explicit.textColor, .purple)
        XCTAssertEqual(explicit.backgroundColor, .orange)

        custom.underlineStyle = .init(fontSize: 19, textColor: .blue, underline: false)
        let underline = custom.resolvedHTMLStyle(.init(), underline: true, highlight: false)
        XCTAssertEqual(underline.underline, false)
        XCTAssertEqual(underline.fontSize, 19)
        XCTAssertEqual(underline.textColor, .blue)
    }

    func testSelectableReaderKeepsMarkUnderlineInsAndNeighborText() {
        let source = "A <mark>M</mark> <u>U</u> <ins>I</ins> <mark><u>B</u></mark> Z"
        let node = MarkdownSyntax.parse(source, enableHTML: true).child(at: 0)!
        guard let document = ReaderSelectionDocument.compose([node], enableHTML: true, plugins: nil) else {
            return XCTFail("Supported HTML decorations should keep native reader selection")
        }
        XCTAssertEqual(document.copiedText, "A M U I B Z")
        let runs = document.lines.flatMap(\.runs)
        XCTAssertTrue(runs.first(where: { $0.text == "M" })?.highlighted == true)
        XCTAssertTrue(runs.first(where: { $0.text == "U" })?.htmlUnderline == true)
        XCTAssertTrue(runs.first(where: { $0.text == "I" })?.htmlUnderline == true)
        XCTAssertTrue(runs.first(where: { $0.text == "B" })?.highlighted == true)
        XCTAssertTrue(runs.first(where: { $0.text == "B" })?.htmlUnderline == true)
        XCTAssertTrue(runs.filter { $0.text == "A " || $0.text == " Z" }
            .allSatisfy { !$0.highlighted && !$0.htmlUnderline })

        let unsupported = MarkdownSyntax.parse("A <font color=red>red</font>", enableHTML: true)
            .child(at: 0)!
        XCTAssertNil(ReaderSelectionDocument.compose([unsupported], enableHTML: true, plugins: nil),
                     "Other HTML styles must retain their SwiftUI renderer")
    }

    func testStreamingWithholdsHalfOpenDecorationTags() {
        var buffer = StreamMarkdownBuffer(startMillis: 0, enableHTML: true)
        XCTAssertNil(buffer.append("A <mark", nowMillis: 50))
        XCTAssertEqual(buffer.visibleText, "A ")
        XCTAssertNil(buffer.append(">B</mark> <ins", nowMillis: 100))
        XCTAssertEqual(buffer.visibleText, "A <mark>B</mark> ")
        XCTAssertNil(buffer.append(">C</ins>", nowMillis: 150))
        XCTAssertEqual(buffer.visibleText, "A <mark>B</mark> <ins>C</ins>")
    }

    #if os(iOS)
    func testNativeReaderAppliesPresetMarkAndUnderlineAttributes() {
        let node = MarkdownSyntax.parse("A <mark>M</mark> <u>U</u> <ins>I</ins>", enableHTML: true)
            .child(at: 0)!
        let document = ReaderSelectionDocument.compose([node], enableHTML: true, plugins: nil)!
        let text = ReaderSelectionTextView(document: document, styleSheet: .light(),
                                           onLinkTap: nil, onTextLongPress: nil,
                                           selectable: true, onCharacterTap: nil)
            .attributedContent(traits: MarkdownTypography.traits(for: .large)).text
        func attributes(_ token: String) -> [NSAttributedString.Key: Any] {
            let location = (text.string as NSString).range(of: token).location
            XCTAssertNotEqual(location, NSNotFound)
            return text.attributes(at: location, effectiveRange: nil)
        }
        XCTAssertEqual(attributes("M")[.backgroundColor] as? UIColor, UIColor(rgb(0xFFF176)))
        XCTAssertEqual(attributes("M")[.foregroundColor] as? UIColor, UIColor(rgb(0x212121)))
        XCTAssertEqual(attributes("U")[.underlineStyle] as? Int, NSUnderlineStyle.single.rawValue)
        XCTAssertEqual(attributes("I")[.underlineStyle] as? Int, NSUnderlineStyle.single.rawValue)
        XCTAssertNil(attributes("A")[.backgroundColor])
    }
    #endif

    private func rgb(_ value: UInt32) -> Color {
        Color(.sRGB, red: Double((value >> 16) & 0xFF) / 255,
              green: Double((value >> 8) & 0xFF) / 255,
              blue: Double(value & 0xFF) / 255, opacity: 1)
    }
}
