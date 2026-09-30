import CoreGraphics
import Foundation
import SwiftUI
#if canImport(FoundationXML)
import FoundationXML
#endif

/// A deliberately bounded, native SVG document. External resources and XML entities are never loaded.
struct SVG {
    let size: CGSize
    fileprivate let viewBox: CGRect
    fileprivate let nodes: [SVGNode]
    fileprivate let gradients: [String: SVGGradient]

    init?(data: Data) {
        guard data.count <= 2 * 1024 * 1024 else { return nil }
        let parser = SVGXMLBuilder(data: data)
        guard parser.parse(), let root = parser.root, root.name == "svg" else { return nil }
        let box = SVGNumbers.list(root.attributes["viewBox"] ?? "")
        let viewBox = box.count == 4 && box[2] > 0 && box[3] > 0
            ? CGRect(x: box[0], y: box[1], width: box[2], height: box[3]) : .zero
        let width = SVGNumbers.length(root.attributes["width"]) ?? (viewBox.width > 0 ? viewBox.width : nil)
        let height = SVGNumbers.length(root.attributes["height"]) ?? (viewBox.height > 0 ? viewBox.height : nil)
        guard let width, let height, width.isFinite, height.isFinite,
              width > 0, height > 0, width <= 16384, height <= 16384 else { return nil }
        self.size = CGSize(width: width, height: height)
        self.viewBox = viewBox.width > 0 ? viewBox : CGRect(origin: .zero, size: size)
        self.nodes = root.children
        var gradients: [String: SVGGradient] = [:]
        root.walk { node in
            if let id = node.attributes["id"], let gradient = SVGGradient(node) { gradients[id] = gradient }
        }
        self.gradients = gradients
    }

    init?(named name: String, in bundle: Bundle) {
        let path = name as NSString
        let resource = path.deletingPathExtension
        let ext = path.pathExtension.isEmpty ? "svg" : path.pathExtension
        guard let url = bundle.url(forResource: resource, withExtension: ext),
              let data = try? Data(contentsOf: url) else { return nil }
        self.init(data: data)
    }
}

private enum SVGNumbers {
    static func list(_ value: String) -> [CGFloat] {
        let scanner = Scanner(string: value.replacingOccurrences(of: ",", with: " "))
        scanner.charactersToBeSkipped = .whitespacesAndNewlines
        var result: [CGFloat] = []
        while !scanner.isAtEnd {
            var number = 0.0
            if scanner.scanDouble(&number) { result.append(CGFloat(number)) }
            else { _ = scanner.scanCharacter() }
        }
        return result
    }

    static func length(_ value: String?) -> CGFloat? {
        guard let value else { return nil }
        let scanner = Scanner(string: value.trimmingCharacters(in: .whitespacesAndNewlines))
        var number = 0.0
        guard scanner.scanDouble(&number), number.isFinite else { return nil }
        let unit = String(value[scanner.currentIndex...]).trimmingCharacters(in: .whitespaces).lowercased()
        let scale: Double
        switch unit {
        case "", "px": scale = 1
        case "pt": scale = 4 / 3
        case "pc": scale = 16
        case "in": scale = 96
        case "cm": scale = 96 / 2.54
        case "mm": scale = 96 / 25.4
        default: return nil
        }
        return CGFloat(number * scale)
    }
}

private final class SVGNode {
    let name: String
    let attributes: [String: String]
    var children: [SVGNode] = []
    var text = ""
    init(name: String, attributes: [String: String]) {
        self.name = name
        self.attributes = attributes
    }
    func walk(_ visit: (SVGNode) -> Void) {
        visit(self)
        children.forEach { $0.walk(visit) }
    }
}

private final class SVGXMLBuilder: NSObject, XMLParserDelegate {
    private let parser: XMLParser
    private var stack: [SVGNode] = []
    var root: SVGNode?
    private var count = 0
    private var valid = true

