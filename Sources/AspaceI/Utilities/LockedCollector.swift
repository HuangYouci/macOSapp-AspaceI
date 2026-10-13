import Foundation

/// 平行工作同時回報結果，用鎖保護。只在 `concurrentPerform` 這類同步等全部結束的場合使用。
final class LockedCollector<Item>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Item] = []

    var items: [Item] {
        lock.withLock { storage }
    }

    func append(_ item: Item) {
        lock.withLock { storage.append(item) }
    }

    func append(contentsOf items: [Item]) {
        lock.withLock { storage.append(contentsOf: items) }
    }
}
