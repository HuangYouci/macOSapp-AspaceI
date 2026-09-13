import Foundation

final class QuotaService: Sendable {
    static let shared = QuotaService()
    private init() {}

    func fetch(for account: Account, credentialData: Data) async throws -> QuotaSnapshot {
        switch account.platform {
        case .codex:
            return try await fetchCodex(data: credentialData)
        case .claude:
            return try await fetchClaude(data: credentialData)
        case .githubCopilot:
            return try await fetchGitHub(data: credentialData)
        case .antigravity:
            return try await fetchAntigravity(data: credentialData)
        }
    }

    private func fetchAntigravity(data: Data) async throws -> QuotaSnapshot {
        let root = try jsonObject(data)
        guard let token = string(in: root, paths: [["access_token"], ["token", "access_token"], ["accessToken"]]) else { throw QuotaError.unsupported("請匯入包含 access_token 的 Antigravity JSON；本機 state.vscdb 僅供 Instance 隔離") }
        let project = string(in: root, paths: [["project_id"], ["token", "project_id"], ["projectId"]])
        var request = URLRequest(url: try endpoint("https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuotaSummary"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: project.map { ["project": $0] } ?? [:])
        let value = try await sendJSON(request)
        return try Self.parseAntigravityQuota(value)
    }

    static func parseAntigravityQuota(_ value: [String: Any]) throws -> QuotaSnapshot {
        var windows: [QuotaWindow] = []
        for group in value["groups"] as? [[String: Any]] ?? [] {
            for bucket in group["buckets"] as? [[String: Any]] ?? [] {
                guard let id = bucket["bucketId"] as? String, let fraction = bucket["remainingFraction"] as? NSNumber else { continue }
                let title = bucket["displayName"] as? String ?? id
                let reset = (bucket["resetTime"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) }
                windows.append(QuotaWindow(id: id, title: title, remainingPercentage: Int(fraction.doubleValue * 100), resetsAt: reset))
            }
        }
        guard !windows.isEmpty else { throw QuotaError.invalidResponse }
        return QuotaSnapshot(windows: windows, fetchedAt: .now)
    }

    private func fetchCodex(data: Data) async throws -> QuotaSnapshot {
        let root = try jsonObject(data)
        guard let token = string(in: root, paths: [["tokens", "access_token"], ["access_token"]]) else { throw QuotaError.missingToken }
        let value = try await requestJSON(url: try endpoint("https://chatgpt.com/backend-api/wham/usage"), token: token)
        return try Self.parseCodexQuota(value)
    }

    static func parseCodexQuota(_ value: [String: Any]) throws -> QuotaSnapshot {
        let rate = value["rate_limit"] as? [String: Any]
        let windows = [parseUsedWindow(rate?["primary_window"], id: "5h", title: "5 小時"), parseUsedWindow(rate?["secondary_window"], id: "weekly", title: "每週")].compactMap { $0 }
        guard !windows.isEmpty else { throw QuotaError.invalidResponse }
        return QuotaSnapshot(windows: windows, fetchedAt: .now)
    }

    private func fetchClaude(data: Data) async throws -> QuotaSnapshot {
        let root = try jsonObject(data)
        guard let token = string(in: root, paths: [["claudeAiOauth", "accessToken"], ["accessToken"]]) else { throw QuotaError.missingToken }
        var request = URLRequest(url: try endpoint("https://api.anthropic.com/api/oauth/usage"))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        let value = try await sendJSON(request)
        return try Self.parseClaudeQuota(value)
    }

    static func parseClaudeQuota(_ value: [String: Any]) throws -> QuotaSnapshot {
        let windows = [parseUtilizationWindow(value["five_hour"], id: "5h", title: "目前工作階段"), parseUtilizationWindow(value["seven_day"], id: "weekly", title: "本週")].compactMap { $0 }
        guard !windows.isEmpty else { throw QuotaError.invalidResponse }
        return QuotaSnapshot(windows: windows, fetchedAt: .now)
    }

    private func fetchGitHub(data: Data) async throws -> QuotaSnapshot {
        let jsonToken: String?
        do {
            jsonToken = try jsonObject(data)["access_token"] as? String
        } catch {
            jsonToken = nil
        }
        let text = String(data: data, encoding: .utf8)
        let yamlToken = text?.split(separator: "\n").first(where: { $0.contains("oauth_token:") })?.split(separator: ":", maxSplits: 1).last?.trimmingCharacters(in: .whitespaces)
        guard let token = jsonToken ?? yamlToken, !token.isEmpty else { throw QuotaError.missingToken }
        let value = try await requestJSON(url: try endpoint("https://api.github.com/rate_limit"), token: token)
        return try Self.parseGitHubQuota(value)
    }

    static func parseGitHubQuota(_ value: [String: Any]) throws -> QuotaSnapshot {
        var windows: [QuotaWindow] = []
        if let resources = value["resources"] as? [String: Any] {
            for key in ["core", "graphql", "search"] {
                guard let item = resources[key] as? [String: Any], let limit = item["limit"] as? NSNumber, let remaining = item["remaining"] as? NSNumber, limit.doubleValue > 0 else { continue }
                let percentage = Int(remaining.doubleValue / limit.doubleValue * 100)
                let reset = (item["reset"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
                windows.append(QuotaWindow(id: key, title: key.capitalized, remainingPercentage: percentage, resetsAt: reset))
            }
        }
        guard !windows.isEmpty else { throw QuotaError.invalidResponse }
        return QuotaSnapshot(windows: windows, fetchedAt: .now)
    }

    private func requestJSON(url: URL, token: String) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await sendJSON(request)
    }

    private func endpoint(_ value: String) throws -> URL {
        guard let url = URL(string: value) else { throw QuotaError.invalidEndpoint }
        return url
    }

    private func sendJSON(_ request: URLRequest) async throws -> [String: Any] {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard !Task.isCancelled else { throw CancellationError() }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw QuotaError.requestFailed }
        return try jsonObject(data)
    }

    private func jsonObject(_ data: Data) throws -> [String: Any] {
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw QuotaError.invalidResponse }
        return value
    }

    private func string(in root: [String: Any], paths: [[String]]) -> String? {
        for path in paths {
            var value: Any = root
            for key in path { guard let object = value as? [String: Any], let next = object[key] else { value = NSNull(); break }; value = next }
            if let result = value as? String, !result.isEmpty { return result }
        }
        return nil
    }

    private static func parseUsedWindow(_ raw: Any?, id: String, title: String) -> QuotaWindow? {
        guard let value = raw as? [String: Any], let used = value["used_percent"] as? NSNumber else { return nil }
        let reset = (value["reset_at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
        return QuotaWindow(id: id, title: title, remainingPercentage: 100 - used.intValue, resetsAt: reset)
    }

    private static func parseUtilizationWindow(_ raw: Any?, id: String, title: String) -> QuotaWindow? {
        guard let value = raw as? [String: Any], let used = value["utilization"] as? NSNumber else { return nil }
        let reset = (value["resets_at"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) }
        return QuotaWindow(id: id, title: title, remainingPercentage: 100 - Int(used.doubleValue), resetsAt: reset)
    }
}

enum QuotaError: LocalizedError {
    case missingToken, invalidResponse, invalidEndpoint, requestFailed, unsupported(String)
    var errorDescription: String? {
        switch self {
        case .missingToken: "找不到可用的登入憑證"
        case .invalidResponse: "額度回應格式無法識別"
        case .invalidEndpoint: "額度服務網址無效"
        case .requestFailed: "額度服務拒絕請求"
        case .unsupported(let message): message
        }
    }
}
