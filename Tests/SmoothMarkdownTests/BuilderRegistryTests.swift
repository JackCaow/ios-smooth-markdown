import Markdown
import SwiftUI
import XCTest
@testable import SmoothMarkdown

private struct TestBuilder: MarkdownWidgetBuilder {
    var identity = ""
    let accepts: (Markup) -> Bool
    let render: (Markup, MarkdownRenderContext) -> AnyView

    func canBuild(_ node: Markup) -> Bool { accepts(node) }
    func build(_ node: Markup, context: MarkdownRenderContext) -> AnyView { render(node, context) }
}

private struct TestPluginBuilder: MarkdownWidgetBuilder {
    let type: String
    let render: (MarkdownPluginNode, MarkdownRenderContext) -> AnyView

    func canBuild(_ node: Markup) -> Bool { false }
    func build(_ node: Markup, context: MarkdownRenderContext) -> AnyView { AnyView(Text("unused")) }
    func canBuild(_ node: MarkdownPluginNode) -> Bool { node.type == type }
    func build(_ node: MarkdownPluginNode, context: MarkdownRenderContext) -> AnyView {
        render(node, context)
    }
}

@MainActor
final class BuilderRegistryTests: XCTestCase {
    func testExactOverrideFallbackAndUnregisteredDefault() {
        let nodes = Array(MarkdownSyntax.parse("# Heading\n\nParagraph\n\n---").children)
        let registry = BuilderRegistry()
        let fallback = TestBuilder(identity: "fallback", accepts: { $0 is Heading }, render: { _, _ in AnyView(Text("fallback")) })
        let rejecting = TestBuilder(identity: "rejecting", accepts: { _ in false }, render: { _, _ in AnyView(Text("never")) })
        let exact = TestBuilder(identity: "exact", accepts: { $0 is Heading }, render: { _, _ in AnyView(Text("exact")) })
        registry.register("other", builder: fallback)
        registry.register("header", builder: rejecting)
        XCTAssertEqual((registry.findBuilder(nodes[0]) as? TestBuilder)?.identity, "fallback",
                       "Rejected exact match must fall through to a capable builder")
        XCTAssertNil(registry.findBuilder(nodes[1]), "Unregistered paragraphs retain native rendering")
        registry.register("header", builder: exact)
        XCTAssertEqual((registry.findBuilder(nodes[0]) as? TestBuilder)?.identity, "exact")
        XCTAssertEqual(BuilderRegistry.nodeType(for: nodes[0]), "header")
        XCTAssertEqual(BuilderRegistry.nodeType(for: nodes[1]), "paragraph")
        XCTAssertEqual(BuilderRegistry.nodeType(for: nodes[2]), "horizontal_rule")
        XCTAssertTrue(registry.getBuilder("header")?.canBuild(nodes[0]) == true)
        registry.unregister("header")
        XCTAssertFalse(registry.hasBuilder("header"))
        registry.clear()
        XCTAssertNil(registry.findBuilder(nodes[0]))
    }

    func testCustomNodeSplitsNativeSelectionGroupWithoutReplacingNeighbors() {
        let nodes = Array(MarkdownSyntax.parse("First\n\n# Override\n\nLast").children)
        let groups = ReaderSelectionGroup.group(nodes, enableHTML: false, plugins: nil,
                                                hasCustomBuilder: { $0 is Heading })
        XCTAssertEqual(groups.count, 3)
        guard case .individual = groups[0], case let .individual(middle) = groups[1],
              case .individual = groups[2] else {
            return XCTFail("Only the overridden heading should be isolated")
        }
        XCTAssertTrue(middle is Heading)

        let mathGroups = ReaderMathSelectionGroup.group(
            [.markup(nodes[0]), .markup(nodes[1]), .displayMath("x")],
            enableHTML: false, plugins: nil, hasCustomBuilder: { $0 is Heading })
        XCTAssertEqual(mathGroups.count, 3)
        guard case .legacy(.individual) = mathGroups[1] else {
            return XCTFail("Math-aware selection must isolate the overridden heading")
        }
    }

    func testNestedCustomBuilderRendersChildrenThroughSameRegistryAndKeepsCodeHook() {
        let registry = BuilderRegistry()
        var rendered: [String] = []
        registry.register("blockquote", builder: TestBuilder(accepts: { $0 is BlockQuote }, render: { node, context in
            rendered.append("quote")
            return AnyView(VStack(alignment: .leading) {
                ForEach(Array(node.children.enumerated()), id: \.offset) { _, child in
                    context.renderBlock(child)
                }
            })
        }))
        registry.register("paragraph", builder: TestBuilder(accepts: { $0 is Paragraph }, render: { _, _ in
            rendered.append("paragraph")
            return AnyView(Text("custom paragraph"))
        }))
        let view = SmoothMarkdownView(markdown: "> Nested\n\n```swift\nprint(1)\n```",
                                      codeBuilder: { _, _ in
                                          rendered.append("code")
                                          return AnyView(Text("custom code"))
                                      }, builderRegistry: registry, selectable: true)
        let renderer = ImageRenderer(content: view.frame(width: 400, height: 300))
        #if canImport(UIKit)
        XCTAssertNotNil(renderer.uiImage)
        #else
        XCTAssertNotNil(renderer.nsImage)
        #endif
        XCTAssertTrue(rendered.contains("quote"))
        XCTAssertTrue(rendered.contains("paragraph"))
        XCTAssertTrue(rendered.contains("code"))
    }

