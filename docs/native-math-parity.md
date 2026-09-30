# Native math command inventory (Draft #100)

Compared against the pinned `swiftui-math` 0.1.0 source (`AtomFactory.swift` and `Parser.swift`, revision `0b5c2cfa`). This is an implementation checklist, not visual parity sign-off. The app on `main` continues to use SwiftUIMath.

| Category | Upstream | Draft renderer | Remaining difference |
| --- | --- | --- | --- |
| Named symbols and named operators | 233 glyph/operator entries plus 13 aliases | All 233 names map to visible glyphs; operators retain default limit behavior | Atom class spacing and font metrics differ |
| Spacing and style | 6 spacing commands, 4 style commands | Parsed as mu gaps or scoped style nodes | Global TeX style state and negative kern metrics differ |
| Fonts | 22 font command names | Parsed with scoped aliases; system fonts and Unicode alphabets | No bundled Latin Modern; some Unicode glyph fallback differs |
| Accents and enclosures | 12 accents, overline, underline, left/right delimiters | Parsed and rendered with scalable text/overlays | Geometry is approximate |
| Fractions/roots | frac, cfrac, dfrac, tfrac, binom, over, atop, choose, brack, brace, sqrt | Structural nodes and views | Continued fraction alignment and TeX rule/axis metrics differ |
| Colors | color, textcolor, colorbox | Hex RGB foreground/background | Color inheritance differs from the upstream monochrome default |
| Tables/environments | 13 matrix forms and 7 additional environments | Parsed and rendered as grids | Column sizing, delimiters and baseline differ |
| Other parser commands | substack, pmod, not, limits/nolimits, escaped characters | Parsed for common forms | Unsupported negation combinations remain visible source |

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
- `benchmarks/evidence/ios-native-math-draft.png` is a real macOS SwiftUI host snapshot. It is not an iOS visual parity result.
- Full TeX font metrics, arbitrary nesting, source error behavior, and all upstream snapshots still require further work. Keep PR #100 as Draft.
