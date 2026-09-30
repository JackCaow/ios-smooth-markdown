import SwiftUI
import CoreText

/// A small, self-contained TeX math subset used by the built-in Markdown renderer.
/// Unknown commands remain visible so a formula never silently loses content.
indirect enum NativeMathNode: Equatable {
    case text(String)
    case row([NativeMathNode])
    case fraction(NativeMathNode, NativeMathNode)
    case fractionNoRule(NativeMathNode, NativeMathNode)
    case root(NativeMathNode)
    case indexedRoot(NativeMathNode, NativeMathNode)
    case space(Int)
    case accent(String, NativeMathNode)
    case alphabet(String, NativeMathNode)
    case largeOperator(String, limits: Bool)
    case color(String, NativeMathNode)
    case colorBox(String, NativeMathNode)
    case underline(NativeMathNode)
    case style(String, NativeMathNode)
    case delimited(String, String, NativeMathNode)
    case environment(String, columns: String, rows: [[NativeMathNode]])
    case script(NativeMathNode, sub: NativeMathNode?, sup: NativeMathNode?)
    case matrix([[NativeMathNode]], left: String, right: String)
    case alignedMatrix([[NativeMathNode]], left: String, right: String, columns: String)
}

enum NativeMathParser {
    static func parse(_ source: String) -> NativeMathNode {
        var parser = Parser(Array(source))
        return .row(parser.row())
    }

