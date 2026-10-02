# 0.4.0 Mermaid rendering repair

This release consolidates the ten-diagram iOS screenshot review: flowchart, sequence, class, state, ER, Gantt, pie, Git history, mindmap and timeline.

- Bounded fence viewports clip their own painting, preserve complete container borders and keep both axes reachable.
- Short graphs center; graph canvases hug actual content and empty class/ER compartments do not add empty bands.
- Rounded/curved routes separate node-side ports and place arrow markers along endpoint tangents. Labels avoid nodes and contribute to canvas bounds.
- Inline pie titles and Unicode sequence aliases parse correctly. Basic Git histories and single-tree mindmaps render natively.
- Public Mermaid tokens expose routing, corner radius, stroke width, arrow size and label padding. Existing initializer identities remain unchanged; exhaustive MermaidKind switches must handle two new cases.

No external package dependency is added. SwiftPM remains iOS 17+/macOS 14+; CocoaPods remains iOS 17+ and includes the owned Rust XCFramework.

Candidate acceptance includes 52 concentrated Mermaid tests, seven affected parser/specialty-boundary tests, unchanged public consumers and reviewed additive API symbols. Actual-scene Simulator gates cover ten diagrams, static/completed equivalence and four viewport/dynamic-type boundaries. Screenshot fixtures distinguish exact visible syntax from reconstructed labels; private history is not rewritten or committed.

## Publication and public consumer verification

- GitHub tag/release `0.4.0` points to `be4b4920a0d70cbe66b9a9cc9448e8293e691949`; library PR #120 is merged.
- CocoaPods Trunk lists `0.4.0`, registered on 2026-10-02 at 14:58:33 UTC. Local and remote-tag pod validation passed. The initial command timed out during its post-publication GitHub check; Trunk registration was independently confirmed with `pod trunk info SmoothMarkdown`.
- The complete 635-test Swift suite passed with the pinned official CommonMark fixture and required Rust backend. The six library Demo platform classes passed 46 tests with zero failures.
- The Remote App actually resolved the public `0.4.0` tag with a clean checkout and no local override. Its 107 source files and 11 artifact files match the validated tree byte-for-byte.
- The public App batch passed both ten-diagram rendering/completion and localized fallback tests: 2 tests, zero failures. All 26 exported public screenshots match the independently reviewed candidate; heading/prose boundaries and six horizontal endpoints are covered.
- Runtime evidence is Simulator evidence. Physical-device verification and production App deployment are separate acceptance steps. The App integration follow-up is MR !2122.
