import CoreGraphics
import Foundation
import ImageIO
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
    fileprivate let definitions: [String: SVGNode]
    fileprivate let cssRules: [SVGRule]
    fileprivate let preserveAspectRatio: String
    fileprivate let externalImages: [String: URL]
    let sourceData: Data
    let baseURL: URL?
    let needsWebKit: Bool

    init?(data: Data, baseURL: URL? = nil) {
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
        self.sourceData = data
        self.baseURL = baseURL
        self.needsWebKit = SVGCompatibility.requiresWebKit(root)
        self.viewBox = viewBox.width > 0 ? viewBox : CGRect(origin: .zero, size: size)
        self.preserveAspectRatio = root.attributes["preserveAspectRatio"] ?? "xMidYMid meet"
        self.nodes = root.children
        var gradients: [String: SVGGradient] = [:]
        var definitions: [String: SVGNode] = [:]
        root.walk { node in
            if let id = node.attributes["id"] {
                definitions[id] = node
            }
        }
        for (id, node) in definitions {
            if let gradient = SVGGradient(node, definitions: definitions, visiting: [id]) { gradients[id] = gradient }
        }
        self.gradients = gradients
        self.definitions = definitions
        self.cssRules = root.children.filter { $0.name == "style" }.flatMap { SVGRule.parse($0.text) }
        var externalImages: [String: URL] = [:]
        root.walk { node in
            guard node.name == "image", let href = node.attributes["href"] ?? node.attributes["xlink:href"],
                  !href.hasPrefix("data:"), let baseURL,
                  let url = URL(string: href, relativeTo: baseURL)?.absoluteURL else { return }
            if url.scheme == "https" || url.scheme == "http" ||
                (url.isFileURL && baseURL.isFileURL && url.path.hasPrefix(baseURL.deletingLastPathComponent().path + "/")) {
                externalImages[href] = url
            }
        }
        self.externalImages = externalImages
    }

    init?(named name: String, in bundle: Bundle) {
        let path = name as NSString
        let resource = path.deletingPathExtension
        let ext = path.pathExtension.isEmpty ? "svg" : path.pathExtension
        guard let url = bundle.url(forResource: resource, withExtension: ext),
              let data = try? Data(contentsOf: url) else { return nil }
        self.init(data: data, baseURL: url)
    }
}

private enum SVGCompatibility {
    static func requiresWebKit(_ root: SVGNode) -> Bool {
        let known: Set<String> = ["svg", "g", "defs", "path", "rect", "circle", "ellipse", "line",
                                  "polyline", "polygon", "text", "tspan", "style", "linearGradient",
                                  "radialGradient", "stop", "use", "image", "clipPath", "mask", "pattern",
                                  "filter", "feGaussianBlur", "title", "desc", "metadata"]
        let attributes: Set<String> = ["xmlns", "xmlns:xlink", "version", "id", "class", "style", "viewBox",
                                       "preserveAspectRatio", "width", "height", "x", "y", "x1", "y1", "x2",
                                       "y2", "cx", "cy", "r", "rx", "ry", "points", "d", "fill", "stroke",
                                       "stroke-width", "stroke-linecap", "stroke-linejoin", "fill-rule",
                                       "opacity", "fill-opacity", "stroke-opacity", "display", "visibility",
                                       "transform", "gradientTransform", "gradientUnits", "href", "xlink:href",
                                       "offset", "stop-color", "stop-opacity", "fx", "fy", "fr", "patternUnits",
                                       "patternContentUnits", "clip-path", "mask", "filter", "stdDeviation",
                                       "font-family", "font-size", "text-anchor", "dx", "dy", "xml:space"]
        let supportedStyle: Set<String> = ["fill", "stroke", "stroke-width", "stroke-linecap",
                                           "stroke-linejoin", "fill-rule", "opacity", "fill-opacity",
                                           "stroke-opacity", "display", "visibility", "font-family",
                                           "font-size", "text-anchor", "stop-color", "stop-opacity",
                                           "clip-path", "mask", "filter"]
        var complex = false
        root.walk { node in
            if !known.contains(node.name) || node.attributes.keys.contains(where: { !attributes.contains($0) }) {
                complex = true
            }
            // These features render more faithfully in WebKit than the bounded Canvas fast path.
            if ["style", "text", "tspan", "linearGradient", "radialGradient", "clipPath",
                "mask", "pattern", "filter"].contains(node.name) { complex = true }
            if node.name == "style" {
                if node.text.contains("@font-face") || node.text.contains("@import") ||
                    node.text.contains("@media") || node.text.contains("url(") { complex = true }
                if SVGRule.parse(node.text).contains(where: { !$0.declarations.keys.allSatisfy(supportedStyle.contains) }) {
                    complex = true
                }
            }
            if !SVGStyle.declarations(node.attributes["style"] ?? "").keys.allSatisfy(supportedStyle.contains) {
                complex = true
            }
            if node.attributes["patternTransform"] != nil || node.attributes["clipPathUnits"] != nil ||
                node.attributes["maskUnits"] != nil || node.attributes["maskContentUnits"] != nil {
                complex = true
            }
            if node.name == "path", SVGPathData.parse(node.attributes["d"] ?? "") == nil { complex = true }
            if node.name == "filter" && node.children.contains(where: { $0.name != "feGaussianBlur" }) { complex = true }
            for key in ["fill", "stroke", "stop-color"] {
                guard let color = node.attributes[key], color != "none", !color.hasPrefix("url(#") else { continue }
                if SVGStyle.color(color) == nil { complex = true }
            }
        }
        return complex
    }
}

