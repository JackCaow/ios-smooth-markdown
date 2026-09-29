import XCTest
@testable import SmoothMarkdown

final class MermaidThemeTests: XCTestCase {
    func testFenceThemeReachesNativeDiagramView() throws {
        let plugin = MermaidPlugin()
        for (fence, expected) in [
            ("```mermaid theme=dark", MermaidTheme.dark),
            ("~~~mermaid title=flow theme = FoReSt", MermaidTheme.forest),
            ("```mermaid theme=neutral", MermaidTheme.neutral),
            ("```mermaid theme=light", MermaidTheme.light),
            ("```mermaid theme=unsupported", MermaidTheme.light),
        ] {
            let match = try XCTUnwrap(plugin.parse([fence, "flowchart LR", "A --> B", String(fence.prefix(3))], at: 0))
            XCTAssertEqual(plugin.theme(for: match), expected, fence)
            let diagram = try XCTUnwrap(MermaidParser.parse(match.content))
            XCTAssertEqual(MermaidDiagramView(diagram: diagram, theme: plugin.theme(for: match)).theme,
                           expected, fence)
        }
        let automatic = try XCTUnwrap(plugin.parse(["```mermaid", "flowchart LR", "A --> B", "```"], at: 0))
        XCTAssertNil(plugin.theme(for: automatic))
        XCTAssertNil(MermaidTheme.fromFenceInfo("mermaid theme dark"))
    }

    func testPaletteMatchesFlutterMermaidStyles() {
        XCTAssertEqual(MermaidTheme.light.palette.background, 0xFFFFFF)
        XCTAssertEqual(MermaidTheme.light.palette.nodeFill, 0xE3F2FD)
        XCTAssertEqual(MermaidTheme.dark.palette.background, 0x1E1E1E)
        XCTAssertEqual(MermaidTheme.dark.palette.text, 0xE0E0E0)
        XCTAssertEqual(MermaidTheme.forest.palette.nodeFill, 0xC8E6C9)
        XCTAssertEqual(MermaidTheme.forest.palette.edge, 0x4CAF50)
        XCTAssertEqual(MermaidTheme.neutral.palette.nodeFill, 0xEEEEEE)
        XCTAssertEqual(MermaidTheme.neutral.palette.nodeStroke, 0x757575)
    }
}