    init(data: Data) {
        parser = XMLParser(data: data)
        super.init()
        parser.delegate = self
        parser.shouldResolveExternalEntities = false
    }
    func parse() -> Bool { parser.parse() && valid && stack.isEmpty }
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes: [String: String]) {
        count += 1
        guard count <= 10000, stack.count < 128 else { valid = false; parser.abortParsing(); return }
        let node = SVGNode(name: elementName, attributes: attributes)
        if let parent = stack.last { parent.children.append(node) }
        else if root == nil { root = node }
        else { valid = false; parser.abortParsing(); return }
        stack.append(node)
    }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if !stack.isEmpty { stack.removeLast() }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { stack.last?.text += string }
    func parser(_ parser: XMLParser, resolveExternalEntityName name: String, systemID: String?) -> Data? { nil }
}

private struct SVGGradient {
    let stops: [Gradient.Stop]
    let start: UnitPoint
    let end: UnitPoint

    init?(_ node: SVGNode) {
        guard node.name == "linearGradient" else { return nil }
        let stops = node.children.compactMap { child -> Gradient.Stop? in
            guard child.name == "stop" else { return nil }
            let style = SVGStyle.attributes(child.attributes)
            guard let color = SVGStyle.color(style["stop-color"] ?? "black") else { return nil }
            let offset = SVGGradient.fraction(style["offset"] ?? "0")
            let opacity = Double(style["stop-opacity"] ?? "1") ?? 1
            return .init(color: color.opacity(opacity), location: offset)
        }
        guard !stops.isEmpty else { return nil }
        self.stops = stops
        self.start = UnitPoint(x: Self.fraction(node.attributes["x1"] ?? "0"), y: Self.fraction(node.attributes["y1"] ?? "0"))
        self.end = UnitPoint(x: Self.fraction(node.attributes["x2"] ?? "100%"), y: Self.fraction(node.attributes["y2"] ?? "0"))
    }
    static func fraction(_ value: String) -> CGFloat {
        let percent = value.trimmingCharacters(in: .whitespaces).hasSuffix("%")
        let number = Double(value.replacingOccurrences(of: "%", with: "")) ?? 0
        return CGFloat(number / (percent ? 100 : 1))
    }
}

private struct SVGStyle {
    var fill = "black"
    var stroke = "none"
    var strokeWidth: CGFloat = 1
    var opacity: Double = 1
    var fillOpacity: Double = 1
    var strokeOpacity: Double = 1
    var lineCap: CGLineCap = .butt
    var lineJoin: CGLineJoin = .miter
    var fillRule: FillStyle = FillStyle()
    var hidden = false

    static func attributes(_ source: [String: String]) -> [String: String] {
        var values: [String: String] = [:]
        if let style = source["style"] {
            for pair in style.split(separator: ";") {
                let parts = pair.split(separator: ":", maxSplits: 1)
                if parts.count == 2 { values[String(parts[0]).trimmingCharacters(in: .whitespaces)] = String(parts[1]).trimmingCharacters(in: .whitespaces) }
            }
        }
        for (key, value) in source where key != "style" { values[key] = value }
        return values
    }

    func merging(_ source: [String: String]) -> Self {
        let values = Self.attributes(source)
        var result = self
        if let value = values["fill"] { result.fill = value }
        if let value = values["stroke"] { result.stroke = value }
        if let value = SVGNumbers.length(values["stroke-width"]) { result.strokeWidth = value }
        if let value = values["opacity"], let number = Double(value) { result.opacity *= number }
        if let value = values["fill-opacity"], let number = Double(value) { result.fillOpacity = number }
        if let value = values["stroke-opacity"], let number = Double(value) { result.strokeOpacity = number }
        if let value = values["stroke-linecap"] { result.lineCap = value == "round" ? .round : value == "square" ? .square : .butt }
        if let value = values["stroke-linejoin"] { result.lineJoin = value == "round" ? .round : value == "bevel" ? .bevel : .miter }
        if values["fill-rule"] == "evenodd" { result.fillRule = FillStyle(eoFill: true) }
        if values["display"] == "none" || values["visibility"] == "hidden" { result.hidden = true }
        return result
    }

