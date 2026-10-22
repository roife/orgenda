import Foundation

struct CachedWorkspaceBlob {
    var data: Data?
    var text: String?
    var byteCount: Int { data?.count ?? text?.utf8.count ?? 0 }
}

/// System-managed cache with advisory budgets. Text replaces its decoded Data
/// so the cache retains one representation of a text blob.
final class WorkspaceBlobCache {
    private final class Entry {
        let value: CachedWorkspaceBlob
        init(_ value: CachedWorkspaceBlob) { self.value = value }
    }
    private let cache = NSCache<NSString, Entry>()
    private let byteLimit: Int

    init(byteLimit: Int = 16 * 1024 * 1024) {
        self.byteLimit = byteLimit
        cache.totalCostLimit = byteLimit
        cache.countLimit = 4096
    }

    subscript(hash: String) -> CachedWorkspaceBlob? {
        get { cache.object(forKey: hash as NSString)?.value }
        set {
            guard let value = newValue, value.byteCount <= byteLimit else {
                cache.removeObject(forKey: hash as NSString)
                return
            }
            cache.setObject(Entry(value), forKey: hash as NSString, cost: value.byteCount)
        }
    }
}
