#if canImport(UIKit)
import SwiftUI
import UIKit

/// A native, two-axis zoomable Mermaid viewport for gallery and detail screens.
/// The inline `MermaidDiagramView` keeps its existing horizontal scroll behavior.
public struct InteractiveMermaidDiagramView: View {
    public let diagram: MermaidDiagram
    public let theme: MermaidTheme?
    public let minScale: CGFloat
    public let maxScale: CGFloat
    public let onNodeTap: ((String) -> Void)?
    @ScaledMetric(relativeTo: .body) private var diagramScale: CGFloat = 1

    public init(diagram: MermaidDiagram, theme: MermaidTheme? = nil,
                minScale: CGFloat = 0.5, maxScale: CGFloat = 3,
                onNodeTap: ((String) -> Void)? = nil) {
        self.diagram = diagram
        self.theme = theme
        self.minScale = minScale
        self.maxScale = maxScale
        self.onNodeTap = onNodeTap
    }

    public var body: some View {
        let layout = MermaidLayout.compute(diagram)
        let scale = max(1, diagramScale)
        let size = CGSize(width: max(layout.size.width, 180) * scale,
                          height: max(layout.size.height, 100) * scale)
        MermaidZoomHost(diagram: diagram, theme: theme, onNodeTap: onNodeTap,
                        layout: layout, contentScale: scale, contentSize: size,
                        minScale: minScale, maxScale: maxScale)
            .accessibilityIdentifier("mermaid-interactive-viewport")
    }
}

private struct MermaidZoomHost: UIViewControllerRepresentable {
    let diagram: MermaidDiagram
    let theme: MermaidTheme?
    let onNodeTap: ((String) -> Void)?
    let layout: MermaidLayoutResult
    let contentScale: CGFloat
    let contentSize: CGSize
    let minScale: CGFloat
    let maxScale: CGFloat

    func makeUIViewController(context: Context) -> MermaidZoomController {
        MermaidZoomController(self)
    }

    func updateUIViewController(_ controller: MermaidZoomController, context: Context) {
        controller.update(self)
    }
}

private final class MermaidZoomController: UIViewController, UIScrollViewDelegate, UIGestureRecognizerDelegate {
    private let scrollView = UIScrollView()
    private let hostingController: UIHostingController<MermaidDiagramView>
    private var host: MermaidZoomHost
    private var needsFit = true
    private var lastViewport: CGSize = .zero

    init(_ host: MermaidZoomHost) {
        self.host = host
        hostingController = UIHostingController(rootView: MermaidDiagramView(
            diagram: host.diagram, theme: host.theme, onNodeTap: host.onNodeTap, scrollable: false))
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.backgroundColor = .clear
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.delaysContentTouches = false
        scrollView.delegate = self
        scrollView.minimumZoomScale = max(0.01, host.minScale)
        scrollView.maximumZoomScale = max(scrollView.minimumZoomScale, host.maxScale)
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        addChild(hostingController)
        hostingController.view.backgroundColor = .clear
        hostingController.view.frame = CGRect(origin: .zero, size: host.contentSize)
        scrollView.addSubview(hostingController.view)
        hostingController.didMove(toParent: self)
        scrollView.contentSize = host.contentSize

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.delegate = self
        scrollView.addGestureRecognizer(doubleTap)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard scrollView.bounds.width > 0, scrollView.bounds.height > 0,
              needsFit || lastViewport != scrollView.bounds.size else { return }
        needsFit = false
        lastViewport = scrollView.bounds.size
        let fit = MermaidInteractiveViewportGeometry.fittedScale(
            content: host.contentSize, viewport: lastViewport,
            minScale: scrollView.minimumZoomScale, maxScale: scrollView.maximumZoomScale)
        scrollView.setZoomScale(fit, animated: false)
        centerContent()
    }

    func update(_ next: MermaidZoomHost) {
        let shouldFit = host.diagram != next.diagram ||
            host.theme?.rawValue != next.theme?.rawValue ||
            host.contentSize != next.contentSize ||
            host.minScale != next.minScale || host.maxScale != next.maxScale
        host = next
        hostingController.rootView = MermaidDiagramView(
            diagram: next.diagram, theme: next.theme, onNodeTap: next.onNodeTap, scrollable: false)
        if shouldFit {
            scrollView.setZoomScale(1, animated: false)
            hostingController.view.frame = CGRect(origin: .zero, size: next.contentSize)
            scrollView.contentSize = next.contentSize
        }
        scrollView.minimumZoomScale = max(0.01, next.minScale)
        scrollView.maximumZoomScale = max(scrollView.minimumZoomScale, next.maxScale)
        if shouldFit { needsFit = true; view.setNeedsLayout() }
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { hostingController.view }

    func scrollViewDidZoom(_ scrollView: UIScrollView) { centerContent() }

    private func centerContent() {
        let inset = MermaidInteractiveViewportGeometry.centeredInset(
            content: host.contentSize, viewport: scrollView.bounds.size, scale: scrollView.zoomScale)
        scrollView.contentInset = UIEdgeInsets(top: inset.height, left: inset.width,
                                              bottom: inset.height, right: inset.width)
    }

    @objc private func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
        let fit = MermaidInteractiveViewportGeometry.fittedScale(
            content: host.contentSize, viewport: scrollView.bounds.size,
            minScale: scrollView.minimumZoomScale, maxScale: scrollView.maximumZoomScale)
        if scrollView.zoomScale > fit * 1.1 {
            scrollView.setZoomScale(fit, animated: true)
            return
        }
        let zoom = min(scrollView.maximumZoomScale, max(fit * 2, scrollView.zoomScale * 2))
        let point = recognizer.location(in: hostingController.view)
        let rect = CGRect(x: point.x - scrollView.bounds.width / (2 * zoom),
                          y: point.y - scrollView.bounds.height / (2 * zoom),
                          width: scrollView.bounds.width / zoom,
                          height: scrollView.bounds.height / zoom)
        scrollView.zoom(to: rect, animated: true)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // Let the hosted SwiftUI button own node taps, preserving its source ID callback.
        let point = touch.location(in: hostingController.view)
        return MermaidInteractiveViewportGeometry.nodeID(
            at: point, layout: host.layout, diagram: host.diagram,
            contentScale: host.contentScale) == nil
    }
}
#endif
