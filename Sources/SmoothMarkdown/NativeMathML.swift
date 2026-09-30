import Foundation

/// Produces standards-based MathML from the locally parsed TeX subset.
/// The output contains markup only and is embedded into a fixed, offline HTML shell.
enum NativeMathML {
    static func html(_ latex: String, size: Int = 20, display: Bool, colorHex: String = "#111111") -> String {
        let math = markup(NativeMathParser.parse(latex), display: display)
        return """
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>html,body{margin:0;padding:0;background:transparent}#formula{display:inline-block;
        color:\(colorHex);font-family:serif;font-size:\(size)px;line-height:normal;white-space:nowrap}</style></head>
        <body><div id="formula"><math xmlns="http://www.w3.org/1998/Math/MathML" display="\(display ? "block" : "inline")">\(math)</math></div></body></html>
        """
    }

    static func markup(_ node: NativeMathNode, display: Bool) -> String {
        switch node {
        case let .text(value):
            let escaped = escape(value)
            if value.count == 1, let c = value.first, c.isNumber { return "<mn>\(escaped)</mn>" }
            if value.count == 1, let c = value.first,
               c.isLetter || ["∂", "𝜕", "∇", "ℏ", "∞", "∅", "ℵ", "ℑ", "ℜ", "℘", "ı", "ȷ"].contains(value) {
                return "<mi>\(escaped)</mi>"
            }
            if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "<mspace width=\"0.3em\"/>"
            }
            // TeX ordinary parentheses and brackets stay at text size. MathML's
            // default operator dictionary otherwise stretches them to nearby
            // fractions, integrals, or summations in the same row.
            return "<mo stretchy=\"false\">\(escaped)</mo>"
        case let .row(nodes): return "<mrow>\(nodes.map { markup($0, display: display) }.joined())</mrow>"
        case let .fraction(top, bottom):
            return "<mfrac>\(markup(top, display: display))\(markup(bottom, display: display))</mfrac>"
        case let .fractionNoRule(top, bottom):
            return "<mfrac linethickness=\"0\">\(markup(top, display: display))\(markup(bottom, display: display))</mfrac>"
        case let .root(value): return "<msqrt>\(markup(value, display: display))</msqrt>"
        case let .indexedRoot(degree, value):
            return "<mroot>\(markup(value, display: display))\(markup(degree, display: false))</mroot>"
        case let .space(mu):
            let width = Double(mu) / 18
            return mu < 0 ? "<mspace width=\"0em\" style=\"margin-left:\(width)em\"/>" :
                "<mspace width=\"\(width)em\"/>"
        case let .accent(mark, value):
            return "<mover accent=\"true\">\(markup(value, display: display))<mo stretchy=\"true\">\(escape(mark))</mo></mover>"
        case let .underline(value):
            return "<munder accentunder=\"true\">\(markup(value, display: display))<mo>¯</mo></munder>"
        case let .alphabet(name, value):
            let variants = ["mathrm":"normal", "mathit":"italic", "mathnormal":"italic", "mathbf":"bold",
                            "mathbb":"double-struck", "mathfrak":"fraktur", "mathcal":"script", "mathsf":"sans-serif",
                            "mathtt":"monospace", "bm":"bold-italic"]
            return "<mstyle mathvariant=\"\(variants[name] ?? "normal")\">\(markup(value, display: display))</mstyle>"
        case let .largeOperator(value, limits):
            let isGlyph = !value.unicodeScalars.allSatisfy { CharacterSet.letters.contains($0) }
            return "<mo largeop=\"\(isGlyph ? "true" : "false")\" movablelimits=\"\(limits ? "true" : "false")\">\(escape(value))</mo>"
        case let .script(base, sub, sup):
            let useLimits: Bool
            if case let .largeOperator(_, limits) = base { useLimits = limits && display } else { useLimits = false }
            let baseMarkup = markup(base, display: display)
            switch (sub, sup) {
            case let (.some(lower), .some(upper)):
                let tag = useLimits ? "munderover" : "msubsup"
                return "<\(tag)>\(baseMarkup)\(markup(lower, display: false))\(markup(upper, display: false))</\(tag)>"
            case let (.some(lower), .none):
                let tag = useLimits ? "munder" : "msub"
                return "<\(tag)>\(baseMarkup)\(markup(lower, display: false))</\(tag)>"
            case let (.none, .some(upper)):
                let tag = useLimits ? "mover" : "msup"
                return "<\(tag)>\(baseMarkup)\(markup(upper, display: false))</\(tag)>"
            case (.none, .none): return baseMarkup
            }
        case let .color(hex, value):
            return "<mstyle mathcolor=\"\(escape(hex))\">\(markup(value, display: display))</mstyle>"
        case let .colorBox(hex, value):
            return "<mstyle mathbackground=\"\(escape(hex))\">\(markup(value, display: display))</mstyle>"
        case let .style(name, value):
            let isDisplay = ["displaystyle", "display"].contains(name) ? true :
                ["textstyle", "text", "scriptstyle", "scriptscriptstyle"].contains(name) ? false : display
            let level = name == "scriptscriptstyle" ? "2" : name == "scriptstyle" ? "1" : "0"
            return "<mstyle displaystyle=\"\(isDisplay ? "true" : "false")\" scriptlevel=\"\(level)\">\(markup(value, display: isDisplay))</mstyle>"
        case let .delimited(left, right, value):
            return "<mrow><mo stretchy=\"true\">\(escape(left))</mo>\(markup(value, display: display))<mo stretchy=\"true\">\(escape(right))</mo></mrow>"
        case let .matrix(rows, left, right):
            return "<mrow><mo stretchy=\"true\">\(escape(left))</mo>\(table(rows, columns: "", display: display))<mo stretchy=\"true\">\(escape(right))</mo></mrow>"
        case let .alignedMatrix(rows, left, right, columns):
            return "<mrow><mo stretchy=\"true\">\(escape(left))</mo>\(table(rows, columns: columns, display: display))<mo stretchy=\"true\">\(escape(right))</mo></mrow>"
        case let .environment(name, columns, rows):
            if name == "cases" {
                // WebKit does not grow a lone stretchy opening brace to an mtable.
                // Give it a row-based minimum; stretchy still handles a taller
                // table where supported by the system renderer.
                let minHeight = Double(rows.count) * 1.25
                return "<mrow><mo fence=\"true\" stretchy=\"true\" minsize=\"\(minHeight)em\">{</mo>" +
                    table(rows, columns: columns, display: display) + "</mrow>"
            }
            return "<mrow>\(table(rows, columns: columns, display: display))</mrow>"
        }
    }

    private static func table(_ rows: [[NativeMathNode]], columns: String, display: Bool) -> String {
        let alignment = columns.compactMap { ["l": "left", "c": "center", "r": "right"][String($0)] }
            .joined(separator: " ")
        let attribute = alignment.isEmpty ? "" : " columnalign=\"\(alignment)\""
        let body = rows.map { cells in
            "<mtr>" + cells.map { "<mtd>\(markup($0, display: display))</mtd>" }.joined() + "</mtr>"
        }.joined()
        return "<mtable\(attribute)>\(body)</mtable>"
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
