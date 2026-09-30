// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ios-smooth-markdown",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "SmoothMarkdown", targets: ["SmoothMarkdown"])],
    dependencies: [
        .package(url: "https://github.com/swhitty/SwiftDraw.git", from: "0.29.0"),
        .package(url: "https://github.com/gonzalezreal/swiftui-math.git", from: "0.1.0")
    ],
    targets: [
        .target(name: "SmoothMarkdown", dependencies: [
            .product(name: "SwiftDraw", package: "SwiftDraw"),
            .product(name: "SwiftUIMath", package: "swiftui-math")
        ]),
        .testTarget(name: "SmoothMarkdownTests", dependencies: [
            "SmoothMarkdown",
            .product(name: "SwiftDraw", package: "SwiftDraw")
        ], resources: [.process("Fixtures")])
    ]
)