    private struct Parser {
        let chars: [Character]
        var index = 0
        var spacesAllowed = false
        init(_ chars: [Character]) { self.chars = chars }
        var end: Bool { index >= chars.count }
        var current: Character? { end ? nil : chars[index] }
        mutating func take() -> Character? {
            guard !end else { return nil }
            defer { index += 1 }
            return chars[index]
        }
        mutating func consume(_ string: String) -> Bool {
            let characters = Array(string)
            guard chars[index...].starts(with: characters) else { return false }
            index += characters.count
            return true
        }
        mutating func consumeControlWord(_ string: String) -> Bool {
            let characters = Array(string)
            guard chars[index...].starts(with: characters) else { return false }
            let next = index + characters.count
            guard next == chars.count || !chars[next].isLetter else { return false }
            index = next
            return true
        }
        mutating func group() -> NativeMathNode {
            if consume("{") {
                let nodes = row(until: "}")
                _ = consume("}")
                return .row(nodes)
            }
            return atom() ?? .text("")
        }
        mutating func row(until terminator: Character? = nil) -> [NativeMathNode] {
            var nodes: [NativeMathNode] = []
            while let c = current, c != terminator {
                if c == "}" { break }
                // Ordinary whitespace has no width in TeX math mode. Explicit spacing
                // commands (including escaped space) still produce a visible gap.
                if c.isWhitespace {
                    _ = take()
                    if spacesAllowed { nodes.append(.space(5)) }
                    continue
                }
                if let style = ["displaystyle", "textstyle", "scriptstyle", "scriptscriptstyle"]
                    .first(where: { consumeControlWord("\\" + $0) }) {
                    nodes.append(.style(style, .row(row(until: terminator))))
                    return nodes
                }
                for (command, left, right, ruled) in [
                    ("\\over", "", "", true), ("\\atop", "", "", false),
                    ("\\choose", "(", ")", false), ("\\brack", "[", "]", false),
                    ("\\brace", "{", "}", false)
                ] where consumeControlWord(command) {
                    let top = NativeMathNode.row(nodes)
                    let bottom = NativeMathNode.row(row(until: terminator))
                    let fraction: NativeMathNode = ruled ? .fraction(top, bottom) : .fractionNoRule(top, bottom)
                    return [left.isEmpty ? fraction : .delimited(left, right, fraction)]
                }
                guard var node = atom() else { break }
                if case let .largeOperator(symbol, _) = node {
                    if consumeControlWord("\\limits") { node = .largeOperator(symbol, limits: true) }
                    else if consumeControlWord("\\nolimits") { node = .largeOperator(symbol, limits: false) }
                }
                var sub: NativeMathNode?
                var sup: NativeMathNode?
                while current == "_" || current == "^" {
                    let marker = take()
                    let value = group()
                    if marker == "_" { sub = value } else { sup = value }
                }
                if sub != nil || sup != nil { node = .script(node, sub: sub, sup: sup) }
                nodes.append(node)
            }
            return nodes
        }
        mutating func atom() -> NativeMathNode? {
            guard let c = take() else { return nil }
            if c == "{" {
                let nodes = row(until: "}")
                _ = consume("}")
                return .row(nodes)
            }
            if c != "\\" { return .text(String(c)) }
            guard let next = current else { return .text("\\") }
            if !next.isLetter {
                _ = take()
                let command = String(next)
                if let mu = NativeMathSymbols.spacingMu[command] { return .space(mu) }
                return .text(NativeMathSymbols.glyphs[command] ?? command)
            }
            var name = ""
            while let c = current, c.isLetter { name.append(take()!) }
            switch name {
            case "frac", "dfrac", "tfrac", "cfrac", "binom":
                if name == "cfrac", consume("["), current != nil { _ = take(); _ = consume("]") }
                let numerator = group(), denominator = group()
                if name == "binom" { return .delimited("(", ")", .fractionNoRule(numerator, denominator)) }
                if name == "tfrac" { return .style("text", .fraction(numerator, denominator)) }
                if name == "dfrac" || name == "cfrac" { return .style("display", .fraction(numerator, denominator)) }
                return .fraction(numerator, denominator)
            case "sqrt":
                if consume("[") { // Keep an optional root index visible.
                    var degree = ""
                    while let c = current, c != "]" { degree.append(take()!) }
                    _ = consume("]")
                    return .indexedRoot(NativeMathParser.parse(degree), group())
                }
                return .root(group())
            case "begin":
                let environment = rawGroup()
                let matrices = ["matrix", "pmatrix", "bmatrix", "Bmatrix", "vmatrix", "Vmatrix", "smallmatrix",
                                "matrix*", "pmatrix*", "bmatrix*", "Bmatrix*", "vmatrix*", "Vmatrix*"]
                if matrices.contains(environment) || ["cases", "array", "aligned", "align", "split", "eqalign", "eqnarray", "gather", "displaylines"].contains(environment) {
                    let columns = environment == "array" ? rawGroup() :
                        (["aligned", "align", "split", "eqalign"].contains(environment) ? "rl" :
                         environment == "eqnarray" ? "rcl" : environment == "cases" ? "ll" : "c")
                    let starredAlignment = environment.hasSuffix("*") && consume("[") ? String(take() ?? "c") : ""
                    if !starredAlignment.isEmpty { _ = consume("]") }
                    let opening = "\\begin{" + environment + "}"
                    let closing = "\\end{" + environment + "}"
                    var body = ""
                    var nesting = 1
                    while !end && nesting > 0 {
                        if consume(opening) { nesting += 1; body += opening; continue }
                        if consume(closing) {
                            nesting -= 1
                            if nesting > 0 { body += closing }
                            continue
                        }
                        body.append(take()!)
                    }
                    let rows = Self.splitTopLevel(body, rows: true).map { line in
                        Self.splitTopLevel(line, rows: false).map { NativeMathParser.parse($0) }
                    }
                    let base = environment.replacingOccurrences(of: "*", with: "")
                    let brackets: (String, String) = base == "pmatrix" ? ("(", ")") :
                        base == "bmatrix" ? ("[", "]") : base == "Bmatrix" ? ("{", "}") :
                        base == "vmatrix" ? ("|", "|") : base == "Vmatrix" ? ("‖", "‖") : ("", "")
                    if matrices.contains(environment) {
                        if !starredAlignment.isEmpty {
                            return .alignedMatrix(rows, left: brackets.0, right: brackets.1,
                                                  columns: String(repeating: starredAlignment,
                                                                  count: rows.map(\.count).max() ?? 1))
                        }
                        let matrix: NativeMathNode = .matrix(rows, left: brackets.0, right: brackets.1)
                        return environment == "smallmatrix" ? .style("scriptstyle", matrix) : matrix
                    }
                    return .environment(environment, columns: starredAlignment.isEmpty ? columns :
                                        String(repeating: starredAlignment, count: rows.map(\.count).max() ?? 1), rows: rows)
                }
                return .text("\\begin{" + environment + "}")
            case "left":
                let left = delimiter()
                let start = index
                var depth = 1
                while !end {
                    if consumeControlWord("\\left") { depth += 1; continue }
                    if consumeControlWord("\\right") {
                        depth -= 1
                        if depth == 0 {
                            let body = String(chars[start..<(index - "\\right".count)])
                            return .delimited(left, delimiter(), NativeMathParser.parse(body))
                        }
                        continue
                    }
                    _ = take()
                }
                return .text("\\left" + left + String(chars[start...]))
            case "right": return .text("\\right")
            case "color", "textcolor", "colorbox":
                let hex = rawGroup()
                guard NativeMathColor.isValid(hex) else { return .text("\\" + name + "{" + hex + "}") }
                return name == "colorbox" ? .colorBox(hex, group()) : .color(hex, group())
            case "underline": return .underline(group())
            case "substack":
                let source = rawGroup()
                let rows = source.components(separatedBy: "\\\\").map { [NativeMathParser.parse($0)] }
                return .environment("substack", columns: "c", rows: rows)
            case "pmod": return .delimited("(", ")", .row([.text("mod"), .space(6), group()]))
            case "not":
                if consume("\\") {
                    var command = ""
                    while let c = current, c.isLetter { command.append(take()!) }
                    return .text(NativeMathSymbols.negated[command] ?? "\\not\\" + command)
                }
                if consume("=") { return .text("≠") }
                return .text("\\not")
            case "grave", "acute", "hat", "widehat", "tilde", "widetilde", "bar", "breve", "dot", "ddot", "check", "vec", "overline":
                let marks = ["grave":"`", "acute":"´", "hat":"ˆ", "widehat":"ˆ", "tilde":"˜",
                             "widetilde":"˜", "bar":"¯", "breve":"˘", "dot":"˙", "ddot":"¨",
                             "check":"ˇ", "vec":"→", "overline":"¯"]
                return .accent(marks[name]!, group())
            case "mathnormal", "mathrm", "textrm", "rm", "mathbf", "bf", "textbf", "mathcal", "cal",
                 "mathtt", "texttt", "mathit", "textit", "mit", "mathsf", "textsf", "mathfrak", "frak",
                 "mathbb", "mathbfit", "bm", "text", "operatorname":
                let aliases = ["textrm":"mathrm", "rm":"mathrm", "bf":"mathbf", "textbf":"mathbf",
                               "cal":"mathcal", "texttt":"mathtt", "textit":"mathit", "mit":"mathit",
                               "textsf":"mathsf", "frak":"mathfrak", "mathbfit":"bm", "text":"mathrm"]
                if name == "text" || name == "operatorname" {
                    let previous = spacesAllowed
                    spacesAllowed = true
                    let value = group()
                    spacesAllowed = previous
                    return .alphabet(aliases[name] ?? "mathrm", value)
                }
                return .alphabet(aliases[name] ?? name, group())
            case "displaystyle", "textstyle", "scriptstyle", "scriptscriptstyle":
                return .style(name, group())
            default:
                let resolved = NativeMathSymbols.aliases[name] ?? name
                if let mu = NativeMathSymbols.spacingMu[resolved] { return .space(mu) }
                if let limits = NativeMathSymbols.operatorLimits[resolved] {
                    return .largeOperator(NativeMathSymbols.glyphs[resolved] ?? resolved, limits: limits)
                }
                return .text(NativeMathSymbols.glyphs[resolved] ?? "\\" + name)
            }
        }
        mutating func delimiter() -> String {
            guard let next = current else { return "" }
            if next != "\\" { _ = take(); return next == "." ? "" : String(next) }
            _ = take()
            var command = ""
            while let c = current, c.isLetter { command.append(take()!) }
            return ["langle":"⟨", "rangle":"⟩", "lbrace":"{", "rbrace":"}", "lvert":"|", "rvert":"|", "lfloor":"⌊", "rfloor":"⌋", "lceil":"⌈", "rceil":"⌉"][command] ?? "\\" + command
        }
        mutating func rawGroup() -> String {
            guard consume("{") else { return "" }
            var value = ""
            var depth = 1
            while let c = take() {
                if c == "{" { depth += 1 }
                if c == "}" { depth -= 1 }
                if depth == 0 { break }
                value.append(c)
            }
            return value
        }