    static func color(_ value: String) -> Color? {
        let value = value.trimmingCharacters(in: .whitespaces).lowercased()
        if value == "none" { return nil }
        if value.hasPrefix("#") {
            var hex = String(value.dropFirst())
            if hex.count == 3 || hex.count == 4 { hex = hex.map { "\($0)\($0)" }.joined() }
            guard hex.count == 6 || hex.count == 8, let n = UInt64(hex, radix: 16) else { return nil }
            let rgb = hex.count == 8 ? n >> 8 : n
            let alpha = hex.count == 8 ? Double(n & 255) / 255 : 1
            return Color(.sRGB, red: Double((rgb >> 16) & 255) / 255,
                         green: Double((rgb >> 8) & 255) / 255,
                         blue: Double(rgb & 255) / 255, opacity: alpha)
        }
        if value.hasPrefix("rgb(") || value.hasPrefix("rgba(") {
            let parts = value.drop(while: { $0 != "(" }).dropFirst().dropLast()
                .replacingOccurrences(of: ",", with: " ").split(whereSeparator: \.isWhitespace)
            guard parts.count >= 3 else { return nil }
            let channels = parts.prefix(3).map { part -> Double in
                let text = String(part)
                let number = Double(text.replacingOccurrences(of: "%", with: "")) ?? 0
                return text.hasSuffix("%") ? number / 100 : number / 255
            }
            let alpha = parts.count > 3 ? (Double(parts[3]) ?? 1) : 1
            return Color(.sRGB, red: channels[0], green: channels[1], blue: channels[2], opacity: alpha)
        }
        switch value {
        case "black": return .black
        case "white": return .white
        case "red": return .red
        case "green": return .green
        case "blue": return .blue
        case "gray", "grey": return .gray
        case "yellow": return .yellow
        case "orange": return .orange
        case "purple": return .purple
        case "transparent": return .clear
        default: return nil
        }
    }
}

struct SVGView: View {
    let svg: SVG
    func resizable() -> Self { self }

    var body: some View {
        Canvas { context, canvasSize in
            guard svg.viewBox.width > 0, svg.viewBox.height > 0 else { return }
            let scale = min(canvasSize.width / svg.viewBox.width, canvasSize.height / svg.viewBox.height)
            var context = context
            context.translateBy(x: (canvasSize.width - svg.viewBox.width * scale) / 2,
                                y: (canvasSize.height - svg.viewBox.height * scale) / 2)
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: -svg.viewBox.minX, y: -svg.viewBox.minY)
            for node in svg.nodes { draw(node, in: &context, style: SVGStyle()) }
        }
        .aspectRatio(svg.size, contentMode: .fit)
    }

    private func draw(_ node: SVGNode, in context: inout GraphicsContext, style inherited: SVGStyle) {
        if node.name == "defs" || node.name == "clipPath" || node.name == "mask" { return }
        let style = inherited.merging(node.attributes)
        guard !style.hidden else { return }
        var context = context
        if let transform = node.attributes["transform"] { context.transform = context.transform.concatenating(SVGTransforms.parse(transform)) }
        if let path = SVGPaths.path(for: node) {
            if style.fill != "none" {
                if let id = style.fill.replacingOccurrences(of: "url(#", with: "").split(separator: ")").first.map(String.init),
                   style.fill.hasPrefix("url(#"), let gradient = svg.gradients[id] {
                    let bounds = path.boundingRect
                    let start = CGPoint(x: bounds.minX + bounds.width * gradient.start.x, y: bounds.minY + bounds.height * gradient.start.y)
                    let end = CGPoint(x: bounds.minX + bounds.width * gradient.end.x, y: bounds.minY + bounds.height * gradient.end.y)
                    context.fill(path, with: .linearGradient(Gradient(stops: gradient.stops), startPoint: start, endPoint: end), style: style.fillRule)
                } else if let color = SVGStyle.color(style.fill) {
                    context.fill(path, with: .color(color.opacity(style.opacity * style.fillOpacity)), style: style.fillRule)
                }
            }
            if let color = SVGStyle.color(style.stroke), style.strokeWidth > 0 {
                context.stroke(path, with: .color(color.opacity(style.opacity * style.strokeOpacity)),
                               style: StrokeStyle(lineWidth: style.strokeWidth,
                                                  lineCap: style.lineCap == .round ? .round : style.lineCap == .square ? .square : .butt,
                                                  lineJoin: style.lineJoin == .round ? .round : style.lineJoin == .bevel ? .bevel : .miter))
            }
        }
        for child in node.children { draw(child, in: &context, style: style) }
    }
}

