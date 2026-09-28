@testable import SmoothMarkdownDemo
import XCTest

final class DemoLocalizationFixtureTests: XCTestCase {
    func testFlutterLanguageFixtureIsBundledForEverySupportedLanguage() {
        let values: [(DemoLanguage, String)] = [
            (.zh, "明亮"), (.en, "Light"), (.ja, "ライト"),
            (.es, "Claro"), (.fr, "Clair"), (.ko, "라이트"),
        ]
        for (language, expected) in values {
            // drawer_light is absent from the Swift fallback dictionary.
            XCTAssertEqual(DemoLocalizations.text("drawer_light", in: language), expected)
        }
    }
}
