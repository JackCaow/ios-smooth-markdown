// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ios-smooth-markdown",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "SmoothMarkdownCore", targets: ["SmoothMarkdownCore"]),
        .library(name: "SmoothMarkdown", targets: ["SmoothMarkdown"])
    ],
    dependencies: [],
    targets: [
        .binaryTarget(name: "CSmoothMarkdownRust", path: "Artifacts/CSmoothMarkdownRust.xcframework"),
        .target(name: "SmoothMarkdownCore", dependencies: ["CSmoothMarkdownRust"]),
        .target(name: "SmoothMarkdown", dependencies: ["SmoothMarkdownCore"]),
        .testTarget(name: "SmoothMarkdownTests", dependencies: ["SmoothMarkdown"], resources: [.process("Fixtures")])
    ]
)