        /// Splits table separators only outside groups and nested environments.
        private static func splitTopLevel(_ source: String, rows: Bool) -> [String] {
            let chars = Array(source)
            var pieces: [String] = []
            var part = ""
            var braces = 0
            var environments = 0
            var index = 0
            while index < chars.count {
                let remaining = chars[index...]
                if remaining.starts(with: Array("\\begin{")) { environments += 1 }
                if remaining.starts(with: Array("\\end{")) { environments = max(0, environments - 1) }
                if chars[index] == "\\", index + 1 < chars.count {
                    if braces == 0 && environments == 0 && rows {
                        if chars[index + 1] == "\\" {
                            pieces.append(part); part = ""; index += 2; continue
                        }
                        if remaining.starts(with: Array("\\cr")),
                           index + 3 == chars.count || !chars[index + 3].isLetter {
                            pieces.append(part); part = ""; index += 3; continue
                        }
                    }
                    if chars[index + 1] == "\\" || !chars[index + 1].isLetter {
                        part.append(chars[index]); part.append(chars[index + 1]); index += 2; continue
                    }
                }
                if braces == 0 && environments == 0 && !rows && chars[index] == "&" {
                    pieces.append(part); part = ""; index += 1; continue
                }
                if chars[index] == "{" { braces += 1 }
                if chars[index] == "}" { braces = max(0, braces - 1) }
                part.append(chars[index])
                index += 1
            }
            pieces.append(part)
            return pieces
        }
    }


}

