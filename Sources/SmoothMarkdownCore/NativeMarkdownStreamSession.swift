import Foundation
#if canImport(CSmoothMarkdownRust)
import CSmoothMarkdownRust
#endif

/// Internal single-owner stream bridge. Call synchronously from one execution context.
@_spi(ReaderInternals) public final class NativeMarkdownStreamSession {
    @_spi(ReaderInternals) public struct Snapshot {
        public let tree: NativeMarkdownNode
        public let retainedBlocks: Int
    }
    private var children: [NativeMarkdownNode] = []
    #if canImport(CSmoothMarkdownRust)
    private var handle: UnsafeMutableRawPointer?
    #endif

    public init() {}

    deinit {
        #if canImport(CSmoothMarkdownRust)
        if let handle { smr_stream_free(handle) }
        #endif
    }

    public func reset() {
        children.removeAll()
        #if canImport(CSmoothMarkdownRust)
        if let handle { smr_stream_free(handle) }
        handle = nil
        #endif
    }

    public func update(_ source: String) -> Snapshot? {
        #if canImport(CSmoothMarkdownRust)
        guard RustMarkdownBridge.isAvailable else { reset(); return nil }
        if handle == nil { handle = smr_stream_new(3) }
        guard let handle else { return nil }
        let units = Array(source.utf16)
        var output = SmrBuffer(data: nil, len: 0, owner: nil)
        var retained: UInt32 = 0
        let status = units.withUnsafeBufferPointer {
            smr_stream_update_utf16(handle, $0.baseAddress, $0.count, &output, &retained)
        }
        // The decoder materializes owned nodes synchronously before this buffer is freed.
        defer { smr_buffer_free(&output) }
        guard status == 0, let pointer = output.data, output.len <= 64 * 1024 * 1024,
              retained <= children.count,
              let delta = try? RustMarkdownWire.decode(Data(bytesNoCopy: UnsafeMutableRawPointer(mutating: pointer), count: output.len, deallocator: .none), source: source),
              delta.kind == .document else { reset(); return nil }
        children = Array(children.prefix(Int(retained))) + delta.children
        let tree = NativeMarkdownNode(kind: .document, source: source,
                                      sourceRange: NSRange(location: 0, length: source.utf16.count),
                                      children: children)
        return Snapshot(tree: tree, retainedBlocks: Int(retained))
        #else
        return nil
        #endif
    }
}
