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
        var sharedExtensions = false
        var pluginIdentity: ObjectIdentifier? = nil
        var pluginRevision: UInt64 = 0
    }
    private var documents: [Key: Document] = [:]
    // Retaining live identities prevents a deallocated registry's address from
    // being reused by a different configuration while its cache key survives.
    private var registryOwners: [Key: ParserPluginRegistry] = [:]
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
            removeOldest()
        }
        documents[key] = document
        usage.append(key)
        return document
    }

    /// Host plugin callbacks execute outside the cache lock because they may
    /// query library state. Cache identity includes the live registry revision.
    func parseShared(_ source: String, plugins: ParserPluginRegistry?, enableHTML: Bool) -> Document? {
        let key = Key(source: source, enableHTML: enableHTML, sharedExtensions: true,
                      pluginIdentity: plugins.map(ObjectIdentifier.init), pluginRevision: plugins?.revision ?? 0)
        lock.lock()
        if let document = documents[key] {
            hitCount += 1; usage.removeAll { $0 == key }; usage.append(key); lock.unlock(); return document
        }
        lock.unlock()
        guard let parsed = PluginSharedSyntax.document(source, registry: plugins, enableHTML: enableHTML) else { return nil }
        lock.lock(); defer { lock.unlock() }
        if let document = documents[key] {
            hitCount += 1; usage.removeAll { $0 == key }; usage.append(key); return document
        }
        missCount += 1
        if usage.count == maxSize { removeOldest() }
        documents[key] = parsed; registryOwners[key] = plugins; usage.append(key)
        return parsed
    }

    private func removeOldest() {
        let key = usage.removeFirst(); documents.removeValue(forKey: key); registryOwners.removeValue(forKey: key)
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
        registryOwners.removeAll()
        usage.removeAll()
        hitCount = 0
        missCount = 0
    }
}