struct AsyncSVGView<Content: View>: View {
    let url: URL
    @ViewBuilder let content: (AsyncSVGPhase) -> Content
    @State private var phase: AsyncSVGPhase = .empty

    var body: some View {
        content(phase).task(id: url) {
            phase = .empty
            do {
                guard url.scheme == "https" || url.scheme == "http" else { phase = .failure; return }
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode),
                      let svg = SVG(data: data) else { phase = .failure; return }
                phase = .success(svg)
            } catch { phase = .failure }
        }
    }
}

enum AsyncSVGPhase {
    case empty, success(SVG), failure
}

private enum SVGTransforms {
    static func parse(_ value: String) -> CGAffineTransform {
        var result = CGAffineTransform.identity
        let pattern = #"([A-Za-z]+)\s*\(([^)]*)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return result }
        let ns = value as NSString
        for match in regex.matches(in: value, range: NSRange(location: 0, length: ns.length)) {
            let name = ns.substring(with: match.range(at: 1))
            let numbers = SVGNumbers.list(ns.substring(with: match.range(at: 2)))
            let transform: CGAffineTransform
            switch name {
            case "translate" where !numbers.isEmpty:
                transform = CGAffineTransform(translationX: numbers[0], y: numbers.count > 1 ? numbers[1] : 0)
            case "scale" where !numbers.isEmpty:
                transform = CGAffineTransform(scaleX: numbers[0], y: numbers.count > 1 ? numbers[1] : numbers[0])
            case "rotate" where !numbers.isEmpty:
                let angle = numbers[0] * .pi / 180
                if numbers.count >= 3 {
                    transform = CGAffineTransform(translationX: numbers[1], y: numbers[2])
                        .rotated(by: angle).translatedBy(x: -numbers[1], y: -numbers[2])
                } else { transform = CGAffineTransform(rotationAngle: angle) }
            case "matrix" where numbers.count >= 6:
                transform = CGAffineTransform(a: numbers[0], b: numbers[1], c: numbers[2], d: numbers[3], tx: numbers[4], ty: numbers[5])
            case "skewX" where !numbers.isEmpty:
                transform = CGAffineTransform(a: 1, b: 0, c: tan(numbers[0] * .pi / 180), d: 1, tx: 0, ty: 0)
            case "skewY" where !numbers.isEmpty:
                transform = CGAffineTransform(a: 1, b: tan(numbers[0] * .pi / 180), c: 0, d: 1, tx: 0, ty: 0)
            default: continue
            }
            result = result.concatenating(transform)
        }
        return result
    }
}

