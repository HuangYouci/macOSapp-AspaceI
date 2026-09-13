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
            throw QuotaError.unsupported(String(localized: "AntigravityQuotaUnavailable", defaultValue: "Antigravity 額度介面尚未能從本機資料安全確認"))
        }
    }

    private func fetchCodex(data: Data) async throws -> QuotaSnapshot {
        let root = try jsonObject(data)
        guard let token = string(in: root, paths: [["tokens", "access_token"], ["access_token"]]) else { throw QuotaError.missingToken }
        let value = try await requestJSON(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!, token: token)
        let rate = value["rate_limit"] as? [String: Any]
        let windows = [quotaWindow(rate?["primary_window"], id: "5h", title: "5 小時"), quotaWindow(rate?["secondary_window"], id: "weekly", title: "每週")].compactMap { $0 }
        guard !windows.isEmpty else { throw QuotaError.invalidResponse }
        return QuotaSnapshot(windows: windows, fetchedAt: .now)
    }

    private func fetchClaude(data: Data) async throws -> QuotaSnapshot {
        let root = try jsonObject(data)
        guard let token = string(in: root, paths: [["claudeAiOauth", "accessToken"], ["accessToken"]]) else { throw QuotaError.missingToken }
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        let value = try await sendJSON(request)
        let windows = [claudeWindow(value["five_hour"], id: "5h", title: "目前工作階段"), claudeWindow(value["seven_day"], id: "weekly", title: "本週")].compactMap { $0 }
        guard !windows.isEmpty else { throw QuotaError.invalidResponse }
        return QuotaSnapshot(windows: windows, fetchedAt: .now)
    }

    private func fetchGitHub(data: Data) async throws -> QuotaSnapshot {
        guard let text = String(data: data, encoding: .utf8), let tokenLine = text.split(separator: "\n").first(where: { $0.contains("oauth_token:") }), let token = tokenLine.split(separator: ":", maxSplits: 1).last?.trimmingCharacters(in: .whitespaces), !token.isEmpty else { throw QuotaError.missingToken }
        let value = try await requestJSON(url: URL(string: "https://api.github.com/copilot_internal/user")!, token: token)
        var windows: [QuotaWindow] = []
        if let snapshots = value["quota_snapshots"] as? [String: Any] {
            for (key, raw) in snapshots {
                guard let item = raw as? [String: Any], let remaining = item["percent_remaining"] as? Double else { continue }
                windows.append(QuotaWindow(id: key, title: key.replacingOccurrences(of: "_", with: " ").capitalized, remainingPercentage: Int(remaining), resetsAt: nil))
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

    private func quotaWindow(_ raw: Any?, id: String, title: String) -> QuotaWindow? {
        guard let value = raw as? [String: Any], let used = value["used_percent"] as? NSNumber else { return nil }
        let reset = (value["reset_at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
        return QuotaWindow(id: id, title: title, remainingPercentage: 100 - used.intValue, resetsAt: reset)
    }

    private func claudeWindow(_ raw: Any?, id: String, title: String) -> QuotaWindow? {
        guard let value = raw as? [String: Any], let used = value["utilization"] as? NSNumber else { return nil }
        let reset = (value["resets_at"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) }
        return QuotaWindow(id: id, title: title, remainingPercentage: 100 - Int(used.doubleValue), resetsAt: reset)
    }
}

enum QuotaError: LocalizedError {
    case missingToken, invalidResponse, requestFailed, unsupported(String)
    var errorDescription: String? {
        switch self {
        case .missingToken: "找不到可用的登入憑證"
        case .invalidResponse: "額度回應格式無法識別"
        case .requestFailed: "額度服務拒絕請求"
        case .unsupported(let message): message
        }
    }
}
