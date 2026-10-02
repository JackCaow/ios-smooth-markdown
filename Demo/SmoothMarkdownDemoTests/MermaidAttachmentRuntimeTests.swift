import SwiftUI
import UIKit
import XCTest
@testable import SmoothMarkdown

@MainActor
final class MermaidAttachmentRuntimeTests: XCTestCase {
    func testMermaidViewportKeepsHeadingAndFollowingParagraphOutsidePaint() async throws {
        for (count, cap, type) in [(1, CGFloat(420), DynamicTypeSize.large),
                                   (10, 420, .large), (10, 420, .accessibility2), (10, 120, .large)] {
            try await verify(nodes: count, cap: cap, type: type)
        }
    }

    private func verify(nodes: Int, cap: CGFloat, type: DynamicTypeSize) async throws {
        let graph = "flowchart TD\n" + (0..<nodes).map { "N\($0)[Node \($0)] --> N\($0 + 1)[Node \($0 + 1)]" }.joined(separator: "\n")
        var style = MarkdownStyleSheet.light()
        style.designTokens.mermaid.maxHeight = cap
        style.designTokens.mermaid.colors = .init(background: 0xFF00FF, text: 0x212121,
            nodeFill: 0xE3F2FD, nodeStroke: 0x1976D2, edge: 0x616161)
        let source = "# Heading before diagram\n\n```mermaid\n" + graph + "\n```\n\nParagraph after diagram."
        let reader = SmoothMarkdownView(markdown: source, styleSheet: style, plugins: .builtIns(), selectable: true)
        let candidate = try XCTUnwrap(reader.wholeDocumentSelection)
        let attachment = try XCTUnwrap(candidate.projection.attachments.first)
        let content = try XCTUnwrap(reader.visualAttachmentView(for: attachment.content))
        let hosting = UIHostingController(rootView: content.environment(\.markdownDesignTokens, style.designTokens)
            .environment(\.dynamicTypeSize, type).environment(\.colorScheme, .light))
        hosting.view.backgroundColor = .clear
        let size = hosting.sizeThatFits(in: CGSize(width: 300, height: CGFloat.greatestFiniteMagnitude))
        let natural = max(MermaidLayout.compute(try XCTUnwrap(MermaidParser.parse(graph))).size.height, 100)
        let expectedHeight = nodes == 1 ? min(natural, cap) + 16 : cap + 16
        XCTAssertEqual(size.height, expectedHeight, accuracy: 1, "The fence must hug a short graph and cap a tall viewport")
        let renderer = ReaderSelectionTextView(document: candidate.selection, styleSheet: style,
            onLinkTap: nil, onTextLongPress: nil, selectable: true, onCharacterTap: nil)
        let text = ReaderDocumentSelectionTextView()
        XCTAssertTrue(text.apply(candidate.projection, availableWidth: 300,
            measuredAttachments: [attachment.id: CGSize(width: 300, height: ceil(size.height))],
            hostedViews: [attachment.id: hosting.view],
            styledText: renderer.attributedContent(traits: MarkdownTypography.traits(for: type)).text))
        let controller = UIViewController()
        controller.view.backgroundColor = .white
        controller.view.addSubview(text)
        controller.addChild(hosting)
        hosting.didMove(toParent: controller)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 300, height: 1000)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKeyAndVisible() }
        controller.view.frame = window.bounds
        text.frame = window.bounds
        for _ in 0..<3 {
            controller.view.layoutIfNeeded(); text.layoutIfNeeded(); hosting.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(50))
        }
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let shot = XCTAttachment(image: image)
        shot.name = "mermaid-boundary-nodes\(nodes)-cap\(Int(cap))-\(type)"
        shot.lifetime = .keepAlways; add(shot)
        let cgImage = try XCTUnwrap(image.cgImage)
        let width = cgImage.width, height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = try XCTUnwrap(CGContext(data: &pixels, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        let rows = (0..<height).filter { y in (0..<width).contains { x in
            let offset = (y * width + x) * 4
            return pixels[offset] > 240 && pixels[offset + 1] < 30 && pixels[offset + 2] > 240
        } }
        let first = try XCTUnwrap(rows.first), last = try XCTUnwrap(rows.last)
        let frame = hosting.view.frame
        print("Mermaid paint nodes=\(nodes) cap=\(cap) type=\(type) natural=\(natural) attachment=\(frame) rows=\(first)...\(last)")
        XCTAssertGreaterThanOrEqual(CGFloat(first), frame.minY - 1, "Paint must not overlap the heading")
        XCTAssertLessThanOrEqual(CGFloat(last), frame.maxY + 1, "Paint must not overlap the following paragraph")
        if nodes > 1 {
            var pending = [hosting.view!]
            var scrolls: [UIScrollView] = []
            while let view = pending.popLast() {
                if let scroll = view as? UIScrollView { scrolls.append(scroll) }
                pending.append(contentsOf: view.subviews)
            }
            let scroll = try XCTUnwrap(scrolls.first { $0.contentSize.height > $0.bounds.height + 1 })
            scroll.setContentOffset(CGPoint(x: 0, y: scroll.contentSize.height - scroll.bounds.height), animated: false)
            scroll.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(50))
            let layout = MermaidLayout.compute(try XCTUnwrap(MermaidParser.parse(graph)))
            let finalNode = try XCTUnwrap(layout.nodes["N\(nodes)"])
            let scale = scroll.contentSize.height / natural
            XCTAssertGreaterThanOrEqual(finalNode.minY * scale, scroll.contentOffset.y - 1)
            XCTAssertLessThanOrEqual(finalNode.maxY * scale, scroll.contentOffset.y + scroll.bounds.height + 1,
                "The last graph node must remain reachable inside the bounded viewport")
            print("Mermaid scroll content=\(scroll.contentSize) viewport=\(scroll.bounds) offset=\(scroll.contentOffset) finalNode=\(finalNode)")
            if cap == 420 && type == .large {
                let bottom = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
                    window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                }
                let lastShot = XCTAttachment(image: bottom)
                lastShot.name = "mermaid-boundary-tall-scrolled-to-final-Node10"
                lastShot.lifetime = .keepAlways; add(lastShot)
            }
        }
    }
}
