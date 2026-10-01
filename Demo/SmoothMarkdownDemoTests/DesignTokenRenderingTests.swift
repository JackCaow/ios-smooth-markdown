import XCTest
import SwiftUI
import UIKit
@testable import SmoothMarkdown

@MainActor
final class DesignTokenRenderingTests: XCTestCase {
    func testCustomThemeRendersInSwiftUIReader() { render(selectable: false) }
    func testCustomThemeRendersInSelectableReader() { render(selectable: true) }

    private func render(selectable: Bool) {
        var sheet = MarkdownStyleSheet.light()
        sheet.quoteBackground = Color(red: 0, green: 1, blue: 0)
        sheet.blockquoteDecoration = .init(backgroundColor: sheet.quoteBackground, borderColor: .purple, borderWidth: 8)
        sheet.designTokens.typography.paragraph = .init(fontName: "Helvetica", size: 18)
        sheet.designTokens.heading.accentColor = .purple
        sheet.designTokens.code.copyLabel = "复制代码"
        sheet.designTokens.code.syntaxColors = .init(keyword: .purple, string: .red, comment: .gray, number: .orange, literal: .blue)
        let source = "# Custom theme\n\n> Explicit quote background\n\nBody text and **bold** stay readable.\n\n```swift\nlet answer = 42\n```"
        let root = SmoothMarkdownView(markdown: source, useEnhancedComponents: true, styleSheet: sheet,
                                      selectable: selectable, enableCrossBlockSelection: selectable, scrollable: false)
            .padding(16).background(Color.white).environment(\.colorScheme, .light)
        let host = UIHostingController(rootView: root)
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first!
        let previous = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKeyAndVisible() }
        host.view.frame = window.bounds; host.view.setNeedsLayout(); host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = selectable ? "tokens-selectable" : "tokens-swiftui"
        attachment.lifetime = .keepAlways; add(attachment)
        let name = (selectable ? "tokens-selectable" : "tokens-swiftui") + ".png"
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("design-token-review")
        try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try! image.pngData()!.write(to: folder.appendingPathComponent(name))
        let cg = image.cgImage!
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: cg.width * cg.height * 4)
        defer { buffer.deallocate() }
        let context = CGContext(data: buffer, width: cg.width, height: cg.height, bitsPerComponent: 8, bytesPerRow: cg.width * 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        var green = 0
        for index in stride(from: 0, to: cg.width * cg.height * 4, by: 4) {
            if buffer[index + 1] > 200 && buffer[index] < 80 && buffer[index + 2] < 80 { green += 1 }
        }
        XCTAssertGreaterThan(green, 1000, "Enhanced reader ignored explicit quote background")
    }
}
