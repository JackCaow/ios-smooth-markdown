import CryptoKit
import Foundation

struct DemoExample: Identifiable {
    let id: String
    let title: String
    let markdown: String
}

struct DemoExampleCatalog {
    let examples: [DemoExample]
    let error: String?

    private struct Manifest: Decodable {
        let examples: [Entry]
        struct Entry: Decodable {
            let id: String
            let title: String
            let file: String
            let sha256: String
        }
    }

    static func load(bundle: Bundle = .main) -> Self {
        guard let manifestURL = resource("manifest.json", bundle: bundle),
              let manifestData = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: manifestData) else {
            return .init(examples: [], error: "Examples/manifest.json is missing or invalid")
        }
        var examples: [DemoExample] = []
        for entry in manifest.examples {
            guard let url = resource(entry.file, bundle: bundle),
                  let data = try? Data(contentsOf: url),
                  let markdown = String(data: data, encoding: .utf8) else {
                return .init(examples: examples, error: "Missing example: \(entry.file)")
            }
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard digest == entry.sha256 else {
                return .init(examples: examples, error: "Example checksum mismatch: \(entry.file)")
            }
            examples.append(.init(id: entry.id, title: entry.title, markdown: markdown))
        }
        return .init(examples: examples, error: nil)
    }

    private static func resource(_ filename: String, bundle: Bundle) -> URL? {
        let name = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        return bundle.url(forResource: name, withExtension: ext, subdirectory: "Examples")
            ?? bundle.url(forResource: name, withExtension: ext)
    }
}
