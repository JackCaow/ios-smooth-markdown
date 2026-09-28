import CryptoKit
import Foundation
import XCTest
@testable import SmoothMarkdown

/// Runs the same 40 Mermaid sources shown by the Flutter and iOS demo galleries.
final class MermaidGalleryParityTests: XCTestCase {
    private struct Manifest: Decodable {
        struct Example: Decodable {
            let index: Int
            let category: String
            let title: String
            let file: String
            let sha256: String
        }

        let examples: [Example]
    }

    func testAllFlutterGalleryExamplesParseAndHaveUsableNativeLayouts() throws {
        // The gallery owns the synced fixtures. Read them from the checkout so this test
        // catches broken gallery assets as well as parser/layout regressions.
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // SmoothMarkdownTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // repository
            .appendingPathComponent("Demo/SmoothMarkdownDemo/Examples/Mermaid")
        let manifestData = try Data(contentsOf: directory.appendingPathComponent("gallery.json"))
        let examples = try JSONDecoder().decode(Manifest.self, from: manifestData).examples
        XCTAssertEqual(examples.count, 40)

        var failures: [String] = []
        for (offset, example) in examples.enumerated() {
            let name = String(format: "%02d %@ %@", example.index, example.category, example.title)
            guard example.index == offset + 1 else {
                failures.append("\(name): out of order")
                continue
            }
            guard let data = try? Data(contentsOf: directory.appendingPathComponent(example.file)),
                  let source = String(data: data, encoding: .utf8) else {
                failures.append("\(name): source fixture missing")
                continue
            }
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard digest == example.sha256 else {
                failures.append("\(name): fixture checksum mismatch")
                continue
            }
            guard let diagram = MermaidParser.parse(source) else {
                failures.append("\(name): parser returned nil (gallery shows source fallback)")
                continue
            }
            let layout = MermaidLayout.compute(diagram)
            guard layout.size.width.isFinite, layout.size.height.isFinite,
                  layout.size.width > 0, layout.size.height > 0 else {
                failures.append("\(name): empty or nonfinite layout")
                continue
            }
            if diagram.kind == .flowchart || diagram.kind == .sequence || diagram.kind == .stateDiagram {
                if diagram.nodes.isEmpty { failures.append("\(name): no nodes") }
                if layout.nodes.count != diagram.nodes.count {
                    failures.append("\(name): laid out \(layout.nodes.count)/\(diagram.nodes.count) nodes")
                }
                if layout.edges.count != diagram.edges.count {
                    failures.append("\(name): laid out \(layout.edges.count)/\(diagram.edges.count) edges")
                }
            }
            if example.index == 6 {
                if diagram.node("E")?.label != "标签" || diagram.node("E")?.shape != .asymmetric {
                    failures.append("\(name): Mermaid asymmetric label/shape was dropped")
                }
            }
        }
        XCTAssertTrue(failures.isEmpty, failures.joined(separator: "\n"))
    }
}
