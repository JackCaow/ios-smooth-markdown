import Foundation
import SwiftUI
import WebKit

/// Browser-grade SVG fallback for features that CoreGraphics does not implement,
/// including embedded WOFF2 fonts. JavaScript and user navigation are disabled.
#if os(iOS)
struct SVGWebKitView: UIViewRepresentable {
    let svg: SVG

    func makeUIView(context: Context) -> WKWebView {
        let webView = SVGWebKitConfiguration.makeView()
        webView.isOpaque = false
        webView.scrollView.isScrollEnabled = false
        webView.navigationDelegate = context.coordinator
        configureViewportUpdates(for: webView)
        if webView.bounds.width > 0 { load(into: webView, width: webView.bounds.width) }
        context.coordinator.loadedData = svg.sourceData
        context.coordinator.loadedBaseURL = svg.baseURL
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        configureViewportUpdates(for: webView)
        guard context.coordinator.loadedData != svg.sourceData || context.coordinator.loadedBaseURL != svg.baseURL else { return }
        if webView.bounds.width > 0 { load(into: webView, width: webView.bounds.width) }
        context.coordinator.loadedData = svg.sourceData
        context.coordinator.loadedBaseURL = svg.baseURL
    }

    func makeCoordinator() -> SVGWebKitNavigationGuard { SVGWebKitNavigationGuard() }

    private func configureViewportUpdates(for webView: WKWebView) {
        (webView as? SVGWebKitSizingView)?.onWidthChange = { [weak webView] width in
            guard let webView else { return }
            load(into: webView, width: width)
        }
    }

    private func load(into webView: WKWebView, width: CGFloat) {
        if let html = SVGWebKitConfiguration.html(for: svg, viewportWidth: width) {
            webView.loadHTMLString(html, baseURL: svg.baseURL ?? URL(string: "https://svg.invalid/")!)
        }
    }
}
#elseif os(macOS)
struct SVGWebKitView: NSViewRepresentable {
    let svg: SVG

    func makeNSView(context: Context) -> WKWebView {
        let webView = SVGWebKitConfiguration.makeView()
        webView.navigationDelegate = context.coordinator
        load(into: webView)
        context.coordinator.loadedData = svg.sourceData
        context.coordinator.loadedBaseURL = svg.baseURL
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.loadedData != svg.sourceData || context.coordinator.loadedBaseURL != svg.baseURL else { return }
        load(into: webView)
        context.coordinator.loadedData = svg.sourceData
        context.coordinator.loadedBaseURL = svg.baseURL
    }

    func makeCoordinator() -> SVGWebKitNavigationGuard { SVGWebKitNavigationGuard() }

    private func load(into webView: WKWebView) {
        if let html = SVGWebKitConfiguration.html(for: svg) {
            webView.loadHTMLString(html, baseURL: svg.baseURL ?? URL(string: "https://svg.invalid/")!)
        }
    }
}
#endif

enum SVGWebKitConfiguration {
    static func html(for svg: SVG, viewportWidth: CGFloat? = nil) -> String? {
        let bytes = svg.sourceData
        let looksUTF16 = bytes.starts(with: [0xFF, 0xFE]) || bytes.starts(with: [0xFE, 0xFF])
            || bytes.prefix(32).contains(0)
        guard let source = looksUTF16 ? String(data: bytes, encoding: .utf16)
                : (String(data: bytes, encoding: .utf8) ?? String(data: bytes, encoding: .isoLatin1)),
              let start = source.range(of: #"<([A-Za-z_][\w.-]*:)?svg(?=[\s/>])"#,
                                       options: .regularExpression),
              let rootEnd = source[start.lowerBound...].firstIndex(of: ">") else { return nil }
        let rootName = String(source[source.index(after: start.lowerBound)..<start.upperBound])
        let closing = "</\(rootName)>"
        let end = source.range(of: closing, options: .backwards)?.upperBound
            ?? (source[start.upperBound...].range(of: "/>")?.upperBound)
        guard let end else { return nil }
        var markup = String(source[start.lowerBound..<end])
        if let prefixEnd = rootName.firstIndex(of: ":") {
            let prefix = rootName[..<prefixEnd]
            markup = markup.replacingOccurrences(of: #"<(/?)"# + NSRegularExpression.escapedPattern(for: String(prefix)) + #":(?=[A-Za-z_])"#,
                                                 with: "<$1", options: .regularExpression)
        }
        if let rootEnd = markup.firstIndex(of: ">"), !markup[..<rootEnd].contains("viewBox") {
            let width = svg.size.width, height = svg.size.height
            markup.insert(contentsOf: " viewBox=\"0 0 \(width) \(height)\"", at: rootEnd)
        }
        // `device-width` is the full iPhone width even inside a small WKWebView.
        // Match the actual view width so both badges and resized SVGs use one CSS pixel per point.
        let width = max(1, Int((viewportWidth ?? svg.size.width).rounded()))
        return "<html><head><meta name='viewport' content='width=\(width),initial-scale=1,minimum-scale=1,maximum-scale=1,user-scalable=no'><style>html,body{margin:0;width:100%;height:100%;background:transparent;overflow:hidden}body>svg{width:100%;height:100%}</style></head><body>\(markup)</body></html>"
    }

    static func makeView() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        #if os(iOS)
        let webView = SVGWebKitSizingView(frame: .zero, configuration: configuration)
        #else
        let webView = WKWebView(frame: .zero, configuration: configuration)
        #endif
        webView.underPageBackgroundColor = .clear
        return webView
    }
}

#if os(iOS)
private final class SVGWebKitSizingView: WKWebView {
    var onWidthChange: ((CGFloat) -> Void)?
    private var lastWidth: CGFloat = 0

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width
        guard width > 0, abs(width - lastWidth) > 0.5 else { return }
        lastWidth = width
        onWidthChange?(width)
    }
}
#endif

final class SVGWebKitNavigationGuard: NSObject, WKNavigationDelegate {
    var loadedData: Data?
    var loadedBaseURL: URL?
    var onFinished: (() -> Void)?

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { onFinished?() }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(navigationAction.navigationType == .linkActivated ? .cancel : .allow)
    }
}