struct NativeMathView: View {
    let latex: String
    let size: CGFloat
    let display: Bool
    var body: some View {
        MathNodeView(node: NativeMathParser.parse(latex), size: size, display: display)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(latex.isEmpty ? "Empty formula" : latex)
    }
}

private struct MathNodeView: View {
    let node: NativeMathNode
    let size: CGFloat
    let display: Bool
    var alphabet = "mathit"
    var body: some View { AnyView(content) }

    @ViewBuilder private var content: some View {
        switch node {
        case let .text(value):
            let rendered = NativeMathGlyphs.styled(value, alphabet: alphabet)
            Text(rendered)
                .font(textFont(for: value))
                .frame(minHeight: NativeMathMetrics.lineHeight(size: size))
        case let .row(nodes):
            NativeMathRowLayout(lineSpacing: size * 0.3) {
                ForEach(Array(nodes.enumerated()), id: \.offset) { index, child in
                    MathNodeView(node: child, size: size, display: display, alphabet: alphabet)
                        .layoutValue(key: NativeMathGapKey.self,
                                     value: child.spaceMu.map { CGFloat($0) * size / 18 } ??
                                        (index > 0 && NativeMathSpacing.needsGap(before: child, after: nodes[index - 1])
                                         ? NativeMathMetrics.operatorGap(size: size) : 0))
                        .layoutValue(key: NativeMathBreakKey.self,
                                     value: index > 0 && NativeMathSpacing.canBreak(after: nodes[index - 1]))
                }
            }
        case .space:
            Color.clear.frame(width: 0, height: 0)
        case let .fraction(top, bottom):
            VStack(spacing: 1) {
                MathNodeView(node: top, size: size * (display ? 0.8 : 0.7), display: display, alphabet: alphabet)
                Rectangle().frame(height: max(1, size / 18))
                MathNodeView(node: bottom, size: size * (display ? 0.8 : 0.7), display: display, alphabet: alphabet)
            }.fixedSize()
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] }
        case let .fractionNoRule(top, bottom):
            VStack(spacing: 2) {
                MathNodeView(node: top, size: size * 0.8, display: display, alphabet: alphabet)
                MathNodeView(node: bottom, size: size * 0.8, display: display, alphabet: alphabet)
            }.fixedSize()
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] }
        case let .indexedRoot(degree, value):
            HStack(alignment: .top, spacing: -2) {
                MathNodeView(node: degree, size: size * 0.55, display: false, alphabet: alphabet)
                MathNodeView(node: .root(value), size: size, display: display, alphabet: alphabet)
            }
        case let .root(value):
            HStack(alignment: .top, spacing: 0) {
                Text("√").font(.system(size: size * 1.3, design: .serif))
                MathNodeView(node: value, size: size, display: display, alphabet: alphabet)
                    .padding(.top, 2)
                    .overlay(alignment: .top) { Rectangle().frame(height: 1) }
            }
        case let .accent(mark, value):
            MathNodeView(node: value, size: size, display: display, alphabet: alphabet)
                .padding(.top, NativeMathMetrics.ascent(size: size) * 0.3)
                .overlay(alignment: .top) {
                    Text(mark).font(.custom("TimesNewRomanPSMT", fixedSize: size * 0.8))
                }
        case let .alphabet(name, value):
            MathNodeView(node: value, size: size, display: display, alphabet: name)
        case let .color(hex, value):
            MathNodeView(node: value, size: size, display: display, alphabet: alphabet)
                .foregroundStyle(NativeMathColor.color(hex))
        case let .colorBox(hex, value):
            MathNodeView(node: value, size: size, display: display, alphabet: alphabet)
                .padding(2).background(NativeMathColor.color(hex))
        case let .underline(value):
            MathNodeView(node: value, size: size, display: display, alphabet: alphabet)
                .padding(.bottom, 2)
                .overlay(alignment: .bottom) { Rectangle().frame(height: 1) }
        case let .style(name, value):
            MathNodeView(node: value, size: size * (name == "scriptstyle" ? 0.7 :
                                          name == "scriptscriptstyle" ? 0.5 : 1),
                             display: name == "displaystyle" ? true : name == "textstyle" ? false : display,
                             alphabet: alphabet)
        case let .delimited(left, right, value):
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(left).font(.custom("TimesNewRomanPSMT", fixedSize: size * value.verticalScale))
                MathNodeView(node: value, size: size, display: display, alphabet: alphabet)
                Text(right).font(.custom("TimesNewRomanPSMT", fixedSize: size * value.verticalScale))
            }
        case let .largeOperator(value, _):
            Text(value).font(.custom("TimesNewRomanPSMT", fixedSize:
                                     display && value.count == 1 ? size * 1.35 : size))
        case let .script(base, sub, sup):
            if case let .largeOperator(_, limits) = base, limits && display {
                VStack(spacing: 0) {
                    if let sup { MathNodeView(node: sup, size: size * 0.65, display: display, alphabet: alphabet) }
                    MathNodeView(node: base, size: size, display: display, alphabet: alphabet)
                    if let sub { MathNodeView(node: sub, size: size * 0.65, display: display, alphabet: alphabet) }
                }
            } else {
                HStack(alignment: .center, spacing: 0) {
                    MathNodeView(node: base, size: size, display: display, alphabet: alphabet)
                    VStack(spacing: 0) {
                        if let sup { MathNodeView(node: sup, size: size * 0.65, display: display, alphabet: alphabet) }
                        if let sub { MathNodeView(node: sub, size: size * 0.65, display: display, alphabet: alphabet) }
                    }.offset(y: sup == nil ? size * 0.22 : sub == nil ? -size * 0.22 : 0)
                }
            }
        case let .matrix(rows, left, right):
            table(rows, left: left, right: right, columns: "")
        case let .alignedMatrix(rows, left, right, columns):
            table(rows, left: left, right: right, columns: columns)
        case let .environment(name, columns, rows):
            table(rows, left: name == "cases" ? "{" : "", right: "", columns: columns)
        }
    }

    private func textFont(for value: String) -> Font {
        switch alphabet {
        case "mathsf": return .system(size: size, design: .default)
        case "mathtt": return .system(size: size, design: .monospaced)
        case "mathbf": return .custom("TimesNewRomanPS-BoldMT", fixedSize: size)
        case "bm": return .custom("TimesNewRomanPS-BoldItalicMT", fixedSize: size)
        case "mathit" where value.allSatisfy(\.isLetter):
            return .custom("TimesNewRomanPS-ItalicMT", fixedSize: size)
        case "mathnormal" where value.allSatisfy(\.isLetter):
            return .custom("TimesNewRomanPS-ItalicMT", fixedSize: size)
        default: return .custom("TimesNewRomanPSMT", fixedSize: size)
        }
    }

    private func table(_ rows: [[NativeMathNode]], left: String, right: String, columns: String) -> some View {
        NativeMathTable(rows: rows, left: left, right: right, columns: columns,
                        size: size, display: display, alphabet: alphabet)
    }


}

