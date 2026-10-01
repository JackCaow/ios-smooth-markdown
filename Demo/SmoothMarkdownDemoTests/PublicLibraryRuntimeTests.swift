import XCTest
import SwiftUI
import UIKit
import Vision
import Combine
@testable import SmoothMarkdown

/// Consumer-facing behavior tested in a hosted SwiftUI tree, including native document selection.
@MainActor
final class PublicLibraryRuntimeTests: XCTestCase {
    func testParserRegistryMutationRefreshesOrdinaryReader() throws { try parserRefresh(selectable: false) }
    func testParserRegistryMutationRefreshesDocumentReader() throws { try parserRefresh(selectable: true) }
    func testBuilderReplacementRefreshesOrdinaryReader() { builderRefresh(selectable: false) }
    func testBuilderReplacementRefreshesDocumentReader() { builderRefresh(selectable: true) }

    func testSharedCallbacksPreserveReferencesInOrdinaryReader() throws { try sharedCallbacks(selectable: false) }
    func testSharedCallbacksPreserveReferencesInDocumentReader() throws { try sharedCallbacks(selectable: true) }

    func testInlineOnlyPluginPreservesOrdinaryReaderParagraph() throws { try inlineOnlyPlugin(selectable: false) }
    func testInlineOnlyPluginPreservesDocumentReaderParagraph() throws { try inlineOnlyPlugin(selectable: true) }

    private func inlineOnlyPlugin(selectable: Bool) throws {
        let registry = ParserPluginRegistry(); try registry.register(RuntimeSharedInlinePlugin())
        let reader = SmoothMarkdownView(markdown: "@runtime",
            renderOptions: .init(scrollable: false),
            selectionOptions: .init(mode: selectable ? .document : .disabled), plugins: registry)
        let host = RuntimeHost(reader); defer { host.close() }
        XCTAssertTrue(try host.recognizedText().contains("RUST INLINE"),
                      "An inline custom range equal to the paragraph/document range must not replace its ancestors")
    }

    func testSharedBuiltinPayloadsRenderCorrectlyInOrdinaryReader() throws { try sharedBuiltins(selectable: false) }
    func testSharedBuiltinPayloadsRenderCorrectlyInDocumentReader() throws { try sharedBuiltins(selectable: true) }

    private func sharedBuiltins(selectable: Bool) throws {
        let capture = RuntimeExtensionCapture()
        let builders = BuilderRegistry(); builders.register("runtime-extensions", builder: RuntimeExtensionBuilder(capture: capture))
        let source = #"\$x$ \[^a]"# + "\n\n> $$\n> x\n> $$\n>\n> [^a:b]: first\n>     second\n"
        let reader = SmoothMarkdownView(markdown: source, renderOptions: .init(scrollable: false),
            selectionOptions: .init(mode: selectable ? .document : .disabled), builders: .init(nodes: builders))
        let host = RuntimeHost(reader); defer { host.close() }
        XCTAssertGreaterThan(host.greenPixels(), 1000, "Typed nested extensions did not reach their builder")
        XCTAssertFalse(capture.nodes.contains { $0.type == "inline_math" || $0.type == "footnote_reference" },
                       "Decoded escaped text was scanned again as Markdown syntax")
        XCTAssertTrue(capture.nodes.contains { $0.type == "block_math" && $0.content == "x" })
        XCTAssertTrue(capture.nodes.contains { $0.type == "footnote_definition" && $0.content == "first\nsecond" && $0.attributes["label"] == "a:b" })
    }

    private func sharedCallbacks(selectable: Bool) throws {
        let plugins = ParserPluginRegistry()
        try plugins.register(AdmonitionPlugin()); try plugins.register(RuntimeSharedInlinePlugin())
        let builders = BuilderRegistry()
        builders.register("resolved-link", builder: RuntimeResolvedLinkBuilder())
        let reader = SmoothMarkdownView(
            markdown: "**@runtime [resolved][id]**\n\n::: note Shared block\nBlock payload\n:::\n\n[id]: https://runtime.invalid/resolved\n",
            renderOptions: .init(scrollable: false),
            selectionOptions: .init(mode: selectable ? .document : .disabled),
            plugins: plugins, builders: .init(nodes: builders))
        let host = RuntimeHost(reader); defer { host.close() }
        XCTAssertGreaterThan(host.greenPixels(), 1000, "Reference defined beyond the plugin did not resolve into the link builder")
        let text = try host.recognizedText()
        XCTAssertTrue(text.contains("RUST INLINE"), "Shared inline callback payload was not rendered")
        XCTAssertTrue(text.contains("BLOCK PAYLOAD"), "Shared block callback payload was not rendered")
    }

