import Foundation

public enum MermaidRadarGraticule: Equatable { case polygon, circle }

public struct MermaidRadarAxis: Equatable {
    public let id: String
    public let label: String
    public init(id: String, label: String) { self.id = id; self.label = label }
}

public struct MermaidRadarCurve: Equatable {
    public let id: String
    public let label: String
    public let values: [Double]
    public init(id: String, label: String, values: [Double]) {
        self.id = id; self.label = label; self.values = values
    }
}

public enum MermaidXYSeriesType: Equatable { case bar, line }
public enum MermaidXYOrientation: Equatable { case vertical, horizontal }

public struct MermaidXYSeries: Equatable {
    public let type: MermaidXYSeriesType
    public let values: [Double]
    public init(type: MermaidXYSeriesType, values: [Double]) { self.type = type; self.values = values }
}

/// Native parser for the Flutter radar-beta and xychart-beta fixture subset.
enum MermaidPlotParser {
    static func radar(_ lines: [String]) -> MermaidDiagram? {
        var title: String?
        var axes: [MermaidRadarAxis] = []
        var curves: [MermaidRadarCurve] = []
        var showLegend = true
        var minimum: Double?
        var maximum: Double?
        var graticule: MermaidRadarGraticule = .polygon
        var ticks = 5
        for line in lines.dropFirst() {
            let lower = line.lowercased()
            if lower.hasPrefix("title ") { title = String(line.dropFirst(6)); continue }
            if lower.hasPrefix("axis ") {
                for part in splitCommas(String(line.dropFirst(5))) {
                    let value = part.trimmingCharacters(in: .whitespaces)
                    if let match = capture(#"^(.+?)\[\"([^\"]+)\"\]$"#, value) {
                        axes.append(.init(id: match[1].trimmingCharacters(in: .whitespaces), label: match[2]))
                    } else if !value.isEmpty { axes.append(.init(id: value, label: value)) }
                }
                continue
            }
            if lower.hasPrefix("curve ") {
                let content = String(line.dropFirst(6))
                guard let match = capture(#"^(.+?)(?:\[\"([^\"]+)\"\])?\{([^}]+)\}$"#, content) else { continue }
                let id = match[1].trimmingCharacters(in: .whitespaces)
                let values = match[3].split(separator: ",").compactMap { item -> Double? in
                    let text = String(item).split(separator: ":", maxSplits: 1).last.map(String.init) ?? ""
                    return Double(text.trimmingCharacters(in: .whitespaces))
                }.filter(\.isFinite)
                if !id.isEmpty && !values.isEmpty { curves.append(.init(id: id, label: match[2].isEmpty ? id : match[2], values: values)) }
                continue
            }
            if lower.hasPrefix("showlegend ") { showLegend = ["true", "yes", "1"].contains(String(lower.dropFirst(11))); continue }
            if lower.hasPrefix("max ") { maximum = Double(String(line.dropFirst(4))); continue }
            if lower.hasPrefix("min ") { minimum = Double(String(line.dropFirst(4))); continue }
            if lower.hasPrefix("graticule ") { graticule = lower.dropFirst(10) == "circle" ? .circle : .polygon; continue }
            if lower.hasPrefix("ticks ") { ticks = max(1, min(Int(lower.dropFirst(6)) ?? 5, 12)); continue }
        }
        guard !axes.isEmpty, !curves.isEmpty else { return nil }
        return .init(kind: .radar, direction: .leftToRight, title: title, radarAxes: axes,
                     radarCurves: curves, radarShowLegend: showLegend, radarMinimum: minimum,
                     radarMaximum: maximum, radarGraticule: graticule, radarTicks: ticks)
    }

    static func xyChart(_ lines: [String]) -> MermaidDiagram? {
        var title: String?
        var xTitle: String?
        var yTitle: String?
        var categories: [String] = []
        var xMin: Double?
        var xMax: Double?
        var yMin: Double?
        var yMax: Double?
        var series: [MermaidXYSeries] = []
        let orientation: MermaidXYOrientation = lines[0].lowercased().contains("horizontal") ? .horizontal : .vertical
        for line in lines.dropFirst() {
            let lower = line.lowercased()
            if lower.hasPrefix("title ") { title = unquote(String(line.dropFirst(6))); continue }
            if lower.hasPrefix("x-axis ") {
                let axis = parseAxis(String(line.dropFirst(7)))
                xTitle = axis.title; categories = axis.categories; xMin = axis.minimum; xMax = axis.maximum
                continue
            }
            if lower.hasPrefix("y-axis ") {
                let axis = parseAxis(String(line.dropFirst(7)))
                yTitle = axis.title; yMin = axis.minimum; yMax = axis.maximum
                continue
            }
            let type: MermaidXYSeriesType
            let values: String
            if lower.hasPrefix("bar ") { type = .bar; values = String(line.dropFirst(4)) }
            else if lower.hasPrefix("line ") { type = .line; values = String(line.dropFirst(5)) }
            else { continue }
            let content = values.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            let numbers = content.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }.filter(\.isFinite)
            if !numbers.isEmpty { series.append(.init(type: type, values: numbers)) }
        }
        guard !series.isEmpty else { return nil }
        return .init(kind: .xyChart, direction: .leftToRight, title: title,
                     xySeries: series, xyOrientation: orientation, xyCategories: categories,
                     xyXAxisTitle: xTitle, xyYAxisTitle: yTitle, xyXAxisMinimum: xMin,
                     xyXAxisMaximum: xMax, xyYAxisMinimum: yMin, xyYAxisMaximum: yMax)
    }

