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
        .target(name: "SmoothMarkdownCore"),
        .target(name: "SmoothMarkdown", dependencies: ["SmoothMarkdownCore"]),
        .testTarget(name: "SmoothMarkdownTests", dependencies: ["SmoothMarkdown"], resources: [.process("Fixtures")])
    ]
)
