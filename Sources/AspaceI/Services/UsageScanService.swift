import Foundation
import os

/// 一次掃描要讀哪些位置。全部由外部給定，測試才能指到臨時資料夾。
struct UsageScanContext: Sendable {
    /// Claude Code 的 `projects` 資料夾；所有 Claude 桌面實例共用同一個。
    var claudeProjectRoots: [URL]
    /// Codex 的 `CODEX_HOME`：預設的 `~/.codex` 與每個 Codex 實例的資料夾。
    var codexHomes: [URL]
    /// 用量歷史存放的資料夾。
    var storeDirectory: URL
    var timeZone: TimeZone = .current
}

/// 讀 Claude Code 與 Codex 留在這台 Mac 的對話紀錄，存進 AspaceI 自己的用量歷史，再彙總成每小時用量。只讀本機檔案，不連網。
actor UsageScanService {
    static let shared = UsageScanService()

    static let historyFileName = "usage-history.plist"
    /// 2026-10-12 第一版的檔名，內容格式相同。
    private static let legacyFileName = "usage-cache.plist"

    private var history: UsageHistory?
    private let logger = Logger(subsystem: "com.huangyouci.AspaceI", category: "Usage")

    struct DiscoveredFile: Equatable, Sendable {
        var url: URL
        var platform: PlatformKind
        var session: String
        var size: Int
        var modified: Double
    }

    func scan(_ context: UsageScanContext) async throws -> [UsageRecord] {
        let isFirstLoad = history == nil
        var history = try self.history ?? Self.loadHistory(in: context.storeDirectory, logger: logger)
        let files = Self.discover(context)

        let pending = files.filter { file in
            guard let record = history.files[file.url.path] else { return true }
            return record.size != file.size || record.modified != file.modified
        }
        let existing = history.files
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

        // 已經刪掉的記錄檔不從歷史移除。
        history.files.merge(parsed) { _, new in new }
        if !parsed.isEmpty || isFirstLoad {
            try Self.save(history, in: context.storeDirectory)
        }
        self.history = history
        return Self.aggregate(files: history.files, timeZone: context.timeZone)
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
                for (url, size, modified) in jsonlFiles(under: home.appending(path: folder, directoryHint: .isDirectory)) {
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

    /// 檔案只會往後寫：有舊紀錄就從上次讀到的位置接著讀；檔案變小（被重寫）則整個重讀。
    static func parse(_ file: DiscoveredFile, existing: UsageFileRecord?) throws -> UsageFileRecord {
        var record = existing.flatMap { $0.platform == file.platform && $0.offset <= file.size ? $0 : nil }
            ?? UsageFileRecord(platform: file.platform, session: file.session)
        record.session = file.session
        switch file.platform {
        case .claude:
            var indexByKey: [Int64: Int] = [:]
            for (index, key) in record.keys.enumerated() { indexByKey[key] = index }
            record.offset = try UsageFileReader.scanLines(of: file.url, from: record.offset, patterns: ["\"usage\":{"]) { line in
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
        case .antigravity:
            break
        }
        record.size = file.size
        record.modified = file.modified
        return record
    }

    // MARK: - 彙總

    static func aggregate(files: [String: UsageFileRecord], timeZone: TimeZone) -> [UsageRecord] {
        struct BucketKey: Hashable {
            let hour: Date
            let platform: PlatformKind
            let model: String
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        // 時區位移最小單位是 15 分鐘，同一刻鐘內的時間必然落在同一個小時。
        var hourByQuarter: [Int: Date] = [:]
        func hour(for time: Int) -> Date {
            let quarter = time / 900
            if let hour = hourByQuarter[quarter] { return hour }
            let date = Date(timeIntervalSince1970: TimeInterval(time))
            let hour = calendar.dateInterval(of: .hour, for: date)?.start ?? date
            hourByQuarter[quarter] = hour
            return hour
        }

        var buckets: [BucketKey: TokenCounts] = [:]
        let ordered = files.sorted { $0.key < $1.key }

        // Claude：續接或分叉的對話會把歷史抄進新檔，同一則回應跨檔只算一次，留 token 較多的那筆。
        var claude: [Int64: UsageEntry] = [:]
        for (_, record) in ordered where record.platform == .claude {
            for index in 0..<record.count {
                let entry = record.entry(at: index)
                if let kept = claude[record.keys[index]], kept.tokens.total >= entry.tokens.total { continue }
                claude[record.keys[index]] = entry
            }
        }
        for entry in claude.values {
            buckets[BucketKey(hour: hour(for: entry.time), platform: .claude, model: entry.model), default: TokenCounts()] += entry.tokens
        }

        // Codex：封存會把檔案從 sessions 搬到 archived_sessions，同名的只取讀到比較多的那份。
        var codex: [String: UsageFileRecord] = [:]
        for (_, record) in ordered where record.platform == .codex {
            if let kept = codex[record.session], kept.count >= record.count { continue }
            codex[record.session] = record
        }
        for record in codex.values {
            for index in 0..<record.count {
                let entry = record.entry(at: index)
                buckets[BucketKey(hour: hour(for: entry.time), platform: .codex, model: entry.model), default: TokenCounts()] += entry.tokens
            }
        }

        return buckets
            .map { UsageRecord(hour: $0.key.hour, platform: $0.key.platform, model: $0.key.model, tokens: $0.value) }
            .sorted { ($0.hour, $0.platform.rawValue, $0.model) < ($1.hour, $1.platform.rawValue, $1.model) }
    }

    // MARK: - 存檔

    /// 讀不出來（損毀或格式版本不同）時不覆寫：原檔改名留著，再從現有的記錄檔重新累積。
    static func loadHistory(in directory: URL, logger: Logger? = nil) throws -> UsageHistory {
        let manager = FileManager.default
        var url = directory.appending(path: historyFileName)
        if !manager.fileExists(atPath: url.path) {
            url = directory.appending(path: legacyFileName)
            guard manager.fileExists(atPath: url.path) else { return UsageHistory() }
        }
        if let history = try? PropertyListDecoder().decode(UsageHistory.self, from: Data(contentsOf: url)),
           history.version == UsageHistory.currentVersion {
            if url.lastPathComponent == legacyFileName {
                try save(history, in: directory)
                try manager.removeItem(at: url)
            }
            return history
        }
        let stamp = Int(Date().timeIntervalSince1970)
        try manager.moveItem(at: url, to: directory.appending(path: "\(url.lastPathComponent).unreadable-\(stamp)"))
        logger?.error("UsageScanService.loadHistory | \(url.lastPathComponent, privacy: .public) 讀不出來，已改名保留並重新累積")
        return UsageHistory()
    }

    static func save(_ history: UsageHistory, in directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let url = directory.appending(path: historyFileName)
        try encoder.encode(history).write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