    private struct AxisData {
        var title: String?
        var categories: [String] = []
        var minimum: Double?
        var maximum: Double?
    }

    private static func parseAxis(_ raw: String) -> AxisData {
        var value = raw.trimmingCharacters(in: .whitespaces)
        var data = AxisData()
        if value.hasPrefix("\""), let end = value.dropFirst().firstIndex(of: "\"") {
            data.title = String(value[value.index(after: value.startIndex)..<end])
            value = String(value[value.index(after: end)...]).trimmingCharacters(in: .whitespaces)
        }
        if let bracket = value.firstIndex(of: "["), let end = value.lastIndex(of: "]"), end > bracket {
            if data.title == nil {
                let prefix = String(value[..<bracket]).trimmingCharacters(in: .whitespaces)
                data.title = prefix.isEmpty ? nil : prefix
            }
            let content = String(value[value.index(after: bracket)..<end])
            data.categories = splitCommas(content).map { unquote($0.trimmingCharacters(in: .whitespaces)) }.filter { !$0.isEmpty }
            return data
        }
        if let arrow = value.range(of: "-->") {
            let left = String(value[..<arrow.lowerBound]).trimmingCharacters(in: .whitespaces)
            let right = String(value[arrow.upperBound...]).trimmingCharacters(in: .whitespaces)
            let parts = left.split(whereSeparator: \.isWhitespace).map(String.init)
            if let last = parts.last, let minimum = Double(last), let maximum = Double(right) {
                if data.title == nil {
                    let title = parts.dropLast().joined(separator: " ")
                    data.title = title.nilIfEmpty
                }
                data.minimum = minimum; data.maximum = maximum
            }
        } else if data.title == nil { data.title = value.nilIfEmpty }
        return data
    }

    private static func unquote(_ value: String) -> String {
        let text = value.trimmingCharacters(in: .whitespaces)
        return text.hasPrefix("\"") && text.hasSuffix("\"") && text.count >= 2 ? String(text.dropFirst().dropLast()) : text
    }

    private static func splitCommas(_ value: String) -> [String] {
        var pieces: [String] = []
        var current = ""
        var quoted = false
        var depth = 0
        for character in value {
            if character == "\"" { quoted.toggle() }
            if character == "[" && !quoted { depth += 1 }
            if character == "]" && !quoted { depth -= 1 }
            if character == "," && !quoted && depth == 0 { pieces.append(current); current = "" }
            else { current.append(character) }
        }
        if !current.isEmpty { pieces.append(current) }
        return pieces
    }

    private static func capture(_ pattern: String, _ text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (0..<match.numberOfRanges).map { match.range(at: $0).location == NSNotFound ? "" : ns.substring(with: match.range(at: $0)) }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