private struct NativeMathTable: View {
    let rows: [[NativeMathNode]]
    let left: String
    let right: String
    let columns: String
    let size: CGFloat
    let display: Bool
    let alphabet: String

    var body: some View {
        HStack(spacing: 4) {
            if !left.isEmpty { Text(left).font(.system(size: size * CGFloat(max(rows.count, 1)), design: .serif)) }
            Grid(horizontalSpacing: 12, verticalSpacing: 4) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, cells in
                    GridRow {
                        ForEach(Array(cells.enumerated()), id: \.offset) { column, value in
                            MathNodeView(node: value, size: size, display: display, alphabet: alphabet)
                                .gridCellAnchor(anchor(column))
                        }
                    }
                }
            }
            if !right.isEmpty { Text(right).font(.system(size: size * CGFloat(max(rows.count, 1)), design: .serif)) }
        }
    }

    private func anchor(_ column: Int) -> UnitPoint {
        let spec = Array(columns)
        guard spec.indices.contains(column) else { return .center }
        if spec[column] == "r" { return .trailing }
        if spec[column] == "l" { return .leading }
        return .center
    }
}


enum NativeMathGlyphs {
    static func styled(_ value: String, alphabet: String) -> String {
        let source = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")
        let letters: String
        switch alphabet {
        case "mathbb": letters = "𝔸𝔹ℂ𝔻𝔼𝔽𝔾ℍ𝕀𝕁𝕂𝕃𝕄ℕ𝕆ℙℚℝ𝕊𝕋𝕌𝕍𝕎𝕏𝕐ℤ𝕒𝕓𝕔𝕕𝕖𝕗𝕘𝕙𝕚𝕛𝕜𝕝𝕞𝕟𝕠𝕡𝕢𝕣𝕤𝕥𝕦𝕧𝕨𝕩𝕪𝕫"
        case "mathfrak": letters = "𝔄𝔅ℭ𝔇𝔈𝔉𝔊ℌℑ𝔍𝔎𝔏𝔐𝔑𝔒𝔓𝔔ℜ𝔖𝔗𝔘𝔙𝔚𝔛𝔜ℨ𝔞𝔟𝔠𝔡𝔢𝔣𝔤𝔥𝔦𝔧𝔨𝔩𝔪𝔫𝔬𝔭𝔮𝔯𝔰𝔱𝔲𝔳𝔴𝔵𝔶𝔷"
        case "mathcal": letters = "𝒜ℬ𝒞𝒟ℰℱ𝒢ℋℐ𝒥𝒦ℒℳ𝒩𝒪𝒫𝒬ℛ𝒮𝒯𝒰𝒱𝒲𝒳𝒴𝒵𝒶𝒷𝒸𝒹ℯ𝒻ℊ𝒽𝒾𝒿𝓀𝓁𝓂𝓃ℴ𝓅𝓆𝓇𝓈𝓉𝓊𝓋𝓌𝓍𝓎𝓏"
        default: return value
        }
        let mapped = Dictionary(uniqueKeysWithValues: zip(source, Array(letters)))
        return String(value.map { mapped[$0] ?? $0 })
    }
}

