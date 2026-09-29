import Foundation
import Markdown

/// Occupancy of the reader's bounded Markdown parse cache.
public struct MarkdownCacheStatistics: Equatable {
    public let size: Int
    public let maxSize: Int
    public let hits: Int
    public let misses: Int
    public var utilization: Double { maxSize == 0 ? 0 : Double(size) / Double(maxSize) }
}

/// Caches parsed documents by their exact source. Parsing and bookkeeping share
/// a lock so concurrent readers cannot race or insert the same document twice.
final class MarkdownParseCache {
    // Flutter exposes two 100-entry caches (HTML on/off). Native parsing is
    // configuration independent, so one 200-entry cache has the same total cap.
    static let shared = MarkdownParseCache(maxSize: 200)

    private let lock = NSLock()
    private let maxSize: Int
    private var documents: [String: Document] = [:]
    private var usage: [String] = [] // least recently used first
    private var hitCount = 0
    private var missCount = 0

    init(maxSize: Int) {
        precondition(maxSize > 0)
        self.maxSize = maxSize
    }

    func parse(_ source: String) -> Document {
        lock.lock()
        defer { lock.unlock() }
        if let document = documents[source] {
            hitCount += 1
            usage.removeAll { $0 == source }
            usage.append(source)
            return document
        }
        let document = Document(parsing: source)
        missCount += 1
        if usage.count == maxSize {
            documents.removeValue(forKey: usage.removeFirst())
        }
        documents[source] = document
        usage.append(source)
        return document
    }

    var statistics: MarkdownCacheStatistics {
        lock.lock()
        defer { lock.unlock() }
        return MarkdownCacheStatistics(size: documents.count, maxSize: maxSize,
                                       hits: hitCount, misses: missCount)
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        documents.removeAll()
        usage.removeAll()
        hitCount = 0
        missCount = 0
    }
}
