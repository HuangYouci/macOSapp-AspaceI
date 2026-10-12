import Foundation
import Testing
@testable import AspaceI

struct UsageLineParserTests {
    private func line(_ json: String) -> Data { Data(json.utf8) }

    @Test("Claude 讀出 message.usage，快取與輸入分開")
    func parsesClaude() throws {
        let entry = try #require(UsageLineParser.claudeEntry(line: line(#"{"timestamp":"2026-10-12T06:58:28.123Z","requestId":"req_1","message":{"id":"msg_1","model":"claude-opus-5","usage":{"input_tokens":3,"output_tokens":40,"cache_read_input_tokens":1000,"cache_creation_input_tokens":200}}}"#), sessionID: "s"))
        #expect(entry.model == "claude-opus-5")
        #expect(entry.tokens == TokenCounts(input: 3, output: 40, cacheRead: 1000, cacheWrite: 200))
        #expect(entry.time == 1_791_788_308)
    }

    @Test("同一則回應的去重鍵相同；沒有 requestId 時以對話區分")
    func claudeKeys() throws {
        let a = try #require(UsageLineParser.claudeEntry(line: line(#"{"timestamp":"2026-10-12T00:00:00Z","requestId":"r","message":{"id":"msg_1","model":"m","usage":{"output_tokens":1}}}"#), sessionID: "s1"))
        let b = try #require(UsageLineParser.claudeEntry(line: line(#"{"timestamp":"2026-10-12T00:00:09Z","requestId":"r","message":{"id":"msg_1","model":"m","usage":{"output_tokens":9}}}"#), sessionID: "s2"))
        #expect(a.key == b.key)
        let c = try #require(UsageLineParser.claudeEntry(line: line(#"{"timestamp":"2026-10-12T00:00:00Z","message":{"id":"msg_1","model":"m","usage":{"output_tokens":1}}}"#), sessionID: "s1"))
        let d = try #require(UsageLineParser.claudeEntry(line: line(#"{"timestamp":"2026-10-12T00:00:00Z","message":{"id":"msg_1","model":"m","usage":{"output_tokens":1}}}"#), sessionID: "s2"))
        #expect(c.key != d.key)
    }

    @Test("略過合成訊息與工具結果裡的 usage")
    func skipsNonResponses() {
        #expect(UsageLineParser.claudeEntry(line: line(#"{"timestamp":"2026-10-12T00:00:00Z","message":{"id":"x","model":"<synthetic>","usage":{"output_tokens":1}}}"#), sessionID: "s") == nil)
        #expect(UsageLineParser.claudeEntry(line: line(#"{"timestamp":"2026-10-12T00:00:00Z","type":"user","message":{"role":"user"},"toolUseResult":{"usage":{"output_tokens":5}}}"#), sessionID: "s") == nil)
    }

    @Test("Codex 用本輪值，累計值沒前進就是重複送出；input 扣掉快取讀取")
    func parsesCodex() throws {
        var state = UsageLineParser.CodexState()
        #expect(UsageLineParser.codexEntry(line: line(#"{"timestamp":"2026-10-12T00:00:00Z","type":"turn_context","payload":{"model":"gpt-6-sol"}}"#), state: &state) == nil)
        let first = try #require(UsageLineParser.codexEntry(line: line(#"{"timestamp":"2026-10-12T00:00:01Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":100,"cached_input_tokens":80,"output_tokens":7},"total_token_usage":{"input_tokens":100,"cached_input_tokens":80,"output_tokens":7}}}}"#), state: &state))
        #expect(first.model == "gpt-6-sol")
        #expect(first.tokens == TokenCounts(input: 20, output: 7, cacheRead: 80, cacheWrite: 0))
        #expect(UsageLineParser.codexEntry(line: line(#"{"timestamp":"2026-10-12T00:00:02Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":100,"cached_input_tokens":80,"output_tokens":7},"total_token_usage":{"input_tokens":100,"cached_input_tokens":80,"output_tokens":7}}}}"#), state: &state) == nil)
        let diffed = try #require(UsageLineParser.codexEntry(line: line(#"{"timestamp":"2026-10-12T00:00:03Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":150,"cached_input_tokens":100,"output_tokens":10}}}}"#), state: &state))
        #expect(diffed.tokens == TokenCounts(input: 30, output: 3, cacheRead: 20, cacheWrite: 0))
    }

    @Test("ISO 8601 時間換算與系統一致")
    func epochSeconds() {
        for text in ["1970-01-01T00:00:00Z", "2000-02-29T12:34:56.789Z", "2026-10-12T23:59:59Z"] {
            let expected = ISO8601DateFormatter.fractional(text).map { Int($0.timeIntervalSince1970) }
            #expect(UsageLineParser.epochSeconds(iso8601: text) == expected)
        }
        #expect(UsageLineParser.epochSeconds(iso8601: "2026-10-12 00:00:00") == nil)
    }
}

private extension ISO8601DateFormatter {
    static func fractional(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = text.contains(".") ? [.withInternetDateTime, .withFractionalSeconds] : [.withInternetDateTime]
        return formatter.date(from: text)
    }
}

