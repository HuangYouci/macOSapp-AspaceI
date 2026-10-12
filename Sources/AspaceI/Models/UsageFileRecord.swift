import Foundation

/// 一個記錄檔已經讀出來的用量，存進快取；檔案變大時從 `offset` 接著讀。
/// 原始檔被官方客戶端清掉之後這份仍然保留，所以統計可以回溯到比記錄檔更早。
struct UsageFileRecord: Codable, Equatable, Sendable {
    var platform: PlatformKind
    /// Claude：對話編號（子代理的檔案歸到父對話）；Codex：檔名（不含副檔名）。
    var session: String
    var size = 0
    var modified = 0.0
    var offset = 0
    /// Claude 記錄檔內自帶的帳號編號，只有部分對話有。
    var accountUUID: String?
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

struct UsageCache: Codable, Equatable, Sendable {
    static let currentVersion = 1

    var version = UsageCache.currentVersion
    /// 記錄檔路徑 → 已讀出的用量。
    var files: [String: UsageFileRecord] = [:]
}

/// 用量屬於哪個帳號。記錄檔本身幾乎不帶帳號，只能在對話還在的時候從旁邊的資料記下來，
/// 所以這份對照表不能重建，獨立存一個檔。
struct UsageOwners: Codable, Equatable, Sendable {
    /// Claude 對話編號 → 平台帳號編號。
    var claude: [String: String] = [:]
    /// Codex 對話檔名 → AspaceI 帳號 id。
    var codex: [String: String] = [:]
}
