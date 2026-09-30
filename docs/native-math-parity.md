# Native math command inventory (PR #100)

Compared against the pinned `swiftui-math` 0.1.0 source (`AtomFactory.swift` and `Parser.swift`, revision `0b5c2cfa`). This is an implementation checklist, not visual parity sign-off. The app on `main` continues to use SwiftUIMath. The draft uses no third-party math renderer: it parses the supported TeX commands locally, emits MathML, and asks Apple's offline WebKit engine to typeset and snapshot it. A local SwiftUI renderer remains visible until the snapshot is ready or if WebKit fails.

| Category | Upstream | Draft renderer | Remaining difference |
| --- | --- | --- | --- |
| Named symbols and named operators | 233 glyph/operator entries plus 13 aliases | All 233 names map to visible glyphs; operators retain default limit behavior | Apple math font and operator spacing differ from Latin Modern |
| Spacing and style | 6 spacing commands, 4 style commands | Decimal em mu gaps including negative `\!`; ordinary math spaces ignored; style state scopes to remaining atoms in its group | Exact TeX font metrics still differ |
| Fonts | 22 font command names | MathML mathvariant and system fallback fonts | No bundled Latin Modern; some Unicode glyph shapes differ |
| Accents and enclosures | 12 accents, overline, underline, left/right delimiters | MathML mover/munder; only explicit left/right and matrix fences stretch, while ordinary parentheses remain text size | Wide accents may remain narrow on WebKit; very tall nested fences show glyph assembly seams |
| Fractions/roots | frac, cfrac, dfrac, tfrac, binom, over, atop, choose, brack, brace, sqrt | MathML fractions, roots and scripts | Continued fraction and TeX axis metrics differ |
| Colors | color, textcolor, colorbox | MathML foreground/background; base color resolves from `styleSheet.textColor` in the active color scheme and enters the snapshot cache key | This draft honors explicit colors while the app's old default Math view used monochrome mode |
| Tables/environments | 13 matrix forms and 7 additional environments | MathML tables with column alignment; nested environments retain their own row and cell separators | WebKit's table/fence typography differs |
| Other parser commands | substack, pmod, not, limits/nolimits, escaped characters | All 11 upstream `not` combinations, limits and controls parsed | Unknown commands remain visible source rather than upstream parse error |

## Upstream named commands by category

- **Other (1):** `\square`.
- **Greek characters (30):** `\alpha`, `\beta`, `\gamma`, `\delta`, `\varepsilon`, `\zeta`, `\eta`, `\theta`, `\iota`, `\kappa`, `\lambda`, `\mu`, `\nu`, `\xi`, `\omicron`, `\pi`, `\rho`, `\varsigma`, `\sigma`, `\tau`, `\upsilon`, `\varphi`, `\chi`, `\psi`, `\omega`, `\epsilon`, `\vartheta`, `\phi`, `\varrho`, `\varpi`.
- **Capital greek characters (11):** `\Gamma`, `\Delta`, `\Theta`, `\Lambda`, `\Xi`, `\Pi`, `\Sigma`, `\Upsilon`, `\Phi`, `\Psi`, `\Omega`.
- **Open (4):** `\lceil`, `\lfloor`, `\langle`, `\lgroup`.
- **Close (4):** `\rceil`, `\rfloor`, `\rangle`, `\rgroup`.
- **Arrows (23):** `\leftarrow`, `\uparrow`, `\rightarrow`, `\downarrow`, `\leftrightarrow`, `\updownarrow`, `\nwarrow`, `\nearrow`, `\searrow`, `\swarrow`, `\mapsto`, `\Leftarrow`, `\Uparrow`, `\Rightarrow`, `\Downarrow`, `\Leftrightarrow`, `\Updownarrow`, `\longleftarrow`, `\longrightarrow`, `\longleftrightarrow`, `\Longleftarrow`, `\Longrightarrow`, `\Longleftrightarrow`.
- **Relations (31):** `\leq`, `\geq`, `\neq`, `\in`, `\notin`, `\ni`, `\propto`, `\mid`, `\parallel`, `\sim`, `\simeq`, `\cong`, `\approx`, `\asymp`, `\doteq`, `\equiv`, `\gg`, `\ll`, `\prec`, `\succ`, `\subset`, `\supset`, `\subseteq`, `\supseteq`, `\sqsubset`, `\sqsupset`, `\sqsubseteq`, `\sqsupseteq`, `\models`, `\perp`, `\implies`.
- **operators (26):** `\times`, `\div`, `\pm`, `\dagger`, `\ddagger`, `\mp`, `\setminus`, `\ast`, `\circ`, `\bullet`, `\wedge`, `\vee`, `\cap`, `\cup`, `\wr`, `\uplus`, `\sqcap`, `\sqcup`, `\oplus`, `\ominus`, `\otimes`, `\oslash`, `\odot`, `\star`, `\cdot`, `\amalg`.
- **No limit operators (23):** `\log`, `\lg`, `\ln`, `\sin`, `\arcsin`, `\sinh`, `\cos`, `\arccos`, `\cosh`, `\tan`, `\arctan`, `\tanh`, `\cot`, `\coth`, `\sec`, `\csc`, `\arg`, `\ker`, `\dim`, `\hom`, `\exp`, `\deg`, `\mod`.
- **Limit operators (10):** `\lim`, `\limsup`, `\liminf`, `\max`, `\min`, `\sup`, `\inf`, `\det`, `\Pr`, `\gcd`.
- **Large operators (17):** `\prod`, `\coprod`, `\sum`, `\int`, `\iint`, `\iiint`, `\iiiint`, `\oint`, `\bigwedge`, `\bigvee`, `\bigcap`, `\bigcup`, `\bigodot`, `\bigoplus`, `\bigotimes`, `\biguplus`, `\bigsqcup`.
- **Latex command characters (9):** `\{`, `\}`, `\$`, `\&`, `\#`, `\%`, `\_`, `\ `, `\backslash`.
- **Punctuation (2):** `\colon`, `\cdotp`.
- **Other symbols (42):** `\degree`, `\neg`, `\angstrom`, `\aa`, `\ae`, `\o`, `\oe`, `\ss`, `\cc`, `\CC`, `\O`, `\AE`, `\OE`, `\|`, `\vert`, `\ldots`, `\prime`, `\hbar`, `\lbar`, `\Im`, `\ell`, `\wp`, `\Re`, `\mho`, `\aleph`, `\forall`, `\exists`, `\nexists`, `\emptyset`, `\nabla`, `\infty`, `\angle`, `\top`, `\bot`, `\vdots`, `\cdots`, `\ddots`, `\triangle`, `\imath`, `\jmath`, `\upquote`, `\partial`.
- **Spacing (6):** `\,`, `\>`, `\;`, `\!`, `\quad`, `\qquad`.
- **Style (4):** `\displaystyle`, `\textstyle`, `\scriptstyle`, `\scriptscriptstyle`.