private enum SVGNumbers {
    static func list(_ value: String) -> [CGFloat] {
        let scanner = Scanner(string: value.replacingOccurrences(of: ",", with: " "))
        scanner.charactersToBeSkipped = .whitespacesAndNewlines
        var result: [CGFloat] = []
        while !scanner.isAtEnd {
            if let number = scanner.scanDouble() { result.append(CGFloat(number)) }
            else { _ = scanner.scanCharacter() }
        }
        return result
    }

    static func length(_ value: String?) -> CGFloat? {
        guard let value else { return nil }
        let scanner = Scanner(string: value.trimmingCharacters(in: .whitespacesAndNewlines))
        guard let number = scanner.scanDouble(), number.isFinite else { return nil }
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

private enum SVGContent {
    case text(String)
    case node(SVGNode)
}

private final class SVGNode {
    let name: String
    let attributes: [String: String]
    var children: [SVGNode] = []
    var content: [SVGContent] = []
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
        let node = SVGNode(name: String(elementName.split(separator: ":").last ?? Substring(elementName)),
                           attributes: attributes)
        if let parent = stack.last { parent.children.append(node); parent.content.append(.node(node)) }
        else if root == nil { root = node }
        else { valid = false; parser.abortParsing(); return }
        stack.append(node)
    }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if !stack.isEmpty { stack.removeLast() }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard let node = stack.last else { return }
        node.text += string
        if case let .text(previous)? = node.content.last {
            node.content[node.content.count - 1] = .text(previous + string)
        } else { node.content.append(.text(string)) }
    }
    func parser(_ parser: XMLParser, resolveExternalEntityName name: String, systemID: String?) -> Data? { nil }
}

private struct SVGRule {
    let selector: String
    let declarations: [String: String]

    static func parse(_ source: String) -> [Self] {
        guard let regex = try? NSRegularExpression(pattern: #"([^{}]+)\{([^}]*)\}"#) else { return [] }
        let ns = source as NSString
        return regex.matches(in: source, range: NSRange(location: 0, length: ns.length)).flatMap { match in
            let declarations = SVGStyle.declarations(ns.substring(with: match.range(at: 2)))
            return ns.substring(with: match.range(at: 1)).split(separator: ",").map {
                Self(selector: $0.trimmingCharacters(in: .whitespacesAndNewlines), declarations: declarations)
            }
        }
    }

    func matches(_ node: SVGNode) -> Bool {
        if selector.hasPrefix("#") { return node.attributes["id"] == String(selector.dropFirst()) }
        if selector.hasPrefix(".") { return (node.attributes["class"] ?? "").split(separator: " ").contains(Substring(selector.dropFirst())) }
        if let dot = selector.firstIndex(of: ".") {
            return node.name == String(selector[..<dot]) &&
                (node.attributes["class"] ?? "").split(separator: " ").contains(Substring(selector[selector.index(after: dot)...]))
        }
        return node.name == selector
    }
}

private struct SVGGradient {
    let stops: [Gradient.Stop]
    let radial: Bool
    let units: String
    let transform: CGAffineTransform
    let x1: String
    let y1: String
    let x2: String
    let y2: String
    let cx: String
    let cy: String
    let r: String
    let fr: String
    let fx: String
    let fy: String

