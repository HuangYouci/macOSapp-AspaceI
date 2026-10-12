import Foundation

/// 一個記錄檔已經讀出來的用量；檔案變大時從 `offset` 接著讀。
/// 原始檔被刪掉之後這份仍然保留：使用者會定期刪對話，統計不能跟著消失。
struct UsageFileRecord: Codable, Equatable, Sendable {
    var platform: PlatformKind
    /// Claude：對話編號（子代理的檔案歸到父對話）；Codex：檔名（不含副檔名）。
    var session: String
    var size = 0
    var modified = 0.0
    var offset = 0
    var codexState: UsageLineParser.CodexState?

    // 每筆用量拆成平行陣列：幾十萬筆存成物件陣列，快取檔會大好幾倍。
    var modelNames: [String] = []
    /// 去重鍵的位元樣式；binary plist 存不了超過 Int64 的無號整數。
    var keys: [Int64] = []
    var times: [Int] = []
    var models: [Int] = []
    var input: [Int] = []
    var output: [Int] = []
    var cacheRead: [Int] = []
    var cacheWrite: [Int] = []

    var count: Int { keys.count }

    func entry(at index: Int) -> UsageEntry {
        UsageEntry(
            key: UInt64(bitPattern: keys[index]),
            time: times[index],
            model: modelNames[models[index]],
            tokens: TokenCounts(input: input[index], output: output[index], cacheRead: cacheRead[index], cacheWrite: cacheWrite[index])
        )
    }

    mutating func append(_ entry: UsageEntry) {
        keys.append(Int64(bitPattern: entry.key))
        times.append(entry.time)
        models.append(modelIndex(entry.model))
        input.append(entry.tokens.input)
        output.append(entry.tokens.output)
        cacheRead.append(entry.tokens.cacheRead)
        cacheWrite.append(entry.tokens.cacheWrite)
    }

    mutating func replace(at index: Int, with entry: UsageEntry) {
        times[index] = entry.time
        models[index] = modelIndex(entry.model)
        input[index] = entry.tokens.input
        output[index] = entry.tokens.output
        cacheRead[index] = entry.tokens.cacheRead
        cacheWrite[index] = entry.tokens.cacheWrite
    }

    private mutating func modelIndex(_ name: String) -> Int {
        if let index = modelNames.firstIndex(of: name) { return index }
        modelNames.append(name)
        return modelNames.count - 1
    }
}

/// AspaceI 自己保存的用量歷史。記錄檔刪了這裡還在，所以不是可以隨意丟掉重建的快取。
struct UsageHistory: Codable, Equatable, Sendable {
    static let currentVersion = 1

    var version = UsageHistory.currentVersion
    /// 記錄檔路徑 → 已讀出的用量。
    var files: [String: UsageFileRecord] = [:]
}