    private func parserRefresh(selectable: Bool) throws {
        let registry = ParserPluginRegistry()
        var style = MarkdownStyleSheet.light()
        style.designTokens.plugins.admonition.backgroundColor = Color(red: 0, green: 1, blue: 0)
        let reader = SmoothMarkdownView(markdown: "::: note Live registry\nHello from plugin\n:::",
            renderOptions: .init(useEnhancedComponents: true, scrollable: false),
            selectionOptions: .init(mode: selectable ? .document : .disabled), styleSheet: style, plugins: registry)
        let host = RuntimeHost(reader)
        defer { host.close() }
        XCTAssertLessThan(host.greenPixels(), 100)
        try registry.register(AdmonitionPlugin())
        host.settle()
        XCTAssertGreaterThan(host.greenPixels(), 1000, "Same registry instance did not refresh the rendered view")
        registry.unregisterBlock("admonition")
        host.settle()
        XCTAssertLessThan(host.greenPixels(), 100)
    }

    private func builderRefresh(selectable: Bool) {
        let registry = BuilderRegistry()
        let reader = SmoothMarkdownView(markdown: "Builder node",
            renderOptions: .init(scrollable: false),
            selectionOptions: .init(mode: selectable ? .document : .disabled), builders: .init(nodes: registry))
        let host = RuntimeHost(reader)
        defer { host.close() }
        XCTAssertLessThan(host.greenPixels(), 100)
        registry.register("paragraph", builder: RuntimeColorBuilder(color: Color(red: 0, green: 1, blue: 0)))
        host.settle()
        XCTAssertGreaterThan(host.greenPixels(), 1000)
        registry.register("paragraph", builder: RuntimeColorBuilder(color: .red))
        host.settle()
        XCTAssertLessThan(host.greenPixels(), 100)
        XCTAssertGreaterThan(host.redPixels(), 1000, "Replacing an existing builder did not refresh the hosted view")
    }

    func testReaderInheritsLoaderAndStringsFromEnvironment() async throws {
        try await inheritedImageAndStrings(selectable: false)
    }
    func testDocumentReaderInheritsLoaderAndStringsFromEnvironment() async throws {
        try await inheritedImageAndStrings(selectable: true)
    }

    private func inheritedImageAndStrings(selectable: Bool) async throws {
        let loader = RuntimeImageLoader(data: Self.greenPNG())
        var strings = MarkdownStrings(); strings.copy = "INHERITED COPY"
        let reader = SmoothMarkdownView(markdown: Self.imageAndCode,
            renderOptions: .init(useEnhancedComponents: true, scrollable: false),
            selectionOptions: .init(mode: selectable ? .document : .disabled))
            .environment(\.markdownResources, .init(headers: ["X-Runtime": "inherited"], loader: loader))
            .environment(\.markdownStrings, strings)
        let host = RuntimeHost(reader)
        defer { host.close() }
        await waitForLoad(loader, host: host)
        XCTAssertGreaterThan(host.greenPixels(), 1000, "Inherited custom image loader was not used")
        let requests = await loader.requests
        XCTAssertEqual(requests.first?.headers["X-Runtime"], "inherited")
        XCTAssertTrue(try host.recognizedText().contains("INHERITED COPY"), "Inherited code-copy label did not reach rendered UI")
    }