    init?(_ node: SVGNode, definitions: [String: SVGNode], visiting: Set<String>) {
        guard node.name == "linearGradient" || node.name == "radialGradient" else { return nil }
        let radial = node.name == "radialGradient"
        let href = node.attributes["href"] ?? node.attributes["xlink:href"] ?? ""
        let referenceID = href.hasPrefix("#") ? String(href.dropFirst()) : ""
        let parent: SVGGradient? = !referenceID.isEmpty && !visiting.contains(referenceID)
            ? definitions[referenceID].flatMap { SVGGradient($0, definitions: definitions,
                                                               visiting: visiting.union([referenceID])) } : nil
        let localStops = node.children.compactMap { child -> Gradient.Stop? in
            guard child.name == "stop" else { return nil }
            let style = SVGStyle.attributes(child.attributes)
            guard let color = SVGStyle.color(style["stop-color"] ?? "black") else { return nil }
            let offset = Self.fraction(style["offset"] ?? "0")
            let opacity = Double(style["stop-opacity"] ?? "1") ?? 1
            return .init(color: color.opacity(opacity), location: offset)
        }
        let stops = localStops.isEmpty ? parent?.stops ?? [] : localStops
        guard !stops.isEmpty else { return nil }
        self.stops = stops
        self.radial = radial
        self.units = node.attributes["gradientUnits"] ?? parent?.units ?? "objectBoundingBox"
        self.transform = SVGTransforms.parse(node.attributes["gradientTransform"] ?? "")
            .concatenating(parent?.transform ?? .identity)
        self.x1 = node.attributes["x1"] ?? parent?.x1 ?? "0%"
        self.y1 = node.attributes["y1"] ?? parent?.y1 ?? "0%"
        self.x2 = node.attributes["x2"] ?? parent?.x2 ?? "100%"
        self.y2 = node.attributes["y2"] ?? parent?.y2 ?? "0%"
        self.cx = node.attributes["cx"] ?? parent?.cx ?? "50%"
        self.cy = node.attributes["cy"] ?? parent?.cy ?? "50%"
        self.r = node.attributes["r"] ?? parent?.r ?? "50%"
        self.fr = node.attributes["fr"] ?? parent?.fr ?? "0%"
        self.fx = node.attributes["fx"] ?? parent?.fx ?? self.cx
        self.fy = node.attributes["fy"] ?? parent?.fy ?? self.cy
    }

    static func fraction(_ value: String) -> CGFloat {
        let percent = value.trimmingCharacters(in: .whitespaces).hasSuffix("%")
        let number = Double(value.replacingOccurrences(of: "%", with: "")) ?? 0
        return CGFloat(number / (percent ? 100 : 1))
    }

    func coordinate(_ raw: String, horizontal: Bool, bounds: CGRect, viewport: CGRect) -> CGFloat {
        let isPercent = raw.hasSuffix("%")
        let fraction = Self.fraction(raw)
        if units == "userSpaceOnUse" {
            return isPercent ? (horizontal ? viewport.width : viewport.height) * fraction
                + (horizontal ? viewport.minX : viewport.minY) : SVGNumbers.length(raw) ?? fraction
        }
        return (horizontal ? bounds.minX + bounds.width * fraction : bounds.minY + bounds.height * fraction)
    }

    func drawRadial(path: Path, bounds: CGRect, viewport: CGRect,
                    opacity: Double, in context: inout GraphicsContext) {
        let colors: [CGColor] = stops.map { stop in
            let resolved = stop.color.resolve(in: EnvironmentValues())
            return CGColor(red: CGFloat(resolved.red), green: CGFloat(resolved.green),
                           blue: CGFloat(resolved.blue), alpha: CGFloat(resolved.opacity) * opacity)
        }
        let locations = stops.map(\.location)
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                        colors: colors as CFArray, locations: locations) else { return }
        let objectBox = units != "userSpaceOnUse"
        let radiusFraction = Self.fraction(r)
        let rx = objectBox ? bounds.width * radiusFraction :
            (r.hasSuffix("%") ? viewport.width * radiusFraction : SVGNumbers.length(r) ?? 0)
        let ry = objectBox ? bounds.height * radiusFraction : rx
        guard rx > 0, ry > 0 else { return }
        let center = CGPoint(x: coordinate(cx, horizontal: true, bounds: bounds, viewport: viewport),
                             y: coordinate(cy, horizontal: false, bounds: bounds, viewport: viewport))
        let focal = CGPoint(x: coordinate(fx, horizontal: true, bounds: bounds, viewport: viewport),
                            y: coordinate(fy, horizontal: false, bounds: bounds, viewport: viewport))
        let firstRadius = objectBox ? min(bounds.width, bounds.height) * Self.fraction(fr) :
            (fr.hasSuffix("%") ? viewport.width * Self.fraction(fr) : SVGNumbers.length(fr) ?? 0)
        context.withCGContext { cg in
            cg.saveGState()
            cg.addPath(path.cgPath)
            cg.clip()
            cg.translateBy(x: center.x, y: center.y)
            cg.concatenate(transform)
            cg.scaleBy(x: rx, y: ry)
            let start = CGPoint(x: (focal.x - center.x) / rx, y: (focal.y - center.y) / ry)
            cg.drawRadialGradient(gradient, startCenter: start,
                                  startRadius: firstRadius / max(rx, ry),
                                  endCenter: .zero, endRadius: 1,
                                  options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            cg.restoreGState()
        }
    }

