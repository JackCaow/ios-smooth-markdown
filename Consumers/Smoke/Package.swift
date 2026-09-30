// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "PublicLibraryConsumers",
    platforms: [.macOS(.v14), .iOS(.v17)],
    dependencies: [.package(name: "ios-smooth-markdown", path: "../..")],
    targets: [
        .executableTarget(name: "CoreConsumer", dependencies: [.product(name: "SmoothMarkdownCore", package: "ios-smooth-markdown")]),
        .executableTarget(name: "ReaderConsumer", dependencies: [.product(name: "SmoothMarkdown", package: "ios-smooth-markdown")])
    ]
)