    func testExplicitReaderOverridesTakePrecedenceOverEnvironment() async throws {
        let inherited = RuntimeImageLoader(data: Self.redPNG())
        let explicit = RuntimeImageLoader(data: Self.greenPNG())
        var inheritedStrings = MarkdownStrings(); inheritedStrings.copy = "INHERITED COPY"
        var explicitStrings = MarkdownStrings(); explicitStrings.copy = "EXPLICIT COPY"
        let reader = SmoothMarkdownView(markdown: Self.imageAndCode,
            renderOptions: .init(useEnhancedComponents: true, scrollable: false),
            resourceOptions: .init(headers: ["X-Runtime": "explicit"], loader: explicit), strings: explicitStrings)
            .environment(\.markdownResources, .init(loader: inherited))
            .environment(\.markdownStrings, inheritedStrings)
        let host = RuntimeHost(reader)
        defer { host.close() }
        await waitForLoad(explicit, host: host)
        XCTAssertGreaterThan(host.greenPixels(), 1000)
        XCTAssertTrue(try host.recognizedText().contains("EXPLICIT COPY"))
        let inheritedRequests = await inherited.requests
        let explicitRequests = await explicit.requests
        XCTAssertTrue(inheritedRequests.isEmpty)
        XCTAssertEqual(explicitRequests.first?.headers["X-Runtime"], "explicit")
    }

    func testStreamingInheritsEnvironmentThroughStructuredEntryPoint() async throws {
        let loader = RuntimeImageLoader(data: Self.greenPNG())
        var strings = MarkdownStrings(); strings.copy = "STREAM COPY"
        let chunks = AsyncStream<String> { continuation in
            continuation.yield(Self.imageAndCode); continuation.finish()
        }
        let stream = StreamMarkdownView(chunks: chunks, renderOptions: .init(useEnhancedComponents: true, scrollable: false),
            streamOptions: .init(throttleMillis: 0))
            .environment(\.markdownResources, .init(loader: loader))
            .environment(\.markdownStrings, strings)
        let host = RuntimeHost(stream)
        defer { host.close() }
        await waitForLoad(loader, host: host)
        XCTAssertGreaterThan(host.greenPixels(), 1000)
        XCTAssertTrue(try host.recognizedText().contains("STREAM COPY"))
    }

    func testEditorInheritsEnvironmentAndLiveParserRegistry() async throws {
        let loader = RuntimeImageLoader(data: Self.greenPNG())
        let registry = ParserPluginRegistry()
        let controller = MarkdownEditorController(text: Self.imageAndCode, plugins: registry)
        controller.mode = .preview
        var strings = MarkdownStrings(); strings.copy = "EDITOR COPY"
        let editor = SmoothMarkdownEditor(controller: controller, enableWikilinks: false, showToolbar: false)
            .environment(\.markdownResources, .init(loader: loader))
            .environment(\.markdownStrings, strings)
        let host = RuntimeHost(editor)
        defer { host.close() }
        await waitForLoad(loader, host: host)
        XCTAssertGreaterThan(host.greenPixels(), 1000)
        XCTAssertTrue(try host.recognizedText().contains("EDITOR COPY"))

        controller.replaceRange(NSRange(location: 0, length: (controller.text as NSString).length), with: "::: note Registry\nEditor plugin body\n:::")
        host.settle()
        var changes = 0
        let subscription = controller.objectWillChange.sink { _ in changes += 1 }
        try registry.register(AdmonitionPlugin())
        host.settle()
        XCTAssertGreaterThan(changes, 0, "Editor did not observe the original registry")
        guard let first = controller.semanticDocument.blocks.first, case .plugin(let id, _) = first.kind else {
            return XCTFail("Editor semantic codec retained a stale registry snapshot")
        }
        XCTAssertEqual(id, "admonition")
        XCTAssertTrue(try host.recognizedText().contains("EDITOR PLUGIN BODY"))
        withExtendedLifetime(subscription) {}
    }

    private func waitForLoad(_ loader: RuntimeImageLoader, host: RuntimeHost) async {
        for _ in 0..<80 {
            if !(await loader.requests).isEmpty, host.greenPixels() > 1000 { break }
            try? await Task.sleep(nanoseconds: 25_000_000)
            host.settle(0.01)
        }
        host.settle(0.15)
    }

    private static let imageAndCode = "![runtime image](https://runtime.invalid/image.png)\n\n```swift\nlet answer = 42\n```"
    private static func greenPNG() -> Data { png(UIColor(red: 0, green: 1, blue: 0, alpha: 1)) }
    private static func redPNG() -> Data { png(.red) }
    private static func png(_ color: UIColor) -> Data {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 120, height: 80), format: format).image { context in
            color.setFill(); context.cgContext.fill(CGRect(x: 0, y: 0, width: 120, height: 80))
        }.pngData()!
    }
}

