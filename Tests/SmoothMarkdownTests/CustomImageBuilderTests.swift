import SwiftUI
import XCTest
@testable import SmoothMarkdown

@MainActor
final class CustomImageBuilderTests: XCTestCase {
    func testSafeMarkdownAndHTMLImagesReachCustomBuilder() {
        var received: [String] = []
        let view = SmoothMarkdownView(
            markdown: "![One](asset.png \"A\")\n\n<img src='https://example.com/two.svg' alt='Two'>",
            imageBuilder: { source, alt, title in
                received.append("\(source)|\(alt ?? "")|\(title ?? "")")
                return AnyView(Text("Custom \(alt ?? "")"))
            },
            enableHTML: true
        )
        let renderer = ImageRenderer(content: view.frame(width: 400, height: 300))
        #if canImport(UIKit)
        XCTAssertNotNil(renderer.uiImage)
        #else
        XCTAssertNotNil(renderer.nsImage)
        #endif
        XCTAssertTrue(received.contains("asset.png|One|A"))
        XCTAssertTrue(received.contains("https://example.com/two.svg|Two|"))
    }

    func testUnsafeImageDoesNotReachCustomBuilder() {
        var received: [String] = []
        let view = SmoothMarkdownView(markdown: "![Unsafe](javascript:alert(1))", imageBuilder: { source, _, _ in
            received.append(source)
            return AnyView(Text("Should not render"))
        })
        let renderer = ImageRenderer(content: view.frame(width: 400, height: 200))
        #if canImport(UIKit)
        XCTAssertNotNil(renderer.uiImage)
        #else
        XCTAssertNotNil(renderer.nsImage)
        #endif
        XCTAssertTrue(received.isEmpty)
    }

    func testFencedCodeCanUseHostBuilder() {
        var received: [String] = []
        let view = SmoothMarkdownView(markdown: "```swift\nprint(1)\n```", codeBuilder: { code, language in
            received.append("\(language ?? "")|\(code)")
            return AnyView(Text("Custom code"))
        })
        let renderer = ImageRenderer(content: view.frame(width: 400, height: 200))
        #if canImport(UIKit)
        XCTAssertNotNil(renderer.uiImage)
        #else
        XCTAssertNotNil(renderer.nsImage)
        #endif
        XCTAssertFalse(received.isEmpty)
        XCTAssertTrue(received.allSatisfy { $0.hasPrefix("swift|print(1)") })
    }
}
