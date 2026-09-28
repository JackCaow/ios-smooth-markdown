// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ios-smooth-markdown",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "SmoothMarkdown", targets: ["SmoothMarkdown"])],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.8.0")
    ],
    targets: [
        .target(name: "SmoothMarkdown", dependencies: [
            .product(name: "Markdown", package: "swift-markdown")
        ]),
        .testTarget(name: "SmoothMarkdownTests", dependencies: [
            "SmoothMarkdown",
            .product(name: "Markdown", package: "swift-markdown")
        ])
    ]
)
