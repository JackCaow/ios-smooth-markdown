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
        registry.register("ListItem", builder: TestBuilder(accepts: { $0 is Markdown.ListItem }, render: { _, _ in
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
}
