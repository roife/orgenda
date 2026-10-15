import Foundation

struct CachedWorkspaceBlob {
    var data: Data?
    var text: String?
    var byteCount: Int { data?.count ?? text?.utf8.count ?? 0 }
}

/// Actor-owned LRU with constant-time access and eviction. Text replaces its
/// decoded Data so the cache retains one representation of a text blob.
final class WorkspaceBlobCache {
    private final class Node {
        let hash: String
        var value: CachedWorkspaceBlob
        weak var previous: Node?
        var next: Node?
        init(hash: String, value: CachedWorkspaceBlob) { self.hash = hash; self.value = value }
    }
    private let byteLimit: Int
    private let countLimit = 4096
    private var nodes: [String: Node] = [:]
    private var head: Node?
    private var tail: Node?
    private var bytes = 0

    init(byteLimit: Int = 16 * 1024 * 1024) { self.byteLimit = byteLimit }

    subscript(hash: String) -> CachedWorkspaceBlob? {
        get {
            guard let node = nodes[hash] else { return nil }
            detach(node)
            prepend(node)
            return node.value
        }
        set {
            if let old = nodes.removeValue(forKey: hash) { detach(old); bytes -= old.value.byteCount }
            guard let value = newValue, value.byteCount <= byteLimit else { return }
            let node = Node(hash: hash, value: value)
            nodes[hash] = node
            prepend(node)
            bytes += value.byteCount
            while bytes > byteLimit || nodes.count > countLimit {
                guard let last = tail else { break }
                detach(last)
                nodes.removeValue(forKey: last.hash)
                bytes -= last.value.byteCount
            }
        }
    }

    private func detach(_ node: Node) {
        if let previous = node.previous { previous.next = node.next } else { head = node.next }
        if let next = node.next { next.previous = node.previous } else { tail = node.previous }
        node.previous = nil
        node.next = nil
    }

    private func prepend(_ node: Node) {
        node.next = head
        head?.previous = node
        head = node
        if tail == nil { tail = node }
    }
}
