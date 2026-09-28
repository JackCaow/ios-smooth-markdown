import SwiftUI

@main
struct SmoothMarkdownDemoApp: App {
    var body: some Scene {
        WindowGroup {
            if ProcessInfo.processInfo.arguments.contains(where: { $0.hasSuffix("-fixture") }) {
                FixtureDemoView()
            } else {
                DemoHomeView()
            }
        }
    }
}
