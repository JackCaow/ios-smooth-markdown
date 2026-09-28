import CryptoKit
import Foundation

/// Exact runtime strings from Flutter's static feature demos.
struct DemoPageCatalog {
    let pages: [String: String]
    let error: String?

    private struct Manifest: Decodable {
        let pages: [Entry]
        struct Entry: Decodable {
            let id: String
            let file: String
            let sha256: String
        }
    }

    static func load(bundle: Bundle = .main) -> Self {
        guard let url = resource("pages.json", bundle: bundle),
              let data = try? Data(contentsOf: url),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data) else {
            return .init(pages: [:], error: "Demo page manifest is missing or invalid")
        }
        var pages: [String: String] = [:]
        for entry in manifest.pages {
            guard let url = resource(entry.file, bundle: bundle),
                  let data = try? Data(contentsOf: url),
                  let markdown = String(data: data, encoding: .utf8) else {
                return .init(pages: [:], error: "Missing demo page: \(entry.file)")
            }
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard digest == entry.sha256 else {
                return .init(pages: [:], error: "Demo page checksum mismatch: \(entry.file)")
            }
            pages[entry.id] = markdown
        }
        guard Set(pages.keys) == Set(["math", "footnote", "html", "plugin", "editor"]) else {
            return .init(pages: [:], error: "Demo page catalog is incomplete")
        }
        return .init(pages: pages, error: nil)
    }

    func markdown(for feature: DemoFeature) -> String? {
        let id: String
        switch feature {
        case .math: id = "math"
        case .footnotes: id = "footnote"
        case .html: id = "html"
        case .plugins: id = "plugin"
        default: return nil
        }
        return pages[id]
    }

    private static func resource(_ filename: String, bundle: Bundle) -> URL? {
        let name = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        return bundle.url(forResource: name, withExtension: ext, subdirectory: "Examples/Pages")
            ?? bundle.url(forResource: name, withExtension: ext, subdirectory: "Pages")
            ?? bundle.url(forResource: name, withExtension: ext)
    }
}