private extension NativeMathNode {
    var spaceMu: Int? {
        if case let .space(mu) = self { return mu }
        return nil
    }
    var verticalScale: CGFloat {
        switch self {
        case let .row(children): return children.map(\.verticalScale).max() ?? 1
        case .fraction, .fractionNoRule: return 1.9
        case let .matrix(rows, _, _), let .alignedMatrix(rows, _, _, _), let .environment(_, _, rows):
            return CGFloat(max(rows.count, 1)) * 1.25
        case let .root(child), let .accent(_, child), let .alphabet(_, child), let .color(_, child),
             let .colorBox(_, child), let .underline(child), let .style(_, child), let .delimited(_, _, child):
            return child.verticalScale
        case let .indexedRoot(_, child): return child.verticalScale
        case let .script(base, _, _): return max(1.3, base.verticalScale)
        case .text, .largeOperator, .space: return 1
        }
    }
}

enum NativeMathSpacing {
    static func canBreak(after node: NativeMathNode) -> Bool {
        guard case let .text(value) = node else { return false }
        return value == " " || ["+", "-", "−", "=", "<", ">", "±", "×", "÷", ","].contains(value)
    }
    static func needsGap(before node: NativeMathNode, after previous: NativeMathNode) -> Bool {
        guard case let .text(current) = node, case let .text(prior) = previous else { return false }
        if current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
           prior.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
        let operators = "+−-=<>±×÷"
        return current.count == 1 && operators.contains(current) || prior.count == 1 && operators.contains(prior)
    }
}

