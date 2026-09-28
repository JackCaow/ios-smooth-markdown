import Darwin.Mach
import SmoothMarkdown
import SwiftUI
import UIKit

/// Manual Simulator fixture for reader layout and real-time stream checks.
struct PerformanceDemoView: View {
    private enum Mode: String, CaseIterable { case staticDocument = "Static", rapidStream = "Rapid stream" }

    @State private var mode: Mode = .staticDocument
    @State private var runID = UUID()
    @State private var startTime = CACurrentMediaTime()
    @State private var firstAppearMillis: Int?
    @State private var completionStatus: String?
    @StateObject private var frames = ReaderFrameProbe()
    private let throttleMillis = Int64(ProcessInfo.processInfo.environment["SMOOTH_PERF_THROTTLE_MS"] ?? "50") ?? 50

    private static let fixture: String = {
        guard let url = Bundle.main.url(forResource: "FlutterREADME", withExtension: "md"),
              let source = try? String(contentsOf: url, encoding: .utf8) else {
            return "Fixture missing: FlutterREADME.md"
        }
        return Array(repeating: source, count: 4).joined(separator: "\n\n")
    }()

    var body: some View {
        let fixture = Self.fixture
        VStack(spacing: 4) {
            HStack {
                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                Button("Run") { run() }
            }
            .padding(.horizontal)
            HStack {
                Text("\(fixture.utf8.count) B")
                Text("\(throttleMillis) ms")
                Text("First appear: \(firstAppearMillis.map(String.init) ?? "—") ms")
                Text("RSS: \(ReaderFrameProbe.footprintMiB()) MiB")
                Spacer()
                Button(frames.isRecording ? "Stop frames" : "Record frames") {
                    if frames.isRecording { frames.stop() } else { frames.start() }
                }
            }
            .font(.caption2)
            .padding(.horizontal)
            if let summary = frames.summary {
                Text(summary).font(.caption2).accessibilityIdentifier("frameSummary")
            }
            if let completionStatus {
                Text(completionStatus).font(.caption2).accessibilityIdentifier("streamCompletion")
            }
            Group {
                if mode == .staticDocument {
                    SmoothMarkdownView(markdown: fixture)
                } else {
                    StreamMarkdownView(chunks: PerformanceChunks(source: fixture, throttleMillis: throttleMillis), streamID: runID.uuidString,
                                       throttleMillis: throttleMillis, onComplete: { final in
                        completionStatus = final == fixture ? "Complete 68,282 B" : "Mismatch: \(final.utf8.count) B"
                        NSLog("PERF visibleComplete throttleMs=%lld bytes=%d exact=%d", throttleMillis,
                              final.utf8.count, final == fixture ? 1 : 0)
                    })
                }
            }
            .onAppear {
                firstAppearMillis = Int((CACurrentMediaTime() - startTime) * 1000)
                NSLog("PERF firstAppear mode=%@ ms=%d bytes=%d rssMiB=%d", mode.rawValue,
                      firstAppearMillis ?? -1, fixture.utf8.count, ReaderFrameProbe.footprintMiB())
            }
            .id(runID)
        }
        .onChange(of: mode) { _, _ in run() }
    }

    private func run() {
        firstAppearMillis = nil
        completionStatus = nil
        startTime = CACurrentMediaTime()
        if mode == .rapidStream { frames.start() }
        runID = UUID()
    }
}

/// Iterator creation is lazy so SwiftUI body reevaluation does not start extra producers.
private struct PerformanceChunks: AsyncSequence {
    typealias Element = String
    let source: String
    let throttleMillis: Int64

    struct AsyncIterator: AsyncIteratorProtocol {
        let characters: [Character]
        let byteCount: Int
        let throttleMillis: Int64
        var offset = 0
        var reportedCompletion = false

        mutating func next() async -> String? {
            guard !Task.isCancelled else { return nil }
            guard offset < characters.count else {
                if !reportedCompletion {
                    NSLog("PERF sourceComplete throttleMs=%lld bytes=%d", throttleMillis, byteCount)
                    reportedCompletion = true
                }
                return nil
            }
            try? await Task.sleep(nanoseconds: 1_000_000)
            let end = Swift.min(offset + 32, characters.count)
            let chunk = String(characters[offset..<end])
            offset = end
            return chunk
        }
    }

    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(characters: Array(source), byteCount: source.utf8.count, throttleMillis: throttleMillis)
    }
}

@MainActor
private final class ReaderFrameProbe: NSObject, ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var summary: String?
    private var link: CADisplayLink?
    private var timestamps: [CFTimeInterval] = []

    func start() {
        stopLink()
        timestamps = []
        summary = nil
        isRecording = true
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        stopLink()
        isRecording = false
        let gaps = zip(timestamps.dropFirst(), timestamps).map { ($0 - $1) * 1000 }.sorted()
        guard !gaps.isEmpty else { summary = "No frames"; return }
        let p95 = gaps[min(gaps.count - 1, Int(Double(gaps.count) * 0.95))]
        let over25 = gaps.filter { $0 > 25 }.count
        summary = String(format: "frames=%d p95=%.1f ms >25ms=%d max=%.1f ms RSS=%d MiB",
                         gaps.count, p95, over25, gaps.last ?? 0, Self.footprintMiB())
        NSLog("PERF frameSummary %@", summary ?? "")
    }

    private func stopLink() { link?.invalidate(); link = nil }
    @objc private func tick(_ link: CADisplayLink) { timestamps.append(link.timestamp) }

    static func footprintMiB() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Int(info.phys_footprint / 1_048_576) : -1
    }
}
