import SwiftUI

/// A small, self-contained TeX math subset used by the built-in Markdown renderer.
/// Unknown commands remain visible so a formula never silently loses content.
indirect enum NativeMathNode: Equatable {
    case text(String)
    case row([NativeMathNode])
    case fraction(NativeMathNode, NativeMathNode)
    case root(NativeMathNode)
    case accent(String, NativeMathNode)
    case script(NativeMathNode, sub: NativeMathNode?, sup: NativeMathNode?)
    case matrix([[NativeMathNode]], left: String, right: String)
}

enum NativeMathParser {
    static func parse(_ source: String) -> NativeMathNode {
        var parser = Parser(Array(source))
        return .row(parser.row())
    }

    private struct Parser {
        let chars: [Character]
        var index = 0
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
                guard var node = atom() else { break }
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
                return .text(next == "\\" ? " " : String(next))
            }
            var name = ""
            while let c = current, c.isLetter { name.append(take()!) }
            switch name {
            case "frac", "dfrac", "tfrac", "binom":
                let numerator = group(), denominator = group()
                if name == "binom" { return .row([.text("("), .fraction(numerator, denominator), .text(")")]) }
                return .fraction(numerator, denominator)
            case "sqrt":
                if consume("[") { // Keep an optional root index visible.
                    var degree = ""
                    while let c = current, c != "]" { degree.append(take()!) }
                    _ = consume("]")
                    return .row([.text(degree), .root(group())])
                }
                return .root(group())
            case "begin":
                let environment = rawGroup()
                if ["matrix", "pmatrix", "bmatrix", "vmatrix"].contains(environment) {
                    let closing = "\\end{" + environment + "}"
                    var body = ""
                    while !end && !chars[index...].starts(with: Array(closing)) { body.append(take()!) }
                    _ = consume(closing)
                    let rows = body.components(separatedBy: "\\\\").map { line in
                        line.components(separatedBy: "&").map { NativeMathParser.parse($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
                    }
                    let brackets: (String, String) = environment == "pmatrix" ? ("(", ")") : environment == "bmatrix" ? ("[", "]") : environment == "vmatrix" ? ("|", "|") : ("", "")
                    return .matrix(rows, left: brackets.0, right: brackets.1)
                }
                return .text("\\begin{" + environment + "}")
            case "left", "right": return atom()
            case "hat", "widehat", "bar", "overline", "vec", "dot", "ddot", "tilde":
                let marks = ["hat":"ˆ", "widehat":"ˆ", "bar":"¯", "overline":"¯", "vec":"→", "dot":"˙", "ddot":"¨", "tilde":"˜"]
                return .accent(marks[name]!, group())
            case "mathbf", "mathrm", "mathit", "text", "operatorname": return group()
            case ",", ";", "quad", "qquad": return .text(" ")
            default: return .text(symbols[name] ?? "\\" + name)
            }
        }
        mutating func rawGroup() -> String {
            guard consume("{") else { return "" }
            var value = ""
            while let c = current, c != "}" { value.append(take()!) }
            _ = consume("}")
            return value
        }
    }

    private static let symbols: [String: String] = [
        "alpha":"α", "beta":"β", "gamma":"γ", "delta":"δ", "epsilon":"ϵ", "varepsilon":"ε",
        "zeta":"ζ", "eta":"η", "theta":"θ", "vartheta":"ϑ", "iota":"ι", "kappa":"κ",
        "lambda":"λ", "mu":"μ", "nu":"ν", "xi":"ξ", "pi":"π", "rho":"ρ", "sigma":"σ",
        "tau":"τ", "upsilon":"υ", "phi":"ϕ", "varphi":"φ", "chi":"χ", "psi":"ψ", "omega":"ω",
        "Gamma":"Γ", "Delta":"Δ", "Theta":"Θ", "Lambda":"Λ", "Xi":"Ξ", "Pi":"Π",
        "Sigma":"Σ", "Phi":"Φ", "Psi":"Ψ", "Omega":"Ω",
        "sum":"∑", "prod":"∏", "int":"∫", "oint":"∮", "infty":"∞", "partial":"∂",
        "nabla":"∇", "cdot":"·", "times":"×", "pm":"±", "mp":"∓", "div":"÷",
        "leq":"≤", "le":"≤", "geq":"≥", "ge":"≥", "neq":"≠", "approx":"≈",
        "equiv":"≡", "to":"→", "rightarrow":"→", "leftarrow":"←", "Rightarrow":"⇒",
        "in":"∈", "notin":"∉", "subset":"⊂", "subseteq":"⊆", "cup":"∪", "cap":"∩",
        "forall":"∀", "exists":"∃", "hbar":"ℏ", "ell":"ℓ", "ldots":"…", "cdots":"⋯",
        "sin":"sin", "cos":"cos", "tan":"tan", "log":"log", "ln":"ln", "lim":"lim",
        "hat":"^", "bar":"¯", "vec":"→"
    ]
}

struct NativeMathView: View {
    let latex: String
    let size: CGFloat
    var body: some View {
        MathNodeView(node: NativeMathParser.parse(latex), size: size)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(latex.isEmpty ? "Empty formula" : latex)
    }
}

private struct MathNodeView: View {
    let node: NativeMathNode
    let size: CGFloat
    var body: some View {
        switch node {
        case let .text(value):
            Text(value).font(.system(size: size, design: .serif))
        case let .row(nodes):
            HStack(alignment: .center, spacing: 0) {
                ForEach(Array(nodes.enumerated()), id: \.offset) { _, child in
                    MathNodeView(node: child, size: size)
                }
            }
        case let .fraction(top, bottom):
            VStack(spacing: 1) {
                MathNodeView(node: top, size: size * 0.8)
                Rectangle().frame(height: max(1, size / 18))
                MathNodeView(node: bottom, size: size * 0.8)
            }.fixedSize()
        case let .root(value):
            HStack(alignment: .top, spacing: 0) {
                Text("√").font(.system(size: size * 1.3, design: .serif))
                MathNodeView(node: value, size: size)
                    .padding(.top, 2)
                    .overlay(alignment: .top) { Rectangle().frame(height: 1) }
            }
        case let .accent(mark, value):
            MathNodeView(node: value, size: size)
                .overlay(alignment: .top) {
                    Text(mark).font(.system(size: size * 0.8, design: .serif))
                        .offset(y: -size * 0.55)
                }
        case let .script(base, sub, sup):
            HStack(alignment: .center, spacing: 0) {
                MathNodeView(node: base, size: size)
                VStack(spacing: 0) {
                    if let sup { MathNodeView(node: sup, size: size * 0.65) }
                    if let sub { MathNodeView(node: sub, size: size * 0.65) }
                }.offset(y: sup == nil ? size * 0.22 : sub == nil ? -size * 0.22 : 0)
            }
        case let .matrix(rows, left, right):
            HStack(spacing: 3) {
                Text(left).font(.system(size: size * CGFloat(max(rows.count, 1)), design: .serif))
                VStack(spacing: 4) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, columns in
                        HStack(spacing: 12) {
                            ForEach(Array(columns.enumerated()), id: \.offset) { _, value in
                                MathNodeView(node: value, size: size)
                            }
                        }
                    }
                }
                Text(right).font(.system(size: size * CGFloat(max(rows.count, 1)), design: .serif))
            }
        }
    }
}
