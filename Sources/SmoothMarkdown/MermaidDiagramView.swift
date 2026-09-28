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
                if diagram.kind == .gantt {
                    drawGantt(in: context, diagram: diagram, size: layout.size, ink: ink)
                    return
                }
                if diagram.kind == .kanban {
                    drawKanban(in: context, diagram: diagram, size: layout.size, ink: ink)
                    return
                }
                if diagram.kind == .radar {
                    drawRadar(in: context, diagram: diagram, ink: ink)
                    return
                }
                if diagram.kind == .xyChart {
                    drawXYChart(in: context, diagram: diagram, ink: ink)
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
                for placed in layout.edges {
                    if placed.edge.from == placed.edge.to, let frame = layout.nodes[placed.edge.from] {
                        drawSelfEdge(placed.edge, frame: frame, in: context, ink: ink)
                    } else {
                        drawEdge(placed, in: context, ink: ink, background: colorScheme == .dark ? .black : .white)
                    }
                }
                for node in diagram.nodes {
                    guard let frame = layout.nodes[node.id] else { continue }
                    let shape = diagram.kind == .sequence ? MermaidShape.rounded : node.shape
                    let path = nodePath(shape, frame: frame)
                    context.fill(path, with: .color(shape == .stateStart ? ink : fill))
                    context.stroke(path, with: .color(ink), lineWidth: 1.5)
                    if shape == .subroutine {
                        for x in [frame.minX + 8, frame.maxX - 8] {
                            var line = Path(); line.move(to: CGPoint(x: x, y: frame.minY)); line.addLine(to: CGPoint(x: x, y: frame.maxY))
                            context.stroke(line, with: .color(ink), lineWidth: 1)
                        }
                    }
                    if !node.compartments.isEmpty {
                        drawCompartments(node, frame: frame, in: context, ink: ink)
                    } else if shape == .stateEnd {
                        context.fill(Path(ellipseIn: frame.insetBy(dx: 7, dy: 7)), with: .color(ink))
                    } else if shape != .stateStart {
                        context.draw(Text(node.label).font(.system(size: 13, weight: .medium)).foregroundColor(ink),
                                     at: CGPoint(x: frame.midX, y: frame.midY))
                    }
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
        case .classDiagram: "Class diagram with \(diagram.nodes.count) classes and \(diagram.edges.count) relationships"
        case .stateDiagram: "State diagram with \(diagram.nodes.count) states and \(diagram.edges.count) transitions"
        case .erDiagram: "ER diagram with \(diagram.nodes.count) entities and \(diagram.edges.count) relationships"
        case .pie: "Pie chart with \(diagram.pieSlices.count) slices"
        case .timeline: "Timeline with \(diagram.timelineSections.count) periods"
        case .gantt: "Gantt chart with \(diagram.ganttTasks.count) tasks"
        case .kanban: "Kanban board with \(diagram.kanbanColumns.count) columns"
        case .radar: "Radar chart with \(diagram.radarAxes.count) axes and \(diagram.radarCurves.count) curves"
        case .xyChart: "XY chart with \(diagram.xySeries.count) series"
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

    private func drawGantt(in context: GraphicsContext, diagram: MermaidDiagram, size: CGSize, ink: Color) {
        if let title = diagram.title {
            context.draw(Text(title).font(.system(size: 16, weight: .semibold)).foregroundColor(ink),
                         at: CGPoint(x: min(size.width / 2, 210), y: 22))
        }
        let bars = MermaidLayout.ganttBars(diagram)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        if let start = diagram.ganttTasks.map(\.startDate).min(), let end = diagram.ganttTasks.map(\.endDate).max() {
            context.draw(Text(formatter.string(from: start)).font(.system(size: 11)).foregroundColor(ink.opacity(0.7)),
                         at: CGPoint(x: 180, y: 60), anchor: .leading)
            context.draw(Text(formatter.string(from: end)).font(.system(size: 11)).foregroundColor(ink.opacity(0.7)),
                         at: CGPoint(x: size.width - 20, y: 60), anchor: .trailing)
        }
        for (index, task) in diagram.ganttTasks.enumerated() {
            guard index < bars.count else { continue }
            let frame = bars[index]
            let color: Color = switch task.status {
            case .normal: .blue
            case .done: .green
            case .active: .cyan
            case .critical: .red
            case .milestone: .orange
            }
            let label = task.section.map { "\($0) · \(task.name)" } ?? task.name
            context.draw(Text(String(label.prefix(25))).font(.system(size: 11)).foregroundColor(ink),
                         at: CGPoint(x: 16, y: frame.midY), anchor: .leading)
            let path: Path
            if task.status == .milestone {
                var diamond = Path()
                diamond.move(to: CGPoint(x: frame.midX, y: frame.minY))
                diamond.addLine(to: CGPoint(x: frame.maxX, y: frame.midY))
                diamond.addLine(to: CGPoint(x: frame.midX, y: frame.maxY))
                diamond.addLine(to: CGPoint(x: frame.minX, y: frame.midY))
                diamond.closeSubpath()
                path = diamond
            } else { path = Path(roundedRect: frame, cornerRadius: 4) }
            context.fill(path, with: .color(color))
            context.stroke(path, with: .color(ink.opacity(0.35)), lineWidth: 1)
        }
    }

    private func drawKanban(in context: GraphicsContext, diagram: MermaidDiagram, size: CGSize, ink: Color) {
        if let title = diagram.title {
            context.draw(Text(title).font(.system(size: 16, weight: .semibold)).foregroundColor(ink),
                         at: CGPoint(x: min(size.width / 2, 195), y: 22))
        }
        for (index, column) in diagram.kanbanColumns.enumerated() {
            let frame = MermaidLayout.kanbanColumns(diagram)[index]
            context.fill(Path(roundedRect: frame, cornerRadius: 8),
                         with: .color(colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.04)))
            context.stroke(Path(roundedRect: frame, cornerRadius: 8), with: .color(ink.opacity(0.25)), lineWidth: 1)
            let heading = column.title + (column.wipLimit.map { "  \(column.tasks.count)/\($0)" } ?? "")
            context.draw(Text(String(heading.prefix(24))).font(.system(size: 13, weight: .semibold))
                .foregroundColor(column.isOverLimit ? .red : ink),
                at: CGPoint(x: frame.minX + 12, y: frame.minY + 20), anchor: .leading)
            for (taskIndex, task) in column.tasks.enumerated() {
                let card = CGRect(x: frame.minX + 10, y: frame.minY + 44 + CGFloat(taskIndex) * 86,
                                  width: frame.width - 20, height: 74)
                context.fill(Path(roundedRect: card, cornerRadius: 6),
                             with: .color(colorScheme == .dark ? Color.black.opacity(0.35) : .white))
                context.stroke(Path(roundedRect: card, cornerRadius: 6), with: .color(ink.opacity(0.18)), lineWidth: 1)
                let stripe: Color = switch task.priority {
                case .veryHigh: .red
                case .high: .orange
                case .normal: .gray
                case .low: .blue
                case .veryLow: .green
                }
                context.fill(Path(CGRect(x: card.minX + 1, y: card.minY + 5, width: 4, height: card.height - 10)), with: .color(stripe))
                context.draw(Text(String(task.description.prefix(23))).font(.system(size: 12, weight: .medium)).foregroundColor(ink),
                             at: CGPoint(x: card.minX + 14, y: card.minY + 22), anchor: .leading)
                let detail = [task.assigned, task.ticket].compactMap { $0 }.joined(separator: " · ")
                if !detail.isEmpty {
                    context.draw(Text(String(detail.prefix(27))).font(.system(size: 10)).foregroundColor(ink.opacity(0.65)),
                                 at: CGPoint(x: card.minX + 14, y: card.minY + 51), anchor: .leading)
                }
            }
        }
    }

    private func drawRadar(in context: GraphicsContext, diagram: MermaidDiagram, ink: Color) {
        let count = diagram.radarAxes.count
        guard count > 0 else { return }
        if let title = diagram.title {
            context.draw(Text(title).font(.system(size: 16, weight: .semibold)).foregroundColor(ink),
                         at: CGPoint(x: 210, y: 24))
        }
        let minimum = diagram.radarMinimum ?? 0
        let observed = diagram.radarCurves.flatMap(\.values).max() ?? 1
        let maximum = max(minimum + 1, diagram.radarMaximum ?? observed)
        let radius: CGFloat = 116
        for tick in 1...max(1, diagram.radarTicks) {
            let r = radius * CGFloat(tick) / CGFloat(max(1, diagram.radarTicks))
            if diagram.radarGraticule == .circle {
                context.stroke(Path(ellipseIn: CGRect(x: 210 - r, y: 200 - r, width: 2 * r, height: 2 * r)),
                               with: .color(ink.opacity(0.20)), lineWidth: 1)
            } else {
                var ring = Path()
                for index in 0..<count {
                    let point = MermaidLayout.radarPoint(index: index, count: count, radius: r)
                    if index == 0 { ring.move(to: point) } else { ring.addLine(to: point) }
                }
                ring.closeSubpath()
                context.stroke(ring, with: .color(ink.opacity(0.20)), lineWidth: 1)
            }
        }
        for (index, axis) in diagram.radarAxes.enumerated() {
            let end = MermaidLayout.radarPoint(index: index, count: count, radius: radius)
            var spoke = Path()
            spoke.move(to: CGPoint(x: 210, y: 200)); spoke.addLine(to: end)
            context.stroke(spoke, with: .color(ink.opacity(0.35)), lineWidth: 1)
            let label = MermaidLayout.radarPoint(index: index, count: count, radius: radius + 25)
            context.draw(Text(String(axis.label.prefix(14))).font(.system(size: 11)).foregroundColor(ink), at: label)
        }
        for (curveIndex, curve) in diagram.radarCurves.enumerated() {
            let color = pieColor(curveIndex)
            var shape = Path()
            for index in 0..<count {
                let value = index < curve.values.count ? curve.values[index] : minimum
                let fraction = min(1, max(0, CGFloat((value - minimum) / (maximum - minimum))))
                let point = MermaidLayout.radarPoint(index: index, count: count, radius: radius * fraction)
                if index == 0 { shape.move(to: point) } else { shape.addLine(to: point) }
            }
            shape.closeSubpath()
            context.fill(shape, with: .color(color.opacity(0.18)))
            context.stroke(shape, with: .color(color), lineWidth: 2)
            if diagram.radarShowLegend {
                let y = CGFloat(370 + curveIndex * 22)
                context.fill(Path(ellipseIn: CGRect(x: 86, y: y - 5, width: 10, height: 10)), with: .color(color))
                context.draw(Text(String(curve.label.prefix(25))).font(.system(size: 11)).foregroundColor(ink),
                             at: CGPoint(x: 104, y: y), anchor: .leading)
            }
        }
    }

    private func drawXYChart(in context: GraphicsContext, diagram: MermaidDiagram, ink: Color) {
        let plot = MermaidLayout.xyPlotFrame(diagram)
        let count = max(diagram.xyCategories.count, diagram.xySeries.map { $0.values.count }.max() ?? 0)
        guard count > 0 else { return }
        let horizontal = diagram.xyOrientation == .horizontal
        if let title = diagram.title {
            context.draw(Text(title).font(.system(size: 16, weight: .semibold)).foregroundColor(ink),
                         at: CGPoint(x: min(plot.midX, 200), y: 24))
        }
        if let yTitle = diagram.xyYAxisTitle, !horizontal {
            context.draw(Text(yTitle).font(.system(size: 11)).foregroundColor(ink.opacity(0.8)),
                         at: CGPoint(x: plot.minX, y: 42), anchor: .leading)
        }
        let values = diagram.xySeries.flatMap(\.values)
        let minimum = min(diagram.xyYAxisMinimum ?? 0, values.min() ?? 0)
        let maximum = max(diagram.xyYAxisMaximum ?? 1, values.max() ?? 1, minimum + 1)
        let span = maximum - minimum
        var axes = Path()
        axes.move(to: CGPoint(x: plot.minX, y: plot.minY))
        axes.addLine(to: CGPoint(x: plot.minX, y: plot.maxY))
        axes.addLine(to: CGPoint(x: plot.maxX, y: plot.maxY))
        context.stroke(axes, with: .color(ink.opacity(0.8)), lineWidth: 1.5)
        for tick in 0...4 {
            let fraction = CGFloat(tick) / 4
            let point = horizontal ? CGPoint(x: plot.minX + plot.width * fraction, y: plot.maxY)
                : CGPoint(x: plot.minX, y: plot.maxY - plot.height * fraction)
            var grid = Path()
            if horizontal {
                grid.move(to: CGPoint(x: point.x, y: plot.minY)); grid.addLine(to: CGPoint(x: point.x, y: plot.maxY))
            } else {
                grid.move(to: CGPoint(x: plot.minX, y: point.y)); grid.addLine(to: CGPoint(x: plot.maxX, y: point.y))
            }
            context.stroke(grid, with: .color(ink.opacity(0.12)), lineWidth: 1)
            context.draw(Text((minimum + span * Double(fraction)).formatted(.number.precision(.fractionLength(0)))).font(.system(size: 10)).foregroundColor(ink),
                         at: horizontal ? CGPoint(x: point.x, y: plot.maxY + 14) : CGPoint(x: plot.minX - 10, y: point.y),
                         anchor: horizontal ? .center : .trailing)
        }
        let barSeries = diagram.xySeries.filter { $0.type == .bar }
        for (seriesIndex, series) in diagram.xySeries.enumerated() {
            let color = pieColor(seriesIndex)
            var line = Path()
            for (index, value) in series.values.enumerated() {
                let slot = CGFloat(index) + 0.5
                let valueFraction = CGFloat((value - minimum) / span)
                let zeroFraction = min(1, max(0, CGFloat((0 - minimum) / span)))
                let point = horizontal
                    ? CGPoint(x: plot.minX + valueFraction * plot.width, y: plot.minY + slot / CGFloat(count) * plot.height)
                    : CGPoint(x: plot.minX + slot / CGFloat(count) * plot.width, y: plot.maxY - valueFraction * plot.height)
                if series.type == .bar {
                    let barIndex = diagram.xySeries.prefix(seriesIndex).filter { $0.type == .bar }.count
                    let barCount = max(1, barSeries.count)
                    let slotSize = (horizontal ? plot.height : plot.width) / CGFloat(count)
                    let thickness = min(24, slotSize * 0.72 / CGFloat(barCount))
                    let offset = (CGFloat(barIndex) - CGFloat(barCount - 1) / 2) * thickness
                    let zero = horizontal ? plot.minX + zeroFraction * plot.width : plot.maxY - zeroFraction * plot.height
                    let frame = horizontal
                        ? CGRect(x: min(zero, point.x), y: point.y + offset - thickness / 2,
                                 width: max(1, abs(point.x - zero)), height: thickness)
                        : CGRect(x: point.x + offset - thickness / 2, y: min(zero, point.y),
                                 width: thickness, height: max(1, abs(point.y - zero)))
                    context.fill(Path(roundedRect: frame, cornerRadius: 3), with: .color(color.opacity(0.85)))
                } else {
                    if index == 0 { line.move(to: point) } else { line.addLine(to: point) }
                    context.fill(Path(ellipseIn: CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6)), with: .color(color))
                }
            }
            if series.type == .line { context.stroke(line, with: .color(color), lineWidth: 2) }
        }
        for index in 0..<count {
            let label = index < diagram.xyCategories.count ? diagram.xyCategories[index] : "\(index + 1)"
            let point = horizontal
                ? CGPoint(x: plot.minX - 8, y: plot.minY + (CGFloat(index) + 0.5) / CGFloat(count) * plot.height)
                : CGPoint(x: plot.minX + (CGFloat(index) + 0.5) / CGFloat(count) * plot.width, y: plot.maxY + 32)
            context.draw(Text(String(label.prefix(12))).font(.system(size: 10)).foregroundColor(ink), at: point,
                         anchor: horizontal ? .trailing : .center)
        }
        if let axisTitle = horizontal ? diagram.xyYAxisTitle : diagram.xyXAxisTitle {
            context.draw(Text(axisTitle).font(.system(size: 11)).foregroundColor(ink),
                         at: CGPoint(x: plot.midX, y: 315))
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
        if let marker = placed.edge.sourceMarker { drawMarker(marker, at: start, toward: end, in: context, ink: ink) }
        if let marker = placed.edge.targetMarker { drawMarker(marker, at: end, toward: start, in: context, ink: ink) }
        if placed.edge.sourceArrow == .arrow { drawArrow(at: start, angle: angle + .pi, in: context, ink: ink) }
        if placed.edge.arrow == .arrow {
            drawArrow(at: end, angle: angle, in: context, ink: ink)
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
        for (text, point) in [(placed.edge.sourceLabel, start), (placed.edge.targetLabel, end)] {
            guard let text, !text.isEmpty else { continue }
            context.draw(Text(text).font(.system(size: 10)).foregroundColor(ink),
                         at: CGPoint(x: point.x + 16, y: point.y - 13))
        }
    }

    private func drawCompartments(_ node: MermaidNode, frame: CGRect, in context: GraphicsContext, ink: Color) {
        context.draw(Text(node.label).font(.system(size: 13, weight: .semibold)).foregroundColor(ink),
                     at: CGPoint(x: frame.midX, y: frame.minY + 22))
        var y = frame.minY + 43
        for rows in node.compartments {
            var divider = Path()
            divider.move(to: CGPoint(x: frame.minX, y: y))
            divider.addLine(to: CGPoint(x: frame.maxX, y: y))
            context.stroke(divider, with: .color(ink.opacity(0.6)), lineWidth: 1)
            y += 13
            for row in rows {
                context.draw(Text(row).font(.system(size: 11, design: .monospaced)).foregroundColor(ink),
                             at: CGPoint(x: frame.minX + 9, y: y), anchor: .leading)
                y += 20
            }
        }
    }

    private func drawArrow(at point: CGPoint, angle: CGFloat, in context: GraphicsContext, ink: Color) {
        let length: CGFloat = 10
        var head = Path()
        head.move(to: point)
        head.addLine(to: CGPoint(x: point.x - length * cos(angle - .pi / 6), y: point.y - length * sin(angle - .pi / 6)))
        head.move(to: point)
        head.addLine(to: CGPoint(x: point.x - length * cos(angle + .pi / 6), y: point.y - length * sin(angle + .pi / 6)))
        context.stroke(head, with: .color(ink), lineWidth: 1.5)
    }

    private func drawMarker(_ marker: MermaidMarker, at point: CGPoint, toward other: CGPoint,
                            in context: GraphicsContext, ink: Color) {
        let angle = atan2(other.y - point.y, other.x - point.x)
        func position(_ forward: CGFloat, _ side: CGFloat = 0) -> CGPoint {
            CGPoint(x: point.x + forward * cos(angle) - side * sin(angle),
                    y: point.y + forward * sin(angle) + side * cos(angle))
        }
        var path = Path()
        switch marker {
        case .inheritance:
            path.move(to: point); path.addLine(to: position(14, 8)); path.addLine(to: position(14, -8)); path.closeSubpath()
            context.fill(path, with: .color(colorScheme == .dark ? .black : .white))
            context.stroke(path, with: .color(ink), lineWidth: 1.5)
        case .composition, .aggregation:
            path.move(to: point); path.addLine(to: position(8, 6)); path.addLine(to: position(16));
            path.addLine(to: position(8, -6)); path.closeSubpath()
            context.fill(path, with: .color(marker == .composition ? ink : (colorScheme == .dark ? .black : .white)))
            context.stroke(path, with: .color(ink), lineWidth: 1.5)
        case .exactlyOne, .zeroOrOne, .oneOrMore, .zeroOrMore:
            let multiple = marker == .oneOrMore || marker == .zeroOrMore
            let optional = marker == .zeroOrOne || marker == .zeroOrMore
            if multiple {
                for side: CGFloat in [-7, 0, 7] {
                    path.move(to: position(16)); path.addLine(to: position(5, side))
                }
            } else {
                for forward: CGFloat in [7, 12] {
                    path.move(to: position(forward, -7)); path.addLine(to: position(forward, 7))
                }
            }
            context.stroke(path, with: .color(ink), lineWidth: 1.5)
            if optional {
                context.fill(Path(ellipseIn: CGRect(x: position(19).x - 3, y: position(19).y - 3, width: 6, height: 6)),
                             with: .color(colorScheme == .dark ? .black : .white))
                context.stroke(Path(ellipseIn: CGRect(x: position(19).x - 3, y: position(19).y - 3, width: 6, height: 6)),
                               with: .color(ink), lineWidth: 1.5)
            }
        }
    }

    private func drawSelfEdge(_ edge: MermaidEdge, frame: CGRect, in context: GraphicsContext, ink: Color) {
        let x = frame.maxX, y = frame.midY
        var path = Path()
        path.move(to: CGPoint(x: x, y: y - 10))
        path.addCurve(to: CGPoint(x: x, y: y + 10), control1: CGPoint(x: x + 56, y: y - 50),
                      control2: CGPoint(x: x + 56, y: y + 50))
        context.stroke(path, with: .color(ink), style: StrokeStyle(lineWidth: 1.5,
                                                                  dash: edge.line == .dotted ? [5, 4] : []))
        drawArrow(at: CGPoint(x: x, y: y + 10), angle: .pi * 0.8, in: context, ink: ink)
        if let label = edge.label {
            context.draw(Text(label).font(.system(size: 10)).foregroundColor(ink),
                         at: CGPoint(x: x + 38, y: y - 26))
        }
    }

    private func nodePath(_ shape: MermaidShape, frame: CGRect) -> Path {
        switch shape {
        case .rectangle, .subroutine: return Path(frame)
        case .rounded: return Path(roundedRect: frame, cornerRadius: 8)
        case .stadium: return Path(roundedRect: frame, cornerRadius: frame.height / 2)
        case .circle, .stateStart, .stateEnd: return Path(ellipseIn: frame)
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
