import CryptoKit
import SmoothMarkdown
import SwiftUI
import UIKit

private struct MermaidGalleryExample: Identifiable {
    let id: Int
    let category: String
    let title: String
    let description: String
    let code: String
}

private struct MermaidGalleryCatalog {
    let examples: [MermaidGalleryExample]
    let error: String?

    private struct Manifest: Decodable {
        let examples: [Entry]

        struct Entry: Decodable {
            let index: Int
            let category: String
            let title: String
            let description: String
            let file: String
            let sha256: String
        }
    }

    static func load(bundle: Bundle = .main) -> Self {
        guard let url = resource("gallery.json", bundle: bundle),
              let data = try? Data(contentsOf: url),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data) else {
            return .init(examples: [], error: "Mermaid gallery resource is missing or invalid")
        }
        guard manifest.examples.count == 40 else {
            return .init(examples: [], error: "Mermaid gallery should contain 40 examples")
        }
        var examples: [MermaidGalleryExample] = []
        for entry in manifest.examples {
            guard entry.index == examples.count + 1,
                  let codeURL = resource(entry.file, bundle: bundle),
                  let codeData = try? Data(contentsOf: codeURL),
                  let code = String(data: codeData, encoding: .utf8) else {
                return .init(examples: [], error: "Missing or out of order Mermaid example: \(entry.file)")
            }
            let digest = SHA256.hash(data: codeData).map { String(format: "%02x", $0) }.joined()
            guard digest == entry.sha256 else {
                return .init(examples: [], error: "Mermaid example checksum mismatch: \(entry.file)")
            }
            examples.append(.init(id: entry.index, category: entry.category, title: entry.title,
                                  description: entry.description, code: code))
        }
        return .init(examples: examples, error: nil)
    }

    private static func resource(_ filename: String, bundle: Bundle) -> URL? {
        let name = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        return bundle.url(forResource: name, withExtension: ext, subdirectory: "Examples/Mermaid")
            ?? bundle.url(forResource: name, withExtension: ext, subdirectory: "Mermaid")
            ?? bundle.url(forResource: name, withExtension: ext)
    }
}

/// The Flutter example's 40-item Mermaid gallery, using synchronized source fixtures.
struct MermaidGalleryView: View {
    @State private var selectedIndex = 0
    @State private var isDark = false
    @State private var showSource = false
    @State private var nodeFeedback: String?
    @State private var lastTappedNodeID: String?
    @State private var feedbackTask: Task<Void, Never>?
    private let catalog = MermaidGalleryCatalog.load()

    private let categoryNames = [
        "flowchart": "流程图 (Flowchart)", "sequence": "时序图 (Sequence)",
        "pie": "饼图 (Pie Chart)", "gantt": "甘特图 (Gantt Chart)",
        "timeline": "时间线 (Timeline)", "kanban": "看板 (Kanban)",
        "complex": "复杂示例", "radar": "雷达图 (Radar Chart)",
        "xy": "XY图 (XY Chart)",
    ]
    private let categoryOrder = ["flowchart", "sequence", "pie", "gantt", "timeline",
                                 "kanban", "complex", "radar", "xy"]

    var body: some View {
        Group {
            if let error = catalog.error {
                ContentUnavailableView("Mermaid gallery unavailable", systemImage: "exclamationmark.triangle",
                                       description: Text(error))
            } else if catalog.examples.indices.contains(selectedIndex) {
                galleryContent(catalog.examples[selectedIndex])
            }
        }
        .navigationTitle("Mermaid 图表测试")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(isDark ? "Light" : "Dark", systemImage: isDark ? "sun.max" : "moon") {
                    isDark.toggle()
                }
                .accessibilityIdentifier("mermaid-theme")
            }
        }
        .preferredColorScheme(isDark ? .dark : .light)
    }

    private func galleryContent(_ example: MermaidGalleryExample) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    categoryMenu
                    Spacer()
                    Text("\(selectedIndex + 1)/\(catalog.examples.count)")
                        .font(.subheadline.monospacedDigit())
                        .accessibilityIdentifier("mermaid-position")
                        .accessibilityValue(lastTappedNodeID.map { "Last tapped node: \($0)" } ?? "")
                }
                Text(example.title).font(.title3.bold()).accessibilityIdentifier("mermaid-title")
                Text(example.description).foregroundStyle(.secondary)
                if let diagram = MermaidParser.parse(example.code) {
                    InteractiveMermaidDiagramView(diagram: diagram, onNodeTap: showNodeFeedback)
                        .frame(height: 600)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(isDark ? Color(red: 13 / 255, green: 17 / 255, blue: 23 / 255) : .white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    ContentUnavailableView("Diagram not supported yet", systemImage: "curlybraces",
                                           description: Text("The original Mermaid source is available below."))
                }
                HStack {
                    Button("View source") { showSource = true }
                    Button("Copy source") { UIPasteboard.general.string = example.code }
                        .accessibilityIdentifier("mermaid-copy")
                }
                .buttonStyle(.bordered)
                Text(example.code)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityIdentifier("mermaid-source")
                HStack {
                    Button("Previous", systemImage: "chevron.left") { selectedIndex -= 1 }
                        .disabled(selectedIndex == 0)
                        .accessibilityIdentifier("mermaid-previous")
                    Spacer()
                    Button("Next", systemImage: "chevron.right") { selectedIndex += 1 }
                        .disabled(selectedIndex == catalog.examples.count - 1)
                        .accessibilityIdentifier("mermaid-next")
                }
                .buttonStyle(.bordered)
            }
            .padding()
        }
        .overlay(alignment: .bottom) {
            if let nodeFeedback {
                Text(nodeFeedback)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.black.opacity(0.85), in: Capsule())
                    .padding(.bottom, 12)
                    .accessibilityIdentifier("mermaid-node-feedback")
            }
        }
        .onDisappear { feedbackTask?.cancel() }
        .onChange(of: selectedIndex) { _, _ in
            feedbackTask?.cancel()
            nodeFeedback = nil
            lastTappedNodeID = nil
        }
        .sheet(isPresented: $showSource) {
            NavigationStack {
                ScrollView {
                    Text(example.code)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .navigationTitle("Mermaid Source")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) { Button("Done") { showSource = false } }
                }
            }
        }
    }

    private func showNodeFeedback(_ id: String) {
        feedbackTask?.cancel()
        lastTappedNodeID = id
        nodeFeedback = "点击了节点: \(id)"
        feedbackTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            if !Task.isCancelled { nodeFeedback = nil }
        }
    }

    private var categoryMenu: some View {
        Menu("Examples") {
            ForEach(categoryOrder, id: \.self) { category in
                Section(categoryNames[category] ?? category) {
                    ForEach(catalog.examples.filter { $0.category == category }) { item in
                        Button(item.title) { selectedIndex = item.id - 1 }
                    }
                }
            }
        }
        .accessibilityIdentifier("mermaid-categories")
    }
}