    func shading(bounds: CGRect, viewport: CGRect) -> GraphicsContext.Shading {
        let gradient = Gradient(stops: stops)
        if radial {
            let center = CGPoint(x: coordinate(cx, horizontal: true, bounds: bounds, viewport: viewport),
                                 y: coordinate(cy, horizontal: false, bounds: bounds, viewport: viewport))
                .applying(transform)
            let radius = units == "userSpaceOnUse" ?
                (r.hasSuffix("%") ? max(viewport.width, viewport.height) * Self.fraction(r) : SVGNumbers.length(r) ?? 0) :
                max(bounds.width, bounds.height) * Self.fraction(r)
            let firstRadius = units == "userSpaceOnUse" ?
                (fr.hasSuffix("%") ? max(viewport.width, viewport.height) * Self.fraction(fr) : SVGNumbers.length(fr) ?? 0) :
                max(bounds.width, bounds.height) * Self.fraction(fr)
            return .radialGradient(gradient, center: center, startRadius: firstRadius,
                                   endRadius: radius * hypot(transform.a, transform.b))
        }
        let start = CGPoint(x: coordinate(x1, horizontal: true, bounds: bounds, viewport: viewport),
                            y: coordinate(y1, horizontal: false, bounds: bounds, viewport: viewport))
            .applying(transform)
        let end = CGPoint(x: coordinate(x2, horizontal: true, bounds: bounds, viewport: viewport),
                          y: coordinate(y2, horizontal: false, bounds: bounds, viewport: viewport))
            .applying(transform)
        return .linearGradient(gradient, startPoint: start, endPoint: end)
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
    var fontSize: CGFloat = 16
    var fontFamily: String?
    var textAnchor = "start"

    static func declarations(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        for pair in text.split(separator: ";") {
            let parts = pair.split(separator: ":", maxSplits: 1)
            if parts.count == 2 {
                result[String(parts[0]).trimmingCharacters(in: .whitespaces)] =
                    String(parts[1]).trimmingCharacters(in: .whitespaces)
            }
        }
        return result
    }

    static func attributes(_ source: [String: String]) -> [String: String] {
        var values = source
        values.removeValue(forKey: "style")
        for (key, value) in declarations(source["style"] ?? "") { values[key] = value }
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
        if let value = SVGNumbers.length(values["font-size"]), value > 0 { result.fontSize = value }
        if let value = values["font-family"] { result.fontFamily = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"' ")) }
        if let value = values["text-anchor"] { result.textAnchor = value }
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
        case "black": return Color(.sRGB, red: 0, green: 0, blue: 0, opacity: 1)
        case "white": return Color(.sRGB, red: 1, green: 1, blue: 1, opacity: 1)
        case "red": return Color(.sRGB, red: 1, green: 0, blue: 0, opacity: 1)
        case "green": return Color(.sRGB, red: 0, green: 128 / 255, blue: 0, opacity: 1)
        case "blue": return Color(.sRGB, red: 0, green: 0, blue: 1, opacity: 1)
        case "gray", "grey": return Color(.sRGB, red: 128 / 255, green: 128 / 255, blue: 128 / 255, opacity: 1)
        case "yellow": return Color(.sRGB, red: 1, green: 1, blue: 0, opacity: 1)
        case "orange": return Color(.sRGB, red: 1, green: 165 / 255, blue: 0, opacity: 1)
        case "purple": return Color(.sRGB, red: 128 / 255, green: 0, blue: 128 / 255, opacity: 1)
        case "transparent": return Color(.sRGB, red: 0, green: 0, blue: 0, opacity: 0)
        default: return nil
        }
    }
}

struct SVGView: View {
    let svg: SVG
    let forceNative: Bool
    @State private var loadedImages: [String: CGImage] = [:]
    func resizable() -> Self { self }

