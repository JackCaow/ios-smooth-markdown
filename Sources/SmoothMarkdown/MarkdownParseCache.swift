import Foundation

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
    // HTML code tags require a source-preserving post-process, so HTML on/off
    // parse results use distinct keys within the same bounded cache.
    static let shared = MarkdownParseCache(maxSize: 200)

    private let lock = NSLock()
    private let maxSize: Int
    private struct Key: Hashable {
        let source: String
        let enableHTML: Bool
    }
    private var documents: [Key: Document] = [:]
    private var usage: [Key] = [] // least recently used first
    private var hitCount = 0
    private var missCount = 0

    init(maxSize: Int) {
        precondition(maxSize > 0)
        self.maxSize = maxSize
    }

    func parse(_ source: String, enableHTML: Bool = false) -> Document {
        lock.lock()
        defer { lock.unlock() }
        let key = Key(source: source, enableHTML: enableHTML)
        if let document = documents[key] {
            hitCount += 1
            usage.removeAll { $0 == key }
            usage.append(key)
            return document
        }
        let parsed = Document(parsing: source)
        let document = enableHTML ? HTMLCodeLiteralSyntax.restore(parsed, source: source) : parsed
        missCount += 1
        if usage.count == maxSize {
            documents.removeValue(forKey: usage.removeFirst())
        }
        documents[key] = document
        usage.append(key)
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
