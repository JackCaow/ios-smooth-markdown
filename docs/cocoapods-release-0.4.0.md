# 0.4.0 Mermaid rendering repair

This release consolidates the ten-diagram iOS screenshot review: flowchart, sequence, class, state, ER, Gantt, pie, Git history, mindmap and timeline.

- Bounded fence viewports clip their own painting, preserve complete container borders and keep both axes reachable.
- Short graphs center; graph canvases hug actual content and empty class/ER compartments do not add empty bands.
- Rounded/curved routes separate node-side ports and place arrow markers along endpoint tangents. Labels avoid nodes and contribute to canvas bounds.
- Inline pie titles and Unicode sequence aliases parse correctly. Basic Git histories and single-tree mindmaps render natively.
- Public Mermaid tokens expose routing, corner radius, stroke width, arrow size and label padding. Existing initializer identities remain unchanged; exhaustive MermaidKind switches must handle two new cases.

No external package dependency is added. SwiftPM remains iOS 17+/macOS 14+; CocoaPods remains iOS 17+ and includes the owned Rust XCFramework.

Candidate acceptance includes 52 concentrated Mermaid tests, seven affected parser/specialty-boundary tests, unchanged public consumers and reviewed additive API symbols. Actual-scene Simulator gates cover ten diagrams, static/completed equivalence and four viewport/dynamic-type boundaries. Screenshot fixtures distinguish exact visible syntax from reconstructed labels; private history is not rewritten or committed.

Publication status and exact public consumer evidence are appended after release verification.