struct UsageScanTests {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "UsageScanTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("只回傳完整的行，結尾還在寫的半行留到下次")
    func readerStopsAtLastNewline() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "a.jsonl")
        try Data("{\"x\":1}\n{\"usage\":{\"a\":1}}\n{\"usage\":{\"b\"".utf8).write(to: file)
        var lines: [String] = []
        let offset = try UsageFileReader.scanLines(of: file, from: 0, patterns: ["\"usage\":{"]) { lines.append(String(decoding: $0, as: UTF8.self)) }
        #expect(lines == ["{\"usage\":{\"a\":1}}"])
        #expect(offset == 26)
    }

    @Test("掃描、續讀、跨檔去重、歸屬與時區分日")
    func scansAndAggregates() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let projects = root.appending(path: "projects/p")
        try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
        func claudeLine(_ id: String, _ time: String, output: Int) -> String {
            #"{"timestamp":"\#(time)","requestId":"r\#(id)","message":{"id":"msg_\#(id)","model":"claude-opus-5","usage":{"input_tokens":1,"output_tokens":\#(output)}}}"# + "\n"
        }
        // s1 的訊息 1 在 s2 又被抄了一次（且較完整），只算一次、取較多的那筆。
        try (claudeLine("1", "2026-10-11T15:30:00Z", output: 5) + claudeLine("2", "2026-10-11T16:30:00Z", output: 7)).write(to: projects.appending(path: "s1.jsonl"), atomically: true, encoding: .utf8)
        try claudeLine("1", "2026-10-11T15:30:00Z", output: 9).write(to: projects.appending(path: "s2.jsonl"), atomically: true, encoding: .utf8)
        let index = root.appending(path: "index/11111111-1111-1111-1111-111111111111/org")
        try FileManager.default.createDirectory(at: index, withIntermediateDirectories: true)
        try #"{"cliSessionId":"s1"}"#.write(to: index.appending(path: "local_a.json"), atomically: true, encoding: .utf8)

        let context = UsageScanContext(
            claudeProjectRoots: [root.appending(path: "projects")],
            claudeSessionIndexRoots: [root.appending(path: "index")],
            codexHomes: [],
            storeDirectory: root.appending(path: "store"),
            timeZone: try #require(TimeZone(identifier: "Asia/Taipei"))
        )
        let records = try await UsageScanService().scan(context)
        let owner = "11111111-1111-1111-1111-111111111111"
        // 台北時間：15:30Z = 10/11 23:30、16:30Z = 10/12 00:30。
        #expect(records.count == 2)
        #expect(records.map(\.tokens.output).sorted() == [7, 9])
        #expect(Set(records.map(\.owner)) == [owner, owner])

        // 續讀：同一個檔案往後寫，舊的不重算；快取重開也讀得回來。
        let handle = try FileHandle(forWritingTo: projects.appending(path: "s2.jsonl"))
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(claudeLine("3", "2026-10-11T17:00:00Z", output: 1).utf8))
        try handle.close()
        let again = try await UsageScanService().scan(context)
        #expect(again.reduce(0) { $0 + $1.tokens.output } == 17)
        // s2 不在桌面 App 的清單裡，訊息 3 無法歸屬。
        #expect(again.contains { $0.owner == nil && $0.tokens.output == 1 })
    }

    @Test("Codex：還在寫的對話記給目前登入的帳號，舊對話不猜")
    func recordsCodexOwners() {
        let home = URL(fileURLWithPath: "/tmp/codex-home")
        let account = UUID()
        let now = Date(timeIntervalSince1970: 1_000_000)
        let context = UsageScanContext(claudeProjectRoots: [], claudeSessionIndexRoots: [], codexHomes: [.init(url: home, accountID: account)], storeDirectory: home, now: now)
        let files = [
            UsageScanService.DiscoveredFile(url: home.appending(path: "sessions/live.jsonl"), platform: .codex, session: "live", size: 1, modified: now.timeIntervalSince1970 - 60),
            UsageScanService.DiscoveredFile(url: home.appending(path: "sessions/old.jsonl"), platform: .codex, session: "old", size: 1, modified: now.timeIntervalSince1970 - 86_400)
        ]
        var owners = UsageOwners(codex: ["kept": "x"])
        UsageScanService.recordCodexOwners(&owners, files: files, context: context)
        #expect(owners.codex == ["kept": "x", "live": account.uuidString])
    }

    @Test("子代理的紀錄歸到父對話")
    func subagentSession() {
        #expect(UsageScanService.claudeSession(for: URL(fileURLWithPath: "/p/abc/subagents/agent-1.jsonl")) == "abc")
        #expect(UsageScanService.claudeSession(for: URL(fileURLWithPath: "/p/abc.jsonl")) == "abc")
    }
}

struct UsageSummaryTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Taipei") ?? .current
        return calendar
    }

    @Test("區間補滿沒有用量的日子，篩選只影響每日與模型")
    func summarizes() {
        let today = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_791_788_308))
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let old = calendar.date(byAdding: .day, value: -40, to: today) ?? today
        let account = Account(platform: .claude, displayName: "claude-max-1", accountUUID: "aaaa")
        let records = [
            UsageRecord(day: today, platform: .claude, model: "opus", owner: "aaaa", tokens: TokenCounts(output: 10)),
            UsageRecord(day: yesterday, platform: .claude, model: "sonnet", owner: nil, tokens: TokenCounts(output: 3)),
            UsageRecord(day: old, platform: .codex, model: "gpt", owner: nil, tokens: TokenCounts(output: 100))
        ]
        let week = UsageSummary(records: records, range: .week, filter: nil, accounts: [account], today: today, calendar: calendar)
        #expect(week.days.count == 7)
        #expect(week.total.output == 13)
        #expect(week.models.map(\.title) == ["opus", "sonnet"])
        #expect(week.owners.map(\.title) == ["claude-max-1", "未歸屬"])

        let filtered = UsageSummary(records: records, range: .week, filter: UsageOwnerKey(platform: .claude, owner: "aaaa"), accounts: [account], today: today, calendar: calendar)
        #expect(filtered.total.output == 10)
        #expect(filtered.owners.count == 2)

        let all = UsageSummary(records: records, range: .all, filter: nil, accounts: [account], today: today, calendar: calendar)
        #expect(all.days.count == 41)
        #expect(all.total.output == 113)
    }
}