private actor RuntimeImageLoader: MarkdownResourceLoader {
    let data: Data
    private(set) var requests: [MarkdownResourceRequest] = []
    init(data: Data) { self.data = data }
    func load(_ request: MarkdownResourceRequest) async throws -> Data {
        requests.append(request); return data
    }
}

private struct RuntimeColorBuilder: MarkdownWidgetBuilder {
    let color: Color
    func canBuild(_ node: Markup) -> Bool { node is Paragraph }
    func build(_ node: Markup, context: MarkdownRenderContext) -> AnyView {
        AnyView(Rectangle().fill(color).frame(width: 180, height: 80))
    }
}

@MainActor
private final class RuntimeHost {
    let window: UIWindow
    let controller: UIHostingController<AnyView>
    private let previous: UIWindow?
    init<Content: View>(_ content: Content) {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first!
        previous = scene.windows.first { $0.isKeyWindow }
        window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        controller = UIHostingController(rootView: AnyView(content.padding(16).background(Color.white).environment(\.colorScheme, .light)))
        window.rootViewController = controller; window.makeKeyAndVisible()
        controller.view.frame = window.bounds
        settle()
    }
    func close() { window.isHidden = true; previous?.makeKeyAndVisible() }
    func settle(_ duration: TimeInterval = 0.2) {
        controller.view.setNeedsLayout(); controller.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(duration))
    }
    func image() -> UIImage {
        UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
    }
    func greenPixels() -> Int { pixels { red, green, blue in green > 200 && red < 80 && blue < 80 } }
    func redPixels() -> Int { pixels { red, green, blue in red > 200 && green < 80 && blue < 80 } }
    private func pixels(_ match: (UInt8, UInt8, UInt8) -> Bool) -> Int {
        let image = image().cgImage!
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: image.width * image.height * 4)
        defer { buffer.deallocate() }
        let context = CGContext(data: buffer, width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        var count = 0
        for index in stride(from: 0, to: image.width * image.height * 4, by: 4) {
            if match(buffer[index], buffer[index + 1], buffer[index + 2]) { count += 1 }
        }
        return count
    }
    func recognizedText() throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate; request.recognitionLanguages = ["en-US"]
        try VNImageRequestHandler(cgImage: image().cgImage!, options: [:]).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n").uppercased()
    }
}

private struct RuntimeSharedInlinePlugin: InlineParserPlugin {
    let id = "runtime-shared-inline"; let name = "Runtime shared inline"; let triggerCharacter: Character = "@"
    func canParse(_ text: String, at index: String.Index) -> Bool { text[index...].hasPrefix("@runtime") }
    func parse(_ text: String, at index: String.Index) -> InlinePluginMatch? {
        canParse(text, at: index) ? .init(consumed: 8, text: "RUST INLINE") : nil
    }
}
private struct RuntimeResolvedLinkBuilder: MarkdownWidgetBuilder {
    func canBuild(_ node: Markup) -> Bool { (node as? Markdown.Link)?.destination == "https://runtime.invalid/resolved" }
    func build(_ node: Markup, context: MarkdownRenderContext) -> AnyView {
        AnyView(Text("RESOLVED LINK").padding(12).background(Color(red: 0, green: 1, blue: 0)))
    }
}

private final class RuntimeExtensionCapture { var nodes: [MarkdownExtensionNode] = [] }
private struct RuntimeExtensionBuilder: MarkdownWidgetBuilder {
    let capture: RuntimeExtensionCapture
    func canBuild(_ node: Markup) -> Bool { false }
    func build(_ node: Markup, context: MarkdownRenderContext) -> AnyView { AnyView(EmptyView()) }
    func canBuild(_ node: MarkdownExtensionNode) -> Bool {
        ["inline_math", "block_math", "footnote_reference", "footnote_definition"].contains(node.type)
    }
    func build(_ node: MarkdownExtensionNode, context: MarkdownRenderContext) -> AnyView {
        capture.nodes.append(node)
        return AnyView(Text(node.content).padding(16).frame(width: 180).background(Color(red: 0, green: 1, blue: 0)))
    }
}
