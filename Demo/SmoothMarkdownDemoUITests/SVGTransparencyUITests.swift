import CoreGraphics
import XCTest

final class SVGTransparencyUITests: XCTestCase {
    func testComplexSVGShowsHostBackgroundThroughTransparentPixels() {
        let app = XCUIApplication()
        app.launchArguments = ["-svg-transparency-probe"]
        app.launch()
        XCTAssertTrue(app.staticTexts["SVG transparency probe"].waitForExistence(timeout: 10))

        var screenshot = app.screenshot()
        var counts = colorCounts(screenshot)
        for _ in 0..<12 where counts.green < 10_000 {
            Thread.sleep(forTimeInterval: 0.5)
            screenshot = app.screenshot()
            counts = colorCounts(screenshot)
        }
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "Live WebKit SVG transparency over magenta host"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertGreaterThan(counts.green, 10_000, "SVG paint must render")
        XCTAssertGreaterThan(counts.magenta, 10_000, "Transparent SVG pixels must expose the host background")
    }

    private func colorCounts(_ screenshot: XCUIScreenshot) -> (green: Int, magenta: Int) {
        guard let image = screenshot.image.cgImage else { return (0, 0) }
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let info = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(data: &pixels, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info) else { return (0, 0) }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var green = 0, magenta = 0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let red = pixels[index], g = pixels[index + 1], blue = pixels[index + 2]
            if g > 220 && red < 40 && blue < 40 { green += 1 }
            if red > 220 && g < 40 && blue > 220 { magenta += 1 }
        }
        return (green, magenta)
    }
}