enum NativeMathMetrics {
    static func font(size: CGFloat) -> CTFont { CTFontCreateWithName("TimesNewRomanPSMT" as CFString, size, nil) }
    static func ascent(size: CGFloat) -> CGFloat { CTFontGetAscent(font(size: size)) }
    static func lineHeight(size: CGFloat) -> CGFloat {
        let value = font(size: size)
        return CTFontGetAscent(value) + CTFontGetDescent(value) + CTFontGetLeading(value)
    }
    static func operatorGap(size: CGFloat) -> CGFloat {
        let value = font(size: size)
        var character: UniChar = 120 // x
        var glyph: CGGlyph = 0
        guard CTFontGetGlyphsForCharacters(value, &character, &glyph, 1) else { return size * 0.2 }
        var advance = CGSize.zero
        CTFontGetAdvancesForGlyphs(value, .horizontal, &glyph, &advance, 1)
        return max(1, advance.width * 0.35)
    }
}

enum NativeMathColor {
    static func isValid(_ hex: String) -> Bool {
        let digits = hex.dropFirst()
        return hex.first == "#" && digits.count == 6 && digits.allSatisfy { $0.isHexDigit }
    }
    static func color(_ hex: String) -> Color {
        guard isValid(hex), let number = UInt32(hex.dropFirst(), radix: 16) else { return .primary }
        return Color(red: Double((number >> 16) & 0xff) / 255,
                     green: Double((number >> 8) & 0xff) / 255,
                     blue: Double(number & 0xff) / 255)
    }
}

private struct NativeMathGapKey: LayoutValueKey { static let defaultValue: CGFloat = 0 }
private struct NativeMathBreakKey: LayoutValueKey { static let defaultValue = false }

private struct NativeMathRowLayout: Layout {
    let lineSpacing: CGFloat
    struct Placement { let x: CGFloat; let y: CGFloat }
    struct Arrangement { let positions: [Placement]; let size: CGSize }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let arrangement = arrange(width: bounds.width, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            let point = arrangement.positions[index]
            subview.place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified)
        }
    }

    private func arrange(width: CGFloat?, subviews: Subviews) -> Arrangement {
        let limit = width ?? .infinity
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let baselines = subviews.enumerated().map { index, subview -> CGFloat in
            let value = subview.dimensions(in: .unspecified)[.firstTextBaseline]
            return value.isFinite ? value : sizes[index].height / 2
        }
        var result = Array(repeating: Placement(x: 0, y: 0), count: subviews.count)
        var lineStart = 0
        var x: CGFloat = 0
        var y: CGFloat = 0
        var maxWidth: CGFloat = 0
        func finishLine(_ end: Int) -> CGFloat {
            guard end > lineStart else { return 0 }
            let ascent = (lineStart..<end).map { baselines[$0] }.max() ?? 0
            let descent = (lineStart..<end).map { sizes[$0].height - baselines[$0] }.max() ?? 0
            for i in lineStart..<end {
                result[i] = Placement(x: result[i].x, y: y + ascent - baselines[i])
            }
            return ascent + descent
        }
        for index in subviews.indices {
            let gap = x == 0 ? 0 : subviews[index][NativeMathGapKey.self]
            if x > 0, x + gap + sizes[index].width > limit, subviews[index][NativeMathBreakKey.self] {
                let height = finishLine(index)
                maxWidth = max(maxWidth, x)
                y += height + lineSpacing
                lineStart = index
                x = 0
            }
            let actualGap = x == 0 ? 0 : gap
            result[index] = Placement(x: x + actualGap, y: 0)
            x += actualGap + sizes[index].width
        }
        let finalHeight = finishLine(subviews.count)
        maxWidth = max(maxWidth, x)
        return Arrangement(positions: result, size: CGSize(width: maxWidth, height: y + finalHeight))
    }
}
