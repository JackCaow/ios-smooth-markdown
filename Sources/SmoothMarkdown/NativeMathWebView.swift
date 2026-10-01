import SwiftUI
import WebKit

#if os(iOS)
import UIKit
typealias NativeMathPlatformImage = UIImage
#elseif os(macOS)
import AppKit
typealias NativeMathPlatformImage = NSImage
#endif

/// Uses the system WebKit MathML engine for font metrics, stretchy glyphs, and math baselines.
/// A single offline WebView renders snapshots sequentially; SwiftUI keeps the local renderer as
/// a visible fallback while a formula is being measured or if WebKit fails.
struct NativeMathWebView: View {
    let latex: String
    let size: CGFloat
    let display: Bool
    let color: Color?
    var fontFamily: String = "serif"
    @Environment(\.colorScheme) private var colorScheme
    @State private var image: NativeMathPlatformImage?

    private var colorHex: String { NativeMathColorHex.resolve(color ?? .primary, scheme: colorScheme) }
    private var key: String { "\(latex)|\(size)|\(display)|\(colorHex)|\(fontFamily)" }

    var body: some View {
        Group {
            if let image {
                platformImage(image).resizable()
                    .frame(width: image.size.width, height: image.size.height)
            } else {
                NativeMathView(latex: latex, size: size, display: display)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(latex.isEmpty ? "Empty formula" : latex)
        .task(id: key) {
            image = nil
            let result = await NativeMathSnapshotRenderer.shared.render(
                latex: latex, size: size, display: display, colorHex: colorHex, fontFamily: fontFamily)
            if !Task.isCancelled { image = result }
        }
    }

    private func platformImage(_ image: NativeMathPlatformImage) -> Image {
        #if os(iOS)
        Image(uiImage: image)
        #else
        Image(nsImage: image)
        #endif
    }
}

enum NativeMathColorHex {
    static func resolve(_ color: Color, scheme: ColorScheme) -> String {
        var environment = EnvironmentValues()
        environment.colorScheme = scheme
        let rgba = color.resolve(in: environment)
        func channel(_ value: Float) -> Int { max(0, min(255, Int((value * 255).rounded()))) }
        let red = channel(rgba.red), green = channel(rgba.green), blue = channel(rgba.blue)
        let alpha = channel(rgba.opacity)
        return alpha == 255 ? String(format: "#%02X%02X%02X", red, green, blue) :
            String(format: "#%02X%02X%02X%02X", red, green, blue, alpha)
    }
}

@MainActor
final class NativeMathSnapshotRenderer: NSObject, WKNavigationDelegate {
    static let shared = NativeMathSnapshotRenderer()

    private struct Job {
        let id: UUID
        let key: NSString
        let html: String
        let continuation: CheckedContinuation<NativeMathPlatformImage?, Never>
    }

    private static let initialViewport = CGSize(width: 2048, height: 2048)
    private static let maximumSnapshotSide: CGFloat = 8192
    private let webView = WKWebView(frame: CGRect(origin: .zero, size: initialViewport))
    private let cache = NSCache<NSString, NativeMathPlatformImage>()
    private var jobs: [Job] = []
    private var active: Job?

    private override init() {
        super.init()
        webView.navigationDelegate = self
        #if os(iOS)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.underPageBackgroundColor = .clear
        #else
        webView.setValue(false, forKey: "drawsBackground")
        webView.underPageBackgroundColor = .clear
        #endif
        cache.countLimit = 128
        cache.totalCostLimit = 32 * 1024 * 1024
    }

    func render(latex: String, size: CGFloat, display: Bool, colorHex: String, fontFamily: String = "serif") async -> NativeMathPlatformImage? {
        let key = "\(latex)|\(size)|\(display)|\(colorHex)|\(fontFamily)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let html = NativeMathML.html(latex, size: Int(size.rounded()), display: display, colorHex: colorHex, fontFamily: fontFamily)
        return await withCheckedContinuation { continuation in
            jobs.append(Job(id: UUID(), key: key, html: html, continuation: continuation))
            startNext()
        }
    }

    private func startNext() {
        guard active == nil else { return }
        while let next = jobs.first, let cached = cache.object(forKey: next.key) {
            jobs.removeFirst().continuation.resume(returning: cached)
        }
        guard !jobs.isEmpty else { return }
        active = jobs.removeFirst()
        webView.frame = CGRect(origin: .zero, size: Self.initialViewport)
        webView.loadHTMLString(active!.html, baseURL: nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let id = active?.id else { return }
        let script = """
        (() => { const r = document.getElementById('formula').getBoundingClientRect();
        return {width: Math.ceil(r.width) + 2, height: Math.ceil(r.height) + 2}; })()
        """
        webView.evaluateJavaScript(script) { [weak self] result, _ in
            Task { @MainActor [weak self] in
                guard let self, self.active?.id == id else { return }
                let bounds = result as? [String: NSNumber]
                guard let width = bounds?["width"]?.doubleValue,
                      let height = bounds?["height"]?.doubleValue,
                      width > 0, height > 0,
                      width <= Self.maximumSnapshotSide, height <= Self.maximumSnapshotSide else {
                    self.finish(nil)
                    return
                }
                // Snapshot rects outside the WebView viewport can be clipped. Resize to
                // the measured intrinsic size before capturing wide display formulas.
                webView.frame = CGRect(x: 0, y: 0, width: width, height: height)
                let config = WKSnapshotConfiguration()
                config.rect = CGRect(x: 0, y: 0, width: width, height: height)
                webView.takeSnapshot(with: config) { [weak self] image, _ in
                    Task { @MainActor [weak self] in
                        guard let self, self.active?.id == id else { return }
                        self.finish(image)
                    }
                }
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(nil)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(nil)
    }

    private func finish(_ image: NativeMathPlatformImage?) {
        guard let job = active else { return }
        active = nil
        if let image {
            let pixels = image.size.width * image.size.height
            cache.setObject(image, forKey: job.key, cost: Int(min(pixels * 4, CGFloat(Int.max))))
        }
        job.continuation.resume(returning: image)
        startNext()
    }
}