    func testNativeQuoteWithCustomChildLeavesSelectionComposition() {
        let registry = BuilderRegistry()
        var renderedParagraph = false
        registry.register("paragraph", builder: TestBuilder(accepts: { $0 is Paragraph }, render: { _, _ in
            renderedParagraph = true
            return AnyView(Text("custom nested paragraph"))
        }))
        let source = "> Nested"
        let quote = MarkdownSyntax.parse(source).child(at: 0)!
        let view = SmoothMarkdownView(markdown: source, builderRegistry: registry, selectable: true)
        XCTAssertTrue(view.containsCustomBlockBuilder(quote))
        let groups = ReaderSelectionGroup.group([quote], enableHTML: false, plugins: nil,
                                                hasCustomBuilder: view.containsCustomBlockBuilder)
        guard case .individual = groups.first else { return XCTFail("Quote must leave native selection composition") }
        let renderer = ImageRenderer(content: view.frame(width: 400, height: 150))
        #if canImport(UIKit)
        XCTAssertNotNil(renderer.uiImage)
        #else
        XCTAssertNotNil(renderer.nsImage)
        #endif
        XCTAssertTrue(renderedParagraph)
    }

    func testListItemCanBeOverriddenInsideNativeList() {
        let registry = BuilderRegistry()
        var renderedItem = false
        registry.register("list_item", builder: TestBuilder(accepts: { $0 is Markdown.ListItem }, render: { _, _ in
            renderedItem = true
            return AnyView(Text("custom list item"))
        }))
        let source = "- Item"
        let list = MarkdownSyntax.parse(source).child(at: 0)!
        let view = SmoothMarkdownView(markdown: source, builderRegistry: registry, selectable: true)
        XCTAssertTrue(view.containsCustomBlockBuilder(list))
        let renderer = ImageRenderer(content: view.frame(width: 400, height: 150))
        #if canImport(UIKit)
        XCTAssertNotNil(renderer.uiImage)
        #else
        XCTAssertNotNil(renderer.nsImage)
        #endif
        XCTAssertTrue(renderedItem)
    }

    func testInlineCustomRunsPreserveNestedStyleAndUnaffectedLink() {
        let paragraph = MarkdownSyntax.parse("start **deep** [link](https://example.com) end").child(at: 0)!
        let runs = InlineContent.runs(in: paragraph, enableHTML: false,
                                      hasCustomBuilder: { ($0 as? Markdown.Text)?.string == "deep" })
        XCTAssertEqual(runs.filter { if case .custom = $0 { return true }; return false }.count, 1)
        guard let custom = runs.first(where: { if case .custom = $0 { return true }; return false }),
              case let .custom(node, style) = custom else { return XCTFail("Expected nested text override") }
        XCTAssertEqual((node as? Markdown.Text)?.string, "deep")
        XCTAssertTrue(style.bold)
        XCTAssertTrue(runs.contains { run in
            if case let .text("link", style, _, _) = run { return style.link?.absoluteString == "https://example.com" }
            return false
        })

        let types = Array(paragraph.children).map(BuilderRegistry.nodeType(for:))
        XCTAssertTrue(types.contains("bold"))
        XCTAssertTrue(types.contains("link"))
        let italic = MarkdownSyntax.parse("*italic*").child(at: 0)!.child(at: 0)!
        XCTAssertEqual(BuilderRegistry.nodeType(for: italic), "italic")

        let registry = BuilderRegistry()
        registry.register("text", builder: TestBuilder(accepts: { ($0 as? Markdown.Text)?.string == "Hello " },
                                                       render: { _, _ in AnyView(Text("custom")) }))
        let pluginParagraph = MarkdownSyntax.parse("Hello @alice").child(at: 0)!
        let pluginView = SmoothMarkdownView(markdown: "Hello @alice", plugins: .builtIns(),
                                            builderRegistry: registry, selectable: true)
        XCTAssertTrue(pluginView.containsCustomBlockBuilder(pluginParagraph),
                      "A builder matching only a post-plugin text piece must leave TextKit composition")
        let pluginRuns = InlineContent.runs(in: pluginParagraph, enableHTML: false,
                                            plugins: .builtIns(),
                                            hasCustomBuilder: { registry.findBuilder($0) != nil })
        XCTAssertTrue(pluginRuns.contains { if case .custom = $0 { return true }; return false })
        XCTAssertTrue(pluginRuns.contains { if case .plugin = $0 { return true }; return false })
    }

