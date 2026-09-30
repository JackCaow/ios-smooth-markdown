#if os(iOS)
import Markdown
import SwiftUI
import UIKit
import XCTest
@testable import SmoothMarkdown

private struct EditorPreviewBuilder: MarkdownWidgetBuilder {
    let accepts: (Markup) -> Bool
    let render: (Markup) -> AnyView

    func canBuild(_ node: Markup) -> Bool { accepts(node) }
    func build(_ node: Markup, context: MarkdownRenderContext) -> AnyView { render(node) }
}

private struct EditorPreviewExtensionBuilder: MarkdownWidgetBuilder {
    let accepts: (MarkdownExtensionNode) -> Bool
    let render: (MarkdownExtensionNode) -> AnyView

    func canBuild(_ node: Markup) -> Bool { false }
    func build(_ node: Markup, context: MarkdownRenderContext) -> AnyView { AnyView(Text("unused")) }
    func canBuild(_ node: MarkdownExtensionNode) -> Bool { accepts(node) }
    func build(_ node: MarkdownExtensionNode, context: MarkdownRenderContext) -> AnyView { render(node) }
}

@MainActor
final class EditorPreviewBuilderRegistryTests: XCTestCase {
    private let source = "# Native heading\n\nNative body"

    func testHostBlockAndInlineBuildersReachPreviewAndSplit() {
        let registry = BuilderRegistry()
        var rendered: [String] = []
        registry.register("header", builder: EditorPreviewBuilder(accepts: { $0 is Heading }, render: { _ in
            rendered.append("heading")
            return AnyView(Text("Host heading"))
        }))
        registry.register("text", builder: EditorPreviewBuilder(accepts: {
            ($0 as? Markdown.Text)?.string == "Native body"
        }, render: { _ in
            rendered.append("inline")
            return AnyView(Text("Host inline"))
        }))

        for mode in [MarkdownEditorMode.preview, .split] {
            rendered.removeAll()
            XCTAssertNotNil(renderEditor(mode: mode, registry: registry))
            XCTAssertTrue(rendered.contains("heading"), "Missing block override in \(mode)")
            XCTAssertTrue(rendered.contains("inline"), "Missing inline override in \(mode)")
        }
    }

    func testRejectedBuildersKeepNativePreviewAndSplit() {
        let registry = BuilderRegistry()
        var customRenderCount = 0
        let rejecting = EditorPreviewBuilder(accepts: { _ in false }, render: { _ in
            customRenderCount += 1
            return AnyView(Text("Never render"))
        })
        registry.register("header", builder: rejecting)
        registry.register("text", builder: rejecting)

        for mode in [MarkdownEditorMode.preview, .split] {
            XCTAssertNotNil(renderEditor(mode: mode, registry: registry))
            XCTAssertEqual(customRenderCount, 0, "Rejected builder replaced native rendering in \(mode)")
        }
    }

    func testExtensionBuildersReachPreviewAndSplit() {
        let registry = BuilderRegistry()
        var received: [String] = []
        for type in ["inline_math", "block_math", "footnote_reference", "footnote_definition", "details"] {
            registry.register(type, builder: EditorPreviewExtensionBuilder(accepts: { $0.type == type },
                                                                          render: { node in
                received.append(node.type)
                return AnyView(Text(node.content))
            }))
        }
        let source = "Formula $x$ and [^n]\n\n$$y$$\n\n[^n]: Note\n\n<details>\n<summary>Expand</summary>\nBody\n</details>"
        for mode in [MarkdownEditorMode.preview, .split] {
            received.removeAll()
            XCTAssertNotNil(renderEditor(mode: mode, registry: registry, source: source))
            for type in ["inline_math", "block_math", "footnote_reference", "footnote_definition", "details"] {
                XCTAssertTrue(received.contains(type), "Missing \(type) in \(mode)")
            }
        }
    }

    private func renderEditor(mode: MarkdownEditorMode, registry: BuilderRegistry,
                              source: String? = nil) -> UIImage? {
        let controller = MarkdownEditorController(text: source ?? self.source)
        controller.mode = mode
        let editor = SmoothMarkdownEditor(controller: controller, builderRegistry: registry)
        return ImageRenderer(content: editor.frame(width: 390, height: 700)).uiImage
    }
}
#endif
