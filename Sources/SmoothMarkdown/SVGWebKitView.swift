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
        load(into: webView)
        context.coordinator.loadedData = svg.sourceData
        context.coordinator.loadedBaseURL = svg.baseURL
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.loadedData != svg.sourceData || context.coordinator.loadedBaseURL != svg.baseURL else { return }
        load(into: webView)
        context.coordinator.loadedData = svg.sourceData
        context.coordinator.loadedBaseURL = svg.baseURL
    }

    func makeCoordinator() -> SVGWebKitNavigationGuard { SVGWebKitNavigationGuard() }

    private func load(into webView: WKWebView) {
        if let html = SVGWebKitConfiguration.html(for: svg.sourceData) {
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
        if let html = SVGWebKitConfiguration.html(for: svg.sourceData) {
            webView.loadHTMLString(html, baseURL: svg.baseURL ?? URL(string: "https://svg.invalid/")!)
        }
    }
}
#endif

enum SVGWebKitConfiguration {
    static func html(for data: Data) -> String? {
        guard let source = String(data: data, encoding: .utf8),
              let start = source.range(of: "<svg"),
              let end = source.range(of: "</svg>", options: .backwards) else { return nil }
        let svg = source[start.lowerBound..<end.upperBound]
        return "<html><head><meta name='viewport' content='width=device-width,initial-scale=1'><style>html,body{margin:0;width:100%;height:100%;background:transparent;overflow:hidden}body>svg{width:100%;height:100%}</style></head><body>\(svg)</body></html>"
    }

    static func makeView() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.underPageBackgroundColor = .clear
        return webView
    }
}

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