    func testStrongAndLinkOverridesRenderNestedTextWithoutChangingCodeOrImageHooks() {
        let registry = BuilderRegistry()
        var received: [String] = []
        registry.register("bold", builder: TestBuilder(accepts: { $0 is Strong }, render: { node, context in
            received.append("bold")
            return AnyView(context.renderInline!(node).fontWeight(.bold))
        }))
        registry.register("text", builder: TestBuilder(accepts: { ($0 as? Markdown.Text)?.string == "inner" },
                                                      render: { _, _ in
            received.append("inner")
            return AnyView(Text("replacement"))
        }))
        registry.register("link", builder: TestBuilder(accepts: { $0 is Markdown.Link }, render: { _, _ in
            received.append("link")
            return AnyView(Text("custom link"))
        }))
        let markdown = "Before **inner** [site](https://example.com)\n\n![Asset](asset.png)\n\n```swift\nprint(1)\n```"
        let view = SmoothMarkdownView(markdown: markdown,
                                      imageBuilder: { _, _, _ in
                                          received.append("image")
                                          return AnyView(Text("host image"))
                                      }, codeBuilder: { _, _ in
                                          received.append("code")
                                          return AnyView(Text("host code"))
                                      }, builderRegistry: registry, selectable: true)
        let first = MarkdownSyntax.parse("Before **inner** [site](https://example.com)").child(at: 0)!
        XCTAssertTrue(view.containsCustomBlockBuilder(first), "Custom inline nodes must leave TextKit composition")
        let renderer = ImageRenderer(content: view.frame(width: 420, height: 440))
        #if canImport(UIKit)
        XCTAssertNotNil(renderer.uiImage)
        #else
        XCTAssertNotNil(renderer.nsImage)
        #endif
        for expected in ["bold", "inner", "link", "image", "code"] {
            XCTAssertTrue(received.contains(expected), "Missing \(expected) render hook")
        }
    }

    func testPluginResultsUseSameRegistryAndCanRenderNestedMarkdown() {
        let registry = BuilderRegistry()
        var received: [String] = []
        registry.register("text", builder: TestBuilder(accepts: { $0 is Markdown.Text }, render: { _, _ in
            received.append("ordinary text")
            return AnyView(Text("ordinary override"))
        }))
        registry.register("mention", builder: TestPluginBuilder(type: "mention", render: { node, _ in
            received.append("\(node.type):\(node.attributes["username"] ?? "")")
            return AnyView(Text("custom mention"))
        }))
        registry.register("admonition", builder: TestPluginBuilder(type: "admonition", render: { node, context in
            received.append("\(node.type):\(node.attributes["type"] ?? "")")
            return AnyView(VStack {
                Text("custom admonition")
                context.renderMarkdown?(node.content)
            })
        }))
        registry.register("bold", builder: TestBuilder(accepts: { $0 is Strong }, render: { _, _ in
            received.append("nested bold")
            return AnyView(Text("nested override"))
        }))
        let view = SmoothMarkdownView(markdown: "Hello @alice\n\n::: note\n**inside**\n::: ",
                                      plugins: .builtIns(), builderRegistry: registry)
        let renderer = ImageRenderer(content: view.frame(width: 400, height: 320))
        #if canImport(UIKit)
        XCTAssertNotNil(renderer.uiImage)
        #else
        XCTAssertNotNil(renderer.nsImage)
        #endif
        XCTAssertTrue(received.contains("mention:alice"))
        XCTAssertTrue(received.contains("ordinary text"), "The text override must not consume plugin syntax")
        XCTAssertTrue(received.contains("admonition:note"))
        XCTAssertTrue(received.contains("nested bold"))
    }

    func testHTMLStyleTokensStayOnNativeStatefulPath() {
        let registry = BuilderRegistry()
        var intercepted = false
        registry.register("InlineHTML", builder: TestBuilder(accepts: { $0 is InlineHTML }, render: { _, _ in
            intercepted = true
            return AnyView(Text("wrong"))
        }))
        let view = SmoothMarkdownView(markdown: "before <u>under</u> after", enableHTML: true,
                                      builderRegistry: registry)
        let renderer = ImageRenderer(content: view.frame(width: 400, height: 120))
        #if canImport(UIKit)
        XCTAssertNotNil(renderer.uiImage)
        #else
        XCTAssertNotNil(renderer.nsImage)
        #endif
        XCTAssertFalse(intercepted)
    }

    func testTableCellOverrideReachesNativeTableLayout() {
        let registry = BuilderRegistry()
        var rendered = false
        registry.register("Cell", builder: TestBuilder(accepts: { $0 is Markdown.Table.Cell }, render: { _, _ in
            rendered = true
            return AnyView(Text("custom cell"))
        }))
        let view = SmoothMarkdownView(markdown: "| A | B |\n| - | - |\n| C | D |",
                                      builderRegistry: registry, selectable: true)
        let renderer = ImageRenderer(content: view.frame(width: 400, height: 180))
        #if canImport(UIKit)
        XCTAssertNotNil(renderer.uiImage)
        #else
        XCTAssertNotNil(renderer.nsImage)
        #endif
        XCTAssertTrue(rendered)
    }
}