private enum SVGPaths {
    static func path(for node: SVGNode) -> Path? {
        let a = node.attributes
        func n(_ key: String) -> CGFloat { SVGNumbers.length(a[key]) ?? 0 }
        var path = Path()
        switch node.name {
        case "path": return SVGPathData.parse(a["d"] ?? "")
        case "rect":
            let rect = CGRect(x: n("x"), y: n("y"), width: n("width"), height: n("height"))
            guard rect.width > 0, rect.height > 0 else { return nil }
            let radius = max(n("rx"), n("ry"))
            return Path(roundedRect: rect, cornerRadius: radius)
        case "circle", "ellipse":
            let rx = node.name == "circle" ? n("r") : n("rx")
            let ry = node.name == "circle" ? n("r") : n("ry")
            guard rx > 0, ry > 0 else { return nil }
            return Path(ellipseIn: CGRect(x: n("cx") - rx, y: n("cy") - ry, width: 2 * rx, height: 2 * ry))
        case "line":
            path.move(to: CGPoint(x: n("x1"), y: n("y1")))
            path.addLine(to: CGPoint(x: n("x2"), y: n("y2")))
        case "polyline", "polygon":
            let points = SVGNumbers.list(a["points"] ?? "")
            guard points.count >= 4 else { return nil }
            path.move(to: CGPoint(x: points[0], y: points[1]))
            for i in stride(from: 2, to: points.count - 1, by: 2) { path.addLine(to: CGPoint(x: points[i], y: points[i + 1])) }
            if node.name == "polygon" { path.closeSubpath() }
        default: return nil
        }
        return path
    }
}

private enum SVGPathData {
    static func parse(_ data: String) -> Path? {
        let scanner = Scanner(string: data.replacingOccurrences(of: ",", with: " "))
        scanner.charactersToBeSkipped = .whitespacesAndNewlines
        var path = Path()
        var command: Character = " "
        var current = CGPoint.zero
        var start = CGPoint.zero
        var previousControl: CGPoint?
        var previousQuadratic: CGPoint?
        var steps = 0
        func number() -> CGFloat? { var value = 0.0; return scanner.scanDouble(&value) ? CGFloat(value) : nil }
        func point(relative: Bool) -> CGPoint? {
            guard let x = number(), let y = number() else { return nil }
            return CGPoint(x: x + (relative ? current.x : 0), y: y + (relative ? current.y : 0))
        }
        while !scanner.isAtEnd && steps < 100000 {
            steps += 1
            if let next = scanner.scanCharacters(from: .letters)?.first { command = next }
            else if command == " " { return nil }
            let oldIndex = scanner.currentIndex
            let relative = command.isLowercase
            let op = command.uppercased()
            switch op {
            case "M":
                guard let end = point(relative: relative) else { return nil }
                path.move(to: end); current = end; start = end
                command = relative ? "l" : "L"
            case "L":
                guard let end = point(relative: relative) else { return nil }
                path.addLine(to: end); current = end
            case "H":
                guard let x = number() else { return nil }
                current.x = x + (relative ? current.x : 0); path.addLine(to: current)
            case "V":
                guard let y = number() else { return nil }
                current.y = y + (relative ? current.y : 0); path.addLine(to: current)
            case "C":
                guard let c1 = point(relative: relative), let c2 = point(relative: relative),
                      let end = point(relative: relative) else { return nil }
                path.addCurve(to: end, control1: c1, control2: c2)
                current = end; previousControl = c2
            case "S":
                guard let c2 = point(relative: relative), let end = point(relative: relative) else { return nil }
                let c1 = previousControl.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
                path.addCurve(to: end, control1: c1, control2: c2)
                current = end; previousControl = c2
            case "Q":
                guard let control = point(relative: relative), let end = point(relative: relative) else { return nil }
                path.addQuadCurve(to: end, control: control)
                current = end; previousQuadratic = control
            case "T":
                guard let end = point(relative: relative) else { return nil }
                let control = previousQuadratic.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
                path.addQuadCurve(to: end, control: control)
                current = end; previousQuadratic = control
            case "Z":
                path.closeSubpath(); current = start; command = " "
            default: return nil
            }
            if op != "C" && op != "S" { previousControl = nil }
            if op != "Q" && op != "T" { previousQuadratic = nil }
            if scanner.currentIndex == oldIndex && op != "Z" { return nil }
        }
        return steps < 100000 ? path : nil
    }
}