## Upstream structural commands and environments

- **Fonts (22):** `\mathnormal`, `\mathrm`, `\textrm`, `\rm`, `\mathbf`, `\bf`, `\textbf`, `\mathcal`, `\cal`, `\mathtt`, `\texttt`, `\mathit`, `\textit`, `\mit`, `\mathsf`, `\textsf`, `\mathfrak`, `\frak`, `\mathbb`, `\mathbfit`, `\bm`, `\text`.
- **Accents (12):** `\grave`, `\acute`, `\hat`, `\tilde`, `\bar`, `\breve`, `\dot`, `\ddot`, `\check`, `\vec`, `\widehat`, `\widetilde`.
- **Fractions and roots:** `\frac`, `\cfrac`, `\dfrac`, `\tfrac`, `\binom`, `\sqrt`, plus infix `\over`, `\atop`, `\choose`, `\brack`, `\brace`.
- **Enclosures and decorations:** `\left`, `\right`, `\overline`, `\underline`, `\color`, `\textcolor`, `\colorbox`.
- **Other parser controls:** `\substack`, `\pmod`, `\not`, `\limits`, `\nolimits`, `\begin`, `\end`, `\cr`, and `\\` row breaks.
- **Matrix environments (13):** `matrix`, `pmatrix`, `bmatrix`, `Bmatrix`, `vmatrix`, `Vmatrix`, `smallmatrix`, `matrix*`, `pmatrix*`, `bmatrix*`, `Bmatrix*`, `vmatrix*`, `Vmatrix*`.
- **Other environments (7):** `eqalign`, `split`, `aligned`, `displaylines`, `gather`, `eqnarray`, `cases`.

`array` and `align` are supported by this draft in addition to the upstream environment list. Upstream supports inline/display math delimiters too; the Markdown layer already splits `$...$` and `$$...$$` before reaching this renderer.

## Evidence

- `Tests/SmoothMarkdownTests/NativeMathParserTests.swift` covers symbol inventory, structural nodes, actual macOS SwiftUI hosting layout, bitmap rendering, and constrained inline wrapping.
- `Tests/SmoothMarkdownTests/NativeMathMLTests.swift` covers MathML structure, escaping, style and column alignment, ordinary/explicit spacing, actual offline WebKit snapshots, transparent crop, snapshot cache reuse, and formulas wider than the initial 2048-point viewport.
- `DemoExamplesUITests.testMathPageSnapshotsThroughMatrixAndCalculus` captures the top, summation, matrix, and calculus areas plus dark theme of the full Demo math page on an iPhone 17 Pro Simulator (iOS 26.0.1). The five PNGs are `benchmarks/evidence/ios-native-math-webkit-{top,sum,matrix,calculus,dark}.png`; the test passed on 2026-09-30.
- `benchmarks/evidence/ios-native-math-webkit-gallery.png` is an actual offline macOS WebKit snapshot covering alphabet variants, wide accents, nested matrices, cases, limits, colors, fractions, and a dark card. It exposes remaining wide-accent and tall-fence geometry differences.
- `benchmarks/evidence/ios-native-math-draft.png` is the earlier local SwiftUI fallback snapshot.
- Simulator review found no missing, clipped, or overlapping formulas across the Demo page. Wide accents remain visually narrow over multi-character operands, and WebKit assembles very tall nested delimiters with visible seams. These are typography differences from the pinned Latin Modern renderer, not missing commands or values. Unknown commands remain visible source instead of triggering the upstream parser error.
