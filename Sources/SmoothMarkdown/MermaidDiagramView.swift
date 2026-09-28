import SwiftUI

/// Native Canvas rendering for the currently supported Mermaid diagrams.
public struct MermaidDiagramView: View {
    public let diagram: MermaidDiagram
    @Environment(\.colorScheme) private var colorScheme

    public init(diagram: MermaidDiagram) { self.diagram = diagram }

    public var body: some View {
        let layout = MermaidLayout.compute(diagram)
        ScrollView(.horizontal) {
            Canvas { context, _ in
                let ink: Color = colorScheme == .dark ? .white : Color(red: 0.15, green: 0.18, blue: 0.24)
                let fill: Color = colorScheme == .dark ? Color(red: 0.18, green: 0.22, blue: 0.31) : Color(red: 0.92, green: 0.95, blue: 1)
                if diagram.kind == .pie {
                    drawPie(in: context, diagram: diagram, size: layout.size, ink: ink)
                    return
                }
                if diagram.kind == .timeline {
                    drawTimeline(in: context, diagram: diagram, size: layout.size, ink: ink)
                    return
                }
                if diagram.kind == .sequence {
                    for node in diagram.nodes {
                        guard let frame = layout.nodes[node.id] else { continue }
                        var line = Path()
                        line.move(to: CGPoint(x: frame.midX, y: frame.maxY))
                        line.addLine(to: CGPoint(x: frame.midX, y: layout.size.height - 16))
                        context.stroke(line, with: .color(ink.opacity(0.4)), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                    }
                }
                for placed in layout.edges { drawEdge(placed, in: context, ink: ink, background: colorScheme == .dark ? .black : .white) }
                for node in diagram.nodes {
                    guard let frame = layout.nodes[node.id] else { continue }
                    let shape = diagram.kind == .sequence ? MermaidShape.rounded : node.shape
                    let path = nodePath(shape, frame: frame)
                    context.fill(path, with: .color(fill))
                    context.stroke(path, with: .color(ink), lineWidth: 1.5)
                    if shape == .subroutine {
                        for x in [frame.minX + 8, frame.maxX - 8] {
                            var line = Path(); line.move(to: CGPoint(x: x, y: frame.minY)); line.addLine(to: CGPoint(x: x, y: frame.maxY))
                            context.stroke(line, with: .color(ink), lineWidth: 1)
                        }
                    }
                    context.draw(Text(node.label).font(.system(size: 13, weight: .medium)).foregroundColor(ink),
                                 at: CGPoint(x: frame.midX, y: frame.midY))
                }
            }
            .frame(width: max(layout.size.width, 180), height: max(layout.size.height, 100))
        }
        .background(colorScheme == .dark ? Color(red: 0.10, green: 0.12, blue: 0.17) : .white,
                    in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3)))
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        switch diagram.kind {
        case .flowchart: "Flowchart with \(diagram.nodes.count) nodes and \(diagram.edges.count) connections"
        case .sequence: "Sequence diagram with \(diagram.nodes.count) participants and \(diagram.edges.count) messages"
        case .pie: "Pie chart with \(diagram.pieSlices.count) slices"
        case .timeline: "Timeline with \(diagram.timelineSections.count) periods"
        }
    }

    private func drawPie(in context: GraphicsContext, diagram: MermaidDiagram, size: CGSize, ink: Color) {
        let total = diagram.pieSlices.reduce(0) { $0 + $1.value }
        guard total > 0 else { return }
        if let title = diagram.title {
            context.draw(Text(title).font(.system(size: 16, weight: .semibold)).foregroundColor(ink),
                         at: CGPoint(x: size.width / 2, y: 22))
        }
        let center = CGPoint(x: 126, y: 144)
        let radius: CGFloat = 98
        var start = -Double.pi / 2
        for (index, slice) in diagram.pieSlices.enumerated() {
            let end = start + 2 * .pi * slice.value / total
            var sector = Path()
            sector.move(to: center)
            sector.addArc(center: center, radius: radius, startAngle: .radians(start),
                          endAngle: .radians(end), clockwise: false)
            sector.closeSubpath()
            let color = pieColor(index)
            context.fill(sector, with: .color(color))
            context.stroke(sector, with: .color(.white.opacity(0.8)), lineWidth: 1)
            start = end
            let marker = CGRect(x: 254, y: 66 + CGFloat(index) * 24, width: 12, height: 12)
            context.fill(Path(roundedRect: marker, cornerRadius: 2), with: .color(color))
            let value = diagram.showData ? " · \(slice.value.formatted())" : ""
            context.draw(Text(slice.label + value).font(.system(size: 12)).foregroundColor(ink),
                         at: CGPoint(x: 274, y: marker.midY), anchor: .leading)
        }
    }

    private func drawTimeline(in context: GraphicsContext, diagram: MermaidDiagram, size: CGSize, ink: Color) {
        if let title = diagram.title {
            context.draw(Text(title).font(.system(size: 16, weight: .semibold)).foregroundColor(ink),
                         at: CGPoint(x: min(size.width / 2, 190), y: 24))
        }
        let axisY: CGFloat = 114
        var axis = Path()
        axis.move(to: CGPoint(x: 54, y: axisY))
        axis.addLine(to: CGPoint(x: size.width - 54, y: axisY))
        context.stroke(axis, with: .color(ink.opacity(0.65)), lineWidth: 2)
        for (index, section) in diagram.timelineSections.enumerated() {
            let x = CGFloat(index) * 180 + 122
            let color = pieColor(index)
            context.fill(Path(ellipseIn: CGRect(x: x - 7, y: axisY - 7, width: 14, height: 14)), with: .color(color))
            context.draw(Text(section.title).font(.system(size: 13, weight: .semibold)).foregroundColor(ink),
                         at: CGPoint(x: x, y: 82))
            for (eventIndex, event) in section.events.enumerated() {
                let y = CGFloat(154 + eventIndex * 30)
                context.draw(Text(event.title).font(.system(size: 12)).foregroundColor(ink),
                             at: CGPoint(x: x, y: y))
                if let description = event.description {
                    context.draw(Text(description).font(.system(size: 10)).foregroundColor(ink.opacity(0.7)),
                                 at: CGPoint(x: x, y: y + 13))
                }
            }
        }
    }

    private func pieColor(_ index: Int) -> Color {
        Color(hue: Double((index * 7) % 17) / 17.0, saturation: 0.65, brightness: colorScheme == .dark ? 0.88 : 0.72)
    }

    private func drawEdge(_ placed: MermaidPlacedEdge, in context: GraphicsContext, ink: Color, background: Color) {
        let start = placed.start, end = placed.end
        var path = Path()
        path.move(to: start)
        path.addLine(to: end)
        let style = StrokeStyle(lineWidth: placed.edge.line == .thick ? 2.5 : 1.5,
                                dash: placed.edge.line == .dotted ? [5, 4] : [])
        context.stroke(path, with: .color(ink), style: style)
        let angle = atan2(end.y - start.y, end.x - start.x)
        if placed.edge.arrow == .arrow {
            let length: CGFloat = 10
            var head = Path()
            head.move(to: end)
            head.addLine(to: CGPoint(x: end.x - length * cos(angle - .pi / 6), y: end.y - length * sin(angle - .pi / 6)))
            head.move(to: end)
            head.addLine(to: CGPoint(x: end.x - length * cos(angle + .pi / 6), y: end.y - length * sin(angle + .pi / 6)))
            context.stroke(head, with: .color(ink), lineWidth: 1.5)
        } else if placed.edge.arrow == .cross {
            var cross = Path()
            for sign in [-1.0, 1.0] {
                let offset = CGFloat(sign) * 5
                cross.move(to: CGPoint(x: end.x + offset * cos(angle + .pi / 2) - 5 * cos(angle),
                                       y: end.y + offset * sin(angle + .pi / 2) - 5 * sin(angle)))
                cross.addLine(to: CGPoint(x: end.x - offset * cos(angle + .pi / 2) - 5 * cos(angle),
                                          y: end.y - offset * sin(angle + .pi / 2) - 5 * sin(angle)))
            }
            context.stroke(cross, with: .color(ink), lineWidth: 1.5)
        }
        if let label = placed.edge.label, !label.isEmpty {
            let middle = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2 - 11)
            let width = min(max(CGFloat(label.utf16.count) * 7 + 10, 28), 190)
            context.fill(Path(roundedRect: CGRect(x: middle.x - width / 2, y: middle.y - 9, width: width, height: 18), cornerRadius: 3),
                         with: .color(background))
            context.draw(Text(label).font(.system(size: 11)).foregroundColor(ink), at: middle)
        }
    }

    private func nodePath(_ shape: MermaidShape, frame: CGRect) -> Path {
        switch shape {
        case .rectangle, .subroutine: return Path(frame)
        case .rounded: return Path(roundedRect: frame, cornerRadius: 8)
        case .stadium: return Path(roundedRect: frame, cornerRadius: frame.height / 2)
        case .circle: return Path(ellipseIn: frame)
        case .diamond:
            var path = Path()
            path.move(to: CGPoint(x: frame.midX, y: frame.minY))
            path.addLine(to: CGPoint(x: frame.maxX, y: frame.midY))
            path.addLine(to: CGPoint(x: frame.midX, y: frame.maxY))
            path.addLine(to: CGPoint(x: frame.minX, y: frame.midY))
            path.closeSubpath()
            return path
        case .cylinder:
            return Path(roundedRect: frame, cornerRadius: 10)
        }
    }
}
