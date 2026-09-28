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
        XCTAssertNotNil(renderer.nsImage)
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
        XCTAssertNotNil(renderer.nsImage)
        XCTAssertTrue(received.isEmpty)
    }
}
