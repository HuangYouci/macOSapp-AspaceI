import Foundation
import os

/// 一次掃描要讀哪些位置。全部由外部給定，測試才能指到臨時資料夾。
struct UsageScanContext: Sendable {
    struct CodexHome: Sendable {
        var url: URL
        /// 目前登入這個資料夾的 AspaceI 帳號。
        var accountID: UUID?
    }

    /// Claude Code 的 `projects` 資料夾；所有 Claude 桌面實例共用同一個。
    var claudeProjectRoots: [URL]
    /// 各個 Claude 桌面 App（預設與每個實例）的 `claude-code-sessions` 資料夾。
    var claudeSessionIndexRoots: [URL]
    var codexHomes: [CodexHome]
    /// 快取與歸屬對照表存放的資料夾。
    var storeDirectory: URL
    var timeZone: TimeZone = .current
    var now = Date()
}

/// 讀 Claude Code 與 Codex 留在這台 Mac 的對話紀錄，彙總成每日用量。只讀本機檔案，不連網。
actor UsageScanService {
    static let shared = UsageScanService()

    /// 對話檔在這段時間內寫過，才把它記給目前登入的帳號；更早的檔案不知道當時是誰。
    static let liveWindow: TimeInterval = 15 * 60

    private static let cacheFileName = "usage-cache.plist"
    private static let ownersFileName = "usage-owners.json"

    private var cache: UsageCache?
    private var owners: UsageOwners?
    private let logger = Logger(subsystem: "com.huangyouci.AspaceI", category: "Usage")

    struct DiscoveredFile: Equatable, Sendable {
        var url: URL
        var platform: PlatformKind
        var session: String
        var size: Int
        var modified: Double
    }

    func scan(_ context: UsageScanContext) async throws -> [UsageRecord] {
        var cache = try self.cache ?? Self.loadCache(in: context.storeDirectory)
        var owners = try self.owners ?? Self.loadOwners(in: context.storeDirectory)
        let files = Self.discover(context)

        let pending = files.filter { file in
            guard let record = cache.files[file.url.path] else { return true }
            return record.size != file.size || record.modified != file.modified
        }
        let existing = cache.files
        let logger = logger
        let parsed = await withTaskGroup(of: (String, UsageFileRecord?).self) { group in
            var iterator = pending.makeIterator()
            var results: [String: UsageFileRecord] = [:]
            func addNext() {
                guard let file = iterator.next() else { return }
                let previous = existing[file.url.path]
                group.addTask(priority: .utility) {
                    do {
                        return (file.url.path, try Self.parse(file, existing: previous))
                    } catch {
                        logger.error("UsageScanService.scan | 讀取 \(file.url.lastPathComponent, privacy: .public) 失敗：\(error.localizedDescription, privacy: .public)")
                        return (file.url.path, nil)
                    }
                }
            }
            for _ in 0..<max(2, min(6, ProcessInfo.processInfo.activeProcessorCount - 2)) { addNext() }
            for await (path, record) in group {
                if let record { results[path] = record }
                addNext()
            }
            return results
        }
        try Task.checkCancellation()

        cache.files.merge(parsed) { _, new in new }
        var updatedOwners = owners
        updatedOwners.claude.merge(Self.claudeOwners(indexRoots: context.claudeSessionIndexRoots)) { _, new in new }
        Self.recordCodexOwners(&updatedOwners, files: files, context: context)

        try FileManager.default.createDirectory(at: context.storeDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        if !parsed.isEmpty || self.cache == nil {
            try Self.save(cache, in: context.storeDirectory)
        }
        if updatedOwners != owners || self.owners == nil {
            try Self.save(updatedOwners, in: context.storeDirectory)
        }
        owners = updatedOwners
        self.cache = cache
        self.owners = owners
        return Self.aggregate(files: cache.files, owners: owners, timeZone: context.timeZone)
    }

    // MARK: - 找檔案

    static func discover(_ context: UsageScanContext) -> [DiscoveredFile] {
        var result: [DiscoveredFile] = []
        for root in context.claudeProjectRoots {
            for (url, size, modified) in jsonlFiles(under: root) {
                result.append(DiscoveredFile(url: url, platform: .claude, session: claudeSession(for: url), size: size, modified: modified))
            }
        }
        for home in context.codexHomes {
            for folder in ["sessions", "archived_sessions"] {
                for (url, size, modified) in jsonlFiles(under: home.url.appending(path: folder, directoryHint: .isDirectory)) {
                    result.append(DiscoveredFile(url: url, platform: .codex, session: url.deletingPathExtension().lastPathComponent, size: size, modified: modified))
                }
            }
        }
        return result
    }

    /// 子代理的紀錄在 `<對話編號>/subagents/` 底下，歸到父對話；其餘以檔名為對話編號。
    static func claudeSession(for url: URL) -> String {
        let components = url.pathComponents
        if let index = components.lastIndex(of: "subagents"), index > 0 {
            return components[index - 1]
        }
        return url.deletingPathExtension().lastPathComponent
    }

    private static func jsonlFiles(under root: URL) -> [(URL, Int, Double)] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys) else { return [] }
        var result: [(URL, Int, Double)] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            result.append((url, values.fileSize ?? 0, values.contentModificationDate?.timeIntervalSince1970 ?? 0))
        }
        return result
    }

    // MARK: - 讀一個檔

    private static let claudeUsagePattern = "\"usage\":{"
    private static let claudeAccountPattern = "ccountUuid\":\""

    /// 檔案只會往後寫：有舊紀錄就從上次讀到的位置接著讀；檔案變小（被重寫）則整個重讀。
    static func parse(_ file: DiscoveredFile, existing: UsageFileRecord?) throws -> UsageFileRecord {
        var record = existing.flatMap { $0.platform == file.platform && $0.offset <= file.size ? $0 : nil }
            ?? UsageFileRecord(platform: file.platform, session: file.session)
        record.session = file.session
        switch file.platform {
        case .claude:
            var indexByKey: [Int64: Int] = [:]
            for (index, key) in record.keys.enumerated() { indexByKey[key] = index }
            let usagePattern = Data(claudeUsagePattern.utf8)
            let patterns = record.accountUUID == nil ? [claudeUsagePattern, claudeAccountPattern] : [claudeUsagePattern]
            record.offset = try UsageFileReader.scanLines(of: file.url, from: record.offset, patterns: patterns) { line in
                guard line.range(of: usagePattern) != nil else {
                    if record.accountUUID == nil { record.accountUUID = UsageLineParser.claudeAccountUUID(line: line) }
                    return
                }
                guard let entry = UsageLineParser.claudeEntry(line: line, sessionID: file.session) else { return }
                let key = Int64(bitPattern: entry.key)
                if let index = indexByKey[key] {
                    // 同一則回應逐段寫入，後面幾行的 output 才是完整的。
                    if entry.tokens.total > record.entry(at: index).tokens.total { record.replace(at: index, with: entry) }
                } else {
                    indexByKey[key] = record.count
                    record.append(entry)
                }
            }
        case .codex:
            var state = record.codexState ?? UsageLineParser.CodexState()
            record.offset = try UsageFileReader.scanLines(of: file.url, from: record.offset, patterns: ["\"token_count\"", "\"turn_context\""]) { line in
                if let entry = UsageLineParser.codexEntry(line: line, state: &state) { record.append(entry) }
            }
            record.codexState = state
        case .antigravity, .githubCopilot:
            break
        }
        record.size = file.size
        record.modified = file.modified
        return record
    }

    // MARK: - 歸屬

    /// 桌面 App 把每個對話記在 `claude-code-sessions/<帳號編號>/<組織>/local_*.json`，裡面的 `cliSessionId` 就是記錄檔的對話編號。
    /// 對話被封存或刪除後這個檔就不在了，所以每次掃描都把看得到的記下來。
    static func claudeOwners(indexRoots: [URL]) -> [String: String] {
        var result: [String: String] = [:]
        let manager = FileManager.default
        func directories(in url: URL) -> [URL] {
            ((try? manager.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey])) ?? [])
                .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        }
        for root in indexRoots {
            for account in directories(in: root) where UUID(uuidString: account.lastPathComponent) != nil {
                for organization in directories(in: account) {
                    let files = (try? manager.contentsOfDirectory(at: organization, includingPropertiesForKeys: nil)) ?? []
                    for file in files where file.lastPathComponent.hasPrefix("local_") && file.pathExtension == "json" {
                        guard let data = try? Data(contentsOf: file),
                              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                              let session = root["cliSessionId"] as? String, !session.isEmpty else { continue }
                        result[session] = account.lastPathComponent.lowercased()
                    }
                }
            }
        }
        return result
    }

    /// Codex 的記錄檔不帶帳號，只知道「現在」每個資料夾登入的是誰；還在寫的對話才記下來，已經記過的不改。
    static func recordCodexOwners(_ owners: inout UsageOwners, files: [DiscoveredFile], context: UsageScanContext) {
        let threshold = context.now.timeIntervalSince1970 - liveWindow
        for home in context.codexHomes {
            guard let accountID = home.accountID else { continue }
            let prefix = home.url.standardizedFileURL.path + "/"
            for file in files where file.platform == .codex && file.modified >= threshold && owners.codex[file.session] == nil {
                if file.url.standardizedFileURL.path.hasPrefix(prefix) {
                    owners.codex[file.session] = accountID.uuidString
                }
            }
        }
    }

    // MARK: - 彙總

    static func aggregate(files: [String: UsageFileRecord], owners: UsageOwners, timeZone: TimeZone) -> [UsageRecord] {
        struct BucketKey: Hashable {
            let day: Date
            let platform: PlatformKind
            let model: String
            let owner: String?
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        // 時區位移最小單位是 15 分鐘，同一刻鐘內的時間必然落在同一天。
        var dayByQuarter: [Int: Date] = [:]
        func day(for time: Int) -> Date {
            let quarter = time / 900
            if let day = dayByQuarter[quarter] { return day }
            let day = calendar.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(time)))
            dayByQuarter[quarter] = day
            return day
        }

        var buckets: [BucketKey: TokenCounts] = [:]
        let ordered = files.sorted { $0.key < $1.key }

        // Claude：續接或分叉的對話會把歷史抄進新檔，同一則回應跨檔只算一次，留 token 較多的那筆。
        var claude: [Int64: (entry: UsageEntry, owner: String?)] = [:]
        for (_, record) in ordered where record.platform == .claude {
            let owner = owners.claude[record.session] ?? record.accountUUID
            for index in 0..<record.count {
                let entry = record.entry(at: index)
                guard let kept = claude[record.keys[index]] else {
                    claude[record.keys[index]] = (entry, owner)
                    continue
                }
                // 兩份的帳號以知道的那份為準：抄過去的新對話可能不在桌面 App 的清單裡。
                claude[record.keys[index]] = (kept.entry.tokens.total >= entry.tokens.total ? kept.entry : entry, kept.owner ?? owner)
            }
        }
        for (entry, owner) in claude.values {
            buckets[BucketKey(day: day(for: entry.time), platform: .claude, model: entry.model, owner: owner), default: TokenCounts()] += entry.tokens
        }

        // Codex：封存會把檔案從 sessions 搬到 archived_sessions，同名的只取讀到比較多的那份。
        var codex: [String: UsageFileRecord] = [:]
        for (_, record) in ordered where record.platform == .codex {
            if let kept = codex[record.session], kept.count >= record.count { continue }
            codex[record.session] = record
        }
        for record in codex.values {
            let owner = owners.codex[record.session]
            for index in 0..<record.count {
                let entry = record.entry(at: index)
                buckets[BucketKey(day: day(for: entry.time), platform: .codex, model: entry.model, owner: owner), default: TokenCounts()] += entry.tokens
            }
        }

        return buckets
            .map { UsageRecord(day: $0.key.day, platform: $0.key.platform, model: $0.key.model, owner: $0.key.owner, tokens: $0.value) }
            .sorted { ($0.day, $0.platform.rawValue, $0.model, $0.owner ?? "") < ($1.day, $1.platform.rawValue, $1.model, $1.owner ?? "") }
    }

    // MARK: - 存檔

    static func loadCache(in directory: URL) throws -> UsageCache {
        let url = directory.appending(path: cacheFileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return UsageCache() }
        let cache = try PropertyListDecoder().decode(UsageCache.self, from: Data(contentsOf: url))
        return cache.version == UsageCache.currentVersion ? cache : UsageCache()
    }

    static func loadOwners(in directory: URL) throws -> UsageOwners {
        let url = directory.appending(path: ownersFileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return UsageOwners() }
        return try JSONDecoder().decode(UsageOwners.self, from: Data(contentsOf: url))
    }

    private static func save(_ cache: UsageCache, in directory: URL) throws {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        try write(encoder.encode(cache), to: directory.appending(path: cacheFileName))
    }

    private static func save(_ owners: UsageOwners, in directory: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try write(encoder.encode(owners), to: directory.appending(path: ownersFileName))
    }

    private static func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