    init(svg: SVG, forceNative: Bool = false) {
        self.svg = svg
        self.forceNative = forceNative
    }

    var body: some View {
        Group {
            if svg.needsWebKit && !forceNative {
                SVGWebKitView(svg: svg)
            } else {
                nativeCanvas
            }
        }
        .aspectRatio(svg.size, contentMode: .fit)
    }

    private var nativeCanvas: some View {
        Canvas { context, canvasSize in
            guard svg.viewBox.width > 0, svg.viewBox.height > 0 else { return }
            var context = context
            let viewport = CGRect(origin: .zero, size: canvasSize)
            context.transform = context.transform.concatenating(
                SVGViewport.transform(viewBox: svg.viewBox, viewport: viewport,
                                      preserveAspectRatio: svg.preserveAspectRatio))
            for node in svg.nodes { draw(node, in: &context, style: SVGStyle()) }
        }
        .task {
            for (href, url) in svg.externalImages {
                if Task.isCancelled { return }
                if let image = await SVGExternalImageLoader.fetch(url) { loadedImages[href] = image }
            }
        }
    }

    private func draw(_ node: SVGNode, in context: inout GraphicsContext, style inherited: SVGStyle,
                      visiting: Set<String> = []) {
        if node.name == "defs" || node.name == "clipPath" || node.name == "mask" { return }
        var cascaded = node.attributes
        let inline = SVGStyle.declarations(node.attributes["style"] ?? "")
        for rule in svg.cssRules where rule.matches(node) {
            for (key, value) in rule.declarations { cascaded[key] = value }
        }
        for (key, value) in inline { cascaded[key] = value }
        let style = inherited.merging(cascaded)
        guard !style.hidden else { return }
        var context = context
        if let transform = node.attributes["transform"] { context.transform = context.transform.concatenating(SVGTransforms.parse(transform)) }
        let attributes = SVGStyle.attributes(cascaded)
        if let clipID = SVGView.fragmentID(attributes["clip-path"]),
           let clip = svg.definitions[clipID], clip.name == "clipPath" {
            var shape = Path()
            for child in clip.children {
                if let childPath = SVGPaths.path(for: child) {
                    shape.addPath(childPath, transform: SVGTransforms.parse(child.attributes["transform"] ?? ""))
                }
            }
            context.clip(to: shape)
        }
        if let maskID = SVGView.fragmentID(attributes["mask"]),
           let mask = svg.definitions[maskID], mask.name == "mask" {
            context.clipToLayer { layer in
                layer.addFilter(.luminanceToAlpha)
                for child in mask.children { draw(child, in: &layer, style: SVGStyle()) }
            }
        }
        if let filterID = SVGView.fragmentID(attributes["filter"]),
           let filter = svg.definitions[filterID], filter.name == "filter",
           let blur = filter.children.first(where: { $0.name == "feGaussianBlur" }),
           let deviation = SVGNumbers.length(blur.attributes["stdDeviation"]), deviation > 0 {
            context.addFilter(.blur(radius: deviation))
        }
        if node.name == "svg" {
            let viewport = CGRect(x: SVGNumbers.length(node.attributes["x"]) ?? 0,
                                  y: SVGNumbers.length(node.attributes["y"]) ?? 0,
                                  width: SVGNumbers.length(node.attributes["width"]) ?? svg.size.width,
                                  height: SVGNumbers.length(node.attributes["height"]) ?? svg.size.height)
            let boxValues = SVGNumbers.list(node.attributes["viewBox"] ?? "")
            let box = boxValues.count == 4 && boxValues[2] > 0 && boxValues[3] > 0
                ? CGRect(x: boxValues[0], y: boxValues[1], width: boxValues[2], height: boxValues[3])
                : CGRect(origin: .zero, size: viewport.size)
            guard viewport.width > 0, viewport.height > 0 else { return }
            context.clip(to: Path(viewport))
            context.transform = context.transform.concatenating(
                SVGViewport.transform(viewBox: box, viewport: viewport,
                                      preserveAspectRatio: node.attributes["preserveAspectRatio"] ?? "xMidYMid meet"))
            for child in node.children { draw(child, in: &context, style: style, visiting: visiting) }
            return
        }
        if node.name == "use" {
            let href = node.attributes["href"] ?? node.attributes["xlink:href"] ?? ""
            if href.hasPrefix("#") {
                let id = String(href.dropFirst())
                if !visiting.contains(id), let referenced = svg.definitions[id] {
                    context.translateBy(x: SVGNumbers.length(node.attributes["x"]) ?? 0,
                                        y: SVGNumbers.length(node.attributes["y"]) ?? 0)
                    draw(referenced, in: &context, style: style, visiting: visiting.union([id]))
                }
            }
            return
        }
        if node.name == "image" { drawImage(node, in: &context); return }
        if node.name == "text" { drawText(node, in: &context, style: style); return }
        if let path = SVGPaths.path(for: node) {
            if style.fill != "none" {
                if let id = SVGView.fragmentID(style.fill), !visiting.contains(id),
                   let pattern = svg.definitions[id], pattern.name == "pattern",
                   let rawWidth = pattern.attributes["width"],
                   let rawHeight = pattern.attributes["height"] {
                    let bounds = path.boundingRect
                    let objectBox = pattern.attributes["patternUnits"] != "userSpaceOnUse"
                    let tileWidth = objectBox ? bounds.width * SVGGradient.fraction(rawWidth) : SVGNumbers.length(rawWidth) ?? 0
                    let tileHeight = objectBox ? bounds.height * SVGGradient.fraction(rawHeight) : SVGNumbers.length(rawHeight) ?? 0
                    if tileWidth > 0, tileHeight > 0 {
                        var patterned = context
                        patterned.clip(to: path, style: style.fillRule)
                        let offsetX = objectBox ? bounds.minX + bounds.width * SVGGradient.fraction(pattern.attributes["x"] ?? "0") : SVGNumbers.length(pattern.attributes["x"]) ?? 0
                        let offsetY = objectBox ? bounds.minY + bounds.height * SVGGradient.fraction(pattern.attributes["y"] ?? "0") : SVGNumbers.length(pattern.attributes["y"]) ?? 0
                        let firstX = floor((bounds.minX - offsetX) / tileWidth) * tileWidth + offsetX
                        let firstY = floor((bounds.minY - offsetY) / tileHeight) * tileHeight + offsetY
                        let cols = min(128, max(0, Int(ceil((bounds.maxX - firstX) / tileWidth))))
                        let rows = min(128, max(0, Int(ceil((bounds.maxY - firstY) / tileHeight))))
                        if cols * rows <= 2048 {
                            for row in 0..<rows {
                                for col in 0..<cols {
                                    var tile = patterned
                                    tile.translateBy(x: firstX + CGFloat(col) * tileWidth,
                                                     y: firstY + CGFloat(row) * tileHeight)
                                    if pattern.attributes["patternContentUnits"] == "objectBoundingBox" {
                                        tile.scaleBy(x: bounds.width, y: bounds.height)
                                    }
                                    for child in pattern.children {
                                        draw(child, in: &tile, style: SVGStyle(), visiting: visiting.union([id]))
                                    }
                                }
                            }
                        }
                    }
                } else if let id = SVGView.fragmentID(style.fill), let gradient = svg.gradients[id] {
                    if gradient.radial {
                        gradient.drawRadial(path: path, bounds: path.boundingRect, viewport: svg.viewBox,
                                            opacity: style.opacity * style.fillOpacity, in: &context)
                    } else {
                        context.fill(path, with: gradient.shading(bounds: path.boundingRect, viewport: svg.viewBox),
                                     style: style.fillRule)
                    }
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
        for child in node.children { draw(child, in: &context, style: style, visiting: visiting) }
    }

    private static func fragmentID(_ value: String?) -> String? {
        guard let value, value.hasPrefix("url(#"), value.hasSuffix(")") else { return nil }
        return String(value.dropFirst(5).dropLast())
    }

    private func drawText(_ node: SVGNode, in context: inout GraphicsContext, style: SVGStyle) {
        var cursor = CGPoint(x: SVGNumbers.length(node.attributes["x"]) ?? 0,
                             y: SVGNumbers.length(node.attributes["y"]) ?? 0)
        let anchorX: CGFloat = style.textAnchor == "middle" ? 0.5 : style.textAnchor == "end" ? 1 : 0
        let fullText = node.content.map { item -> String in
            switch item { case let .text(value): value; case let .node(child): child.text }
        }.joined()
        if anchorX > 0 {
            let font: Font = style.fontFamily.map { .custom($0, size: style.fontSize) } ?? .system(size: style.fontSize)
            let width = context.resolve(Text(fullText).font(font)).measure(in: CGSize(width: 100_000, height: 100_000)).width
            cursor.x -= width * anchorX
        }
        drawTextContent(node, in: &context, style: style, cursor: &cursor, applyPosition: false)
    }

    private func drawTextContent(_ node: SVGNode, in context: inout GraphicsContext,
                                 style: SVGStyle, cursor: inout CGPoint,
                                 applyPosition: Bool = true) {
        let style = style.merging(node.attributes)
        if applyPosition {
            if let x = SVGNumbers.length(node.attributes["x"]) { cursor.x = x }
            if let y = SVGNumbers.length(node.attributes["y"]) { cursor.y = y }
            cursor.x += SVGNumbers.length(node.attributes["dx"]) ?? 0
            cursor.y += SVGNumbers.length(node.attributes["dy"]) ?? 0
        }
        guard let color = SVGStyle.color(style.fill) else { return }
        let font: Font = style.fontFamily.map { .custom($0, size: style.fontSize) } ?? .system(size: style.fontSize)
        for item in node.content {
            switch item {
            case let .text(value):
                guard !value.isEmpty else { continue }
                let text = Text(value).font(font).foregroundColor(color.opacity(style.opacity * style.fillOpacity))
                let resolved = context.resolve(text)
                context.draw(resolved, at: cursor, anchor: .bottomLeading)
                cursor.x += resolved.measure(in: CGSize(width: 100_000, height: 100_000)).width
            case let .node(child) where child.name == "tspan":
                drawTextContent(child, in: &context, style: style, cursor: &cursor)
            case .node: break
            }
        }
    }

    private func drawImage(_ node: SVGNode, in context: inout GraphicsContext) {
        let a = node.attributes
        let href = a["href"] ?? a["xlink:href"] ?? ""
        let image: CGImage?
        if href.hasPrefix("data:image/"), let comma = href.firstIndex(of: ","),
           href[..<comma].lowercased().hasSuffix(";base64"),
           let data = Data(base64Encoded: String(href[href.index(after: comma)...])),
           data.count <= 2 * 1024 * 1024,
           let source = CGImageSourceCreateWithData(data as CFData, nil) {
            image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        } else {
            image = loadedImages[href]
        }
        guard let image,
              let width = SVGNumbers.length(a["width"]), let height = SVGNumbers.length(a["height"]),
              width > 0, height > 0 else { return }
        var rect = CGRect(x: SVGNumbers.length(a["x"]) ?? 0,
                          y: SVGNumbers.length(a["y"]) ?? 0, width: width, height: height)
        if a["preserveAspectRatio"] != "none" {
            let ratio = min(width / CGFloat(image.width), height / CGFloat(image.height))
            let fitted = CGSize(width: CGFloat(image.width) * ratio, height: CGFloat(image.height) * ratio)
            rect = CGRect(x: rect.midX - fitted.width / 2, y: rect.midY - fitted.height / 2,
                          width: fitted.width, height: fitted.height)
        }
        context.draw(Image(decorative: image, scale: 1), in: rect)
    }
}

private final class SVGImageBox: NSObject {
    let image: CGImage
    init(_ image: CGImage) { self.image = image }
}

enum SVGExternalImageLoader {
    private static let cache: NSCache<NSURL, SVGImageBox> = {
        let cache = NSCache<NSURL, SVGImageBox>()
        cache.totalCostLimit = 32 * 1024 * 1024
        return cache
    }()
    static func fetch(_ url: URL, session: URLSession = .shared) async -> CGImage? {
        if let cached = cache.object(forKey: url as NSURL) { return cached.image }
        guard url.scheme == "https" || url.scheme == "http" || url.isFileURL else { return nil }
        let data: Data
        if url.isFileURL {
            guard let file = try? Data(contentsOf: url), file.count <= 2 * 1024 * 1024 else { return nil }
            data = file
        } else {
            do {
                let (bytes, response) = try await session.bytes(for: URLRequest(url: url, timeoutInterval: 20))
                guard let response = response as? HTTPURLResponse,
                      (200..<300).contains(response.statusCode),
                      response.expectedContentLength <= 2 * 1024 * 1024 else { return nil }
                var received = Data()
                for try await byte in bytes {
                    guard received.count < 2 * 1024 * 1024 else { bytes.task.cancel(); return nil }
                    received.append(byte)
                }
                data = received
            } catch { return nil }
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as NSDictionary?,
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 8192, height <= 8192,
              width * height <= 16_000_000,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        cache.setObject(SVGImageBox(image), forKey: url as NSURL, cost: width * height * 4)
        return image
    }
}

private enum SVGViewport {
    static func transform(viewBox: CGRect, viewport: CGRect, preserveAspectRatio: String) -> CGAffineTransform {
        guard viewBox.width > 0, viewBox.height > 0 else { return .identity }
        let parts = preserveAspectRatio.split(separator: " ").map(String.init)
        let alignment = parts.first == "defer" ? (parts.dropFirst().first ?? "xMidYMid") : (parts.first ?? "xMidYMid")
        let xScale = viewport.width / viewBox.width
        let yScale = viewport.height / viewBox.height
        if alignment == "none" {
            return CGAffineTransform(a: xScale, b: 0, c: 0, d: yScale,
                                     tx: viewport.minX - viewBox.minX * xScale,
                                     ty: viewport.minY - viewBox.minY * yScale)
        }
        let scale = parts.contains("slice") ? max(xScale, yScale) : min(xScale, yScale)
        let unusedX = viewport.width - viewBox.width * scale
        let unusedY = viewport.height - viewBox.height * scale
        let x: CGFloat = alignment.contains("xMax") ? unusedX : alignment.contains("xMid") ? unusedX / 2 : 0
        let y: CGFloat = alignment.contains("YMax") ? unusedY : alignment.contains("YMid") ? unusedY / 2 : 0
        return CGAffineTransform(a: scale, b: 0, c: 0, d: scale,
                                 tx: viewport.minX + x - viewBox.minX * scale,
                                 ty: viewport.minY + y - viewBox.minY * scale)
    }
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

enum SVGPathData {
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
        func number() -> CGFloat? { scanner.scanDouble().map { CGFloat($0) } }
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
            case "A":
                guard let rx = number(), let ry = number(), let rotation = number(),
                      let large = number(), let sweep = number(),
                      let end = point(relative: relative) else { return nil }
                addArc(to: end, from: current, rx: rx, ry: ry,
                       rotation: rotation, large: large != 0, sweep: sweep != 0, to: &path)
                current = end
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

    /// SVG endpoint arc conversion, split into cubic segments of at most 90 degrees.
    private static func addArc(to end: CGPoint, from start: CGPoint, rx rawRX: CGFloat, ry rawRY: CGFloat,
                               rotation: CGFloat, large: Bool, sweep: Bool, to path: inout Path) {
        var rx = abs(rawRX), ry = abs(rawRY)
        guard rx > 0, ry > 0, start != end else { path.addLine(to: end); return }
        let phi = rotation * .pi / 180
        let cosPhi = cos(phi), sinPhi = sin(phi)
        let dx = (start.x - end.x) / 2, dy = (start.y - end.y) / 2
        let x1 = cosPhi * dx + sinPhi * dy
        let y1 = -sinPhi * dx + cosPhi * dy
        let needed = sqrt(x1 * x1 / (rx * rx) + y1 * y1 / (ry * ry))
        if needed > 1 { rx *= needed; ry *= needed }
        let numerator = max(0, rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1)
        let denominator = rx * rx * y1 * y1 + ry * ry * x1 * x1
        guard denominator > 0 else { path.addLine(to: end); return }
        let sign: CGFloat = large == sweep ? -1 : 1
        let factor = sign * sqrt(numerator / denominator)
        let cx1 = factor * rx * y1 / ry
        let cy1 = factor * -ry * x1 / rx
        let cx = cosPhi * cx1 - sinPhi * cy1 + (start.x + end.x) / 2
        let cy = sinPhi * cx1 + cosPhi * cy1 + (start.y + end.y) / 2
        let startAngle = atan2((y1 - cy1) / ry, (x1 - cx1) / rx)
        var delta = atan2((-y1 - cy1) / ry, (-x1 - cx1) / rx) - startAngle
        if sweep && delta < 0 { delta += 2 * .pi }
        if !sweep && delta > 0 { delta -= 2 * .pi }
        let segments = min(64, max(1, Int(ceil(abs(delta) / (.pi / 2)))))
        let step = delta / CGFloat(segments)
        func project(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: cx + rx * cosPhi * x - ry * sinPhi * y,
                    y: cy + rx * sinPhi * x + ry * cosPhi * y)
        }
        for i in 0..<segments {
            let a = startAngle + CGFloat(i) * step
            let b = a + step
            let k = 4 / 3 * tan((b - a) / 4)
            let c1 = project(cos(a) - k * sin(a), sin(a) + k * cos(a))
            let c2 = project(cos(b) + k * sin(b), sin(b) - k * cos(b))
            let target = i == segments - 1 ? end : project(cos(b), sin(b))
            path.addCurve(to: target, control1: c1, control2: c2)
        }
    }
}
