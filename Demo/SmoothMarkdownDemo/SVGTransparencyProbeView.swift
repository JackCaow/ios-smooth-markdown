import SmoothMarkdown
import SwiftUI

struct SVGTransparencyProbeView: View {
    var body: some View {
        VStack(spacing: 0) {
            Text("SVG transparency probe")
                .font(.headline)
                .frame(height: 80)
            SmoothMarkdownView(markdown: "![probe](transparent-webkit-probe.svg)")
                .frame(width: 200, height: 200)
                .background(Color(red: 1, green: 0, blue: 1))
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("svg-transparency-probe")
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
    }
}
