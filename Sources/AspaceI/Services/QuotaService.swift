import Foundation

final class QuotaService: Sendable {
    static let shared = QuotaService()
    private init() {}

    func fetch(for account: Account, credentialData: Data) async throws -> QuotaSnapshot {
        switch account.platform {
        case .codex:
            return try await fetchCodex(data: credentialData)
        case .claude:
            return try await fetchClaude(data: credentialData, account: account)
        case .githubCopilot:
            return try await fetchGitHub(data: credentialData)
        case .antigravity:
            return try await fetchAntigravity(data: credentialData, account: account)
        }
    }

    // MARK: Antigravity

    private func fetchAntigravity(data: Data, account: Account) async throws -> QuotaSnapshot {
        let root = try jsonObject(data)
        let token: String
        if let refreshToken = string(in: root, paths: [["refresh_token"], ["token", "refresh_token"], ["refreshToken"]]) {
            token = try await refreshGoogleAccessToken(refreshToken)
        } else if let accessToken = string(in: root, paths: [["access_token"], ["token", "access_token"], ["accessToken"]]) {
            token = accessToken
        } else {
            throw QuotaError.missingToken
        }
        let project = string(in: root, paths: [["project_id"], ["token", "project_id"], ["projectId"]])
        var request = URLRequest(url: try endpoint("https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuotaSummary"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("antigravity", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: project.map { ["project": $0] } ?? [:])
        var snapshot = try Self.parseAntigravityQuota(try await sendJSON(request))
        snapshot.identity = try? await requestJSON(url: try endpoint("https://www.googleapis.com/oauth2/v2/userinfo"), token: token)["email"] as? String
        if account.planName == nil {
            snapshot.plan = await antigravityPlan(token: token)
        }
        return snapshot
    }

    private func antigravityPlan(token: String) async -> String? {
        guard let url = URL(string: "https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("antigravity", forHTTPHeaderField: "User-Agent")
        request.httpBody = Data(#"{"metadata":{"ideType":"ANTIGRAVITY","platform":"PLATFORM_UNSPECIFIED","pluginType":"GEMINI"}}"#.utf8)
        guard let value = try? await sendJSON(request) else { return nil }
        return Self.parseAntigravityPlan(value)
    }

    /// 付費方案優先；tier id 例如 `free-tier`、`g1-pro-tier`、`g1-ultra-tier`。
    static func parseAntigravityPlan(_ value: [String: Any]) -> String? {
        let id = ((value["paidTier"] as? [String: Any])?["id"] ?? (value["currentTier"] as? [String: Any])?["id"]) as? String
        guard let id = id?.lowercased() else { return nil }
        if id.contains("ultra") { return "Ultra" }
        if id.contains("pro") { return "Pro" }
        if id.contains("free") { return "Free" }
        if id.contains("standard") { return "Standard" }
        return nil
    }

    private func refreshGoogleAccessToken(_ refreshToken: String) async throws -> String {
        var request = URLRequest(url: try endpoint("https://oauth2.googleapis.com/token"))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "client_id", value: OAuthClient.antigravityID),
            URLQueryItem(name: "client_secret", value: OAuthClient.antigravitySecret),
            URLQueryItem(name: "refresh_token", value: refreshToken),
            URLQueryItem(name: "grant_type", value: "refresh_token")
        ]
        request.httpBody = Data((components.percentEncodedQuery ?? "").utf8)
        let value = try await sendJSON(request, failure: .tokenExpired)
        guard let token = value["access_token"] as? String, !token.isEmpty else { throw QuotaError.tokenExpired }
        return token
    }

    static func parseAntigravityQuota(_ value: [String: Any], now: Date = .now) throws -> QuotaSnapshot {
        let groups = value["groups"] as? [[String: Any]] ?? []
        // 找不到 Gemini 群組就不顯示。退回第一個群組會把 Claude／GPT（`3p-*`）的數字掛到 Gemini 欄位上。
        guard let group = groups.first(where: { group in
            (group["buckets"] as? [[String: Any]] ?? []).contains { ($0["bucketId"] as? String)?.hasPrefix("gemini") == true }
        }) else { throw QuotaError.invalidResponse }
        var windows: [QuotaWindow] = []
        for bucket in group["buckets"] as? [[String: Any]] ?? [] {
            guard let id = bucket["bucketId"] as? String,
                  let fraction = bucket["remainingFraction"] as? NSNumber,
                  bucket["disabled"] as? Bool != true else { continue }
            let kind: QuotaWindow.Kind = switch bucket["window"] as? String ?? "" {
            case "5h": .fiveHour
            case "weekly": .week
            default: id.hasSuffix("5h") ? .fiveHour : id.hasSuffix("weekly") ? .week : .other
            }
            guard kind != .other else { continue }
            var percentage = Int((fraction.doubleValue * 100).rounded())
            var reset = (bucket["resetTime"] as? String).flatMap(parseISODate)
            // 週限額用完時，5h 桶會回週的重置時間與被壓住的比例。這時 5h 本身其實沒被用掉，
            // 照抄會讓「段」欄倒數好幾天。判定沿用 cockpit-tools 的 `getAntigravityQuotaDisplayItems`。
            if kind == .fiveHour, let resetsAt = reset, resetsAt.timeIntervalSince(now) > 5 * 3_600 {
                percentage = 100
                reset = nil
            }
            windows.append(QuotaWindow(
                id: id,
                title: kind.shortTitle,
                remainingPercentage: percentage,
                resetsAt: reset,
                kind: kind
            ))
        }
        guard !windows.isEmpty else { throw QuotaError.invalidResponse }
        return QuotaSnapshot(windows: windows, fetchedAt: .now)
    }

    // MARK: Codex

    private func fetchCodex(data: Data) async throws -> QuotaSnapshot {
        let root = try jsonObject(data)
        guard let token = string(in: root, paths: [["tokens", "access_token"], ["access_token"]]) else { throw QuotaError.missingToken }
        let value = try await requestJSON(url: try endpoint("https://chatgpt.com/backend-api/wham/usage"), token: token)
        return try Self.parseCodexQuota(value)
    }

    static func parseCodexQuota(_ value: [String: Any]) throws -> QuotaSnapshot {
        let rate = value["rate_limit"] as? [String: Any]
        let windows = [
            parseCodexWindow(rate?["primary_window"], fallback: .fiveHour),
            parseCodexWindow(rate?["secondary_window"], fallback: .week)
        ].compactMap { $0 }
        guard !windows.isEmpty else { throw QuotaError.invalidResponse }
        return QuotaSnapshot(windows: windows, fetchedAt: .now, identity: value["email"] as? String, plan: (value["plan_type"] as? String).flatMap(codexPlanName))
    }

    /// Pro 分 5x（prolite）與 20x（promax）；API 只回 `pro` 時沿用 cockpit-tools 的判定視為 20x。
    static func codexPlanName(_ raw: String) -> String? {
        switch raw.lowercased().replacingOccurrences(of: "_", with: "-").replacingOccurrences(of: " ", with: "-") {
        case "free": "Free"
        case "go": "Go"
        case "plus": "Plus"
        case "prolite", "pro-lite", "pro-5x", "codex-pro-5x": "Pro 5x"
        case "pro", "promax", "pro-max", "pro-20x", "codex-pro-20x": "Pro 20x"
        case "team": "Team"
        case "business": "Business"
        case "enterprise": "Enterprise"
        case "edu", "education": "Edu"
        default: nil
        }
    }

    private static func parseCodexWindow(_ raw: Any?, fallback: QuotaWindow.Kind) -> QuotaWindow? {
        guard let value = raw as? [String: Any], let used = value["used_percent"] as? NSNumber else { return nil }
        let kind = (value["limit_window_seconds"] as? NSNumber).map { QuotaWindow.Kind.from(seconds: $0.doubleValue) } ?? fallback
        guard kind != .other else { return nil }
        let reset = (value["reset_at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
        return QuotaWindow(id: kind.rawValue, title: kind.shortTitle, remainingPercentage: 100 - used.intValue, resetsAt: reset, kind: kind)
    }

    // MARK: Claude

    private func fetchClaude(data: Data, account: Account) async throws -> QuotaSnapshot {
        let root = try jsonObject(data)
        guard let token = string(in: root, paths: [["claudeAiOauth", "accessToken"], ["accessToken"], ["access_token"]]) else { throw QuotaError.missingToken }
        var request = URLRequest(url: try endpoint("https://api.anthropic.com/api/oauth/usage"))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        var snapshot = try Self.parseClaudeQuota(try await sendJSON(request))
        if account.planName == nil || account.email == nil {
            var profileRequest = request
            profileRequest.url = URL(string: "https://api.anthropic.com/api/oauth/profile")
            if let profile = try? await sendJSON(profileRequest) {
                snapshot.plan = Self.parseClaudePlan(profile)
                snapshot.identity = (profile["account"] as? [String: Any])?["email"] as? String
                    ?? (profile["account"] as? [String: Any])?["email_address"] as? String
            }
        }
        return snapshot
    }

    static func parseClaudePlan(_ profile: [String: Any]) -> String? {
        let organization = profile["organization"] as? [String: Any]
        let tier = (organization?["rate_limit_tier"] as? String)?.lowercased() ?? ""
        if tier.contains("max_20x") { return "Max 20x" }
        if tier.contains("max_5x") { return "Max 5x" }
        switch organization?["organization_type"] as? String {
        case "claude_max": return "Max"
        case "claude_pro": return "Pro"
        case "claude_team": return "Team"
        case "claude_enterprise": return "Enterprise"
        default: return nil
        }
    }

    static func parseClaudeQuota(_ value: [String: Any]) throws -> QuotaSnapshot {
        let windows = [
            parseUtilizationWindow(value["five_hour"], kind: .fiveHour),
            parseUtilizationWindow(value["seven_day"], kind: .week)
        ].compactMap { $0 }
        guard !windows.isEmpty else { throw QuotaError.invalidResponse }
        return QuotaSnapshot(windows: windows, fetchedAt: .now)
    }

    private static func parseUtilizationWindow(_ raw: Any?, kind: QuotaWindow.Kind) -> QuotaWindow? {
        guard let value = raw as? [String: Any], let used = value["utilization"] as? NSNumber else { return nil }
        let reset = (value["resets_at"] as? String).flatMap(parseISODate)
        return QuotaWindow(id: kind.rawValue, title: kind.shortTitle, remainingPercentage: 100 - Int(used.doubleValue.rounded()), resetsAt: reset, kind: kind)
    }

    // MARK: GitHub Copilot

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
        let value = try await requestJSON(url: try endpoint("https://api.github.com/copilot_internal/user"), token: token)
        return try Self.parseCopilotQuota(value)
    }

    /// 付費方案看 premium requests；免費方案沒有 premium 額度時退回 chat。
    static func parseCopilotQuota(_ value: [String: Any]) throws -> QuotaSnapshot {
        guard let snapshots = value["quota_snapshots"] as? [String: Any] else { throw QuotaError.invalidResponse }
        let reset = (value["quota_reset_date_utc"] as? String).flatMap(parseISODate)
        let premium = snapshots["premium_interactions"] as? [String: Any]
        let chat = snapshots["chat"] as? [String: Any]
        let premiumAvailable = premium.map { ($0["unlimited"] as? Bool == true) || ($0["entitlement"] as? NSNumber)?.doubleValue ?? 0 > 0 } ?? false
        guard let selected = premiumAvailable ? premium : chat else { throw QuotaError.invalidResponse }
        let percentage: Int
        if selected["unlimited"] as? Bool == true {
            percentage = 100
        } else if let remaining = selected["percent_remaining"] as? NSNumber {
            percentage = Int(remaining.doubleValue.rounded())
        } else {
            throw QuotaError.invalidResponse
        }
        let window = QuotaWindow(
            id: premiumAvailable ? "premium" : "chat",
            title: QuotaWindow.Kind.month.shortTitle,
            remainingPercentage: percentage,
            resetsAt: reset,
            kind: .month
        )
        return QuotaSnapshot(windows: [window], fetchedAt: .now, identity: value["login"] as? String, plan: parseCopilotPlan(value))
    }

    static func parseCopilotPlan(_ value: [String: Any]) -> String? {
        let sku = (value["access_type_sku"] as? String)?.lowercased() ?? ""
        let plan = (value["copilot_plan"] as? String)?.lowercased() ?? ""
        if sku.contains("free") { return "Free" }
        if plan == "enterprise" { return "Enterprise" }
        if plan == "business" { return "Business" }
        if sku.contains("plus") { return "Pro+" }
        if plan == "individual" { return "Pro" }
        return nil
    }

    // MARK: Helpers

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

    private func sendJSON(_ request: URLRequest, failure: QuotaError? = nil) async throws -> [String: Any] {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard !Task.isCancelled else { throw CancellationError() }
        guard let http = response as? HTTPURLResponse else { throw QuotaError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            if let failure { throw failure }
            throw http.statusCode == 401 || http.statusCode == 403 ? QuotaError.tokenExpired : QuotaError.requestFailed(http.statusCode)
        }
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

    private static func parseISODate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}

enum QuotaError: LocalizedError {
    case missingToken, invalidResponse, invalidEndpoint, tokenExpired, tokenCannotReadUsage, requestFailed(Int)
    var errorDescription: String? {
        switch self {
        case .missingToken: "找不到可用的登入憑證"
        case .invalidResponse: "額度回應格式無法識別"
        case .invalidEndpoint: "額度服務網址無效"
        case .tokenExpired: "憑證已失效，請重新登入後再匯入"
        case .tokenCannotReadUsage: "這個 token 沒有讀取額度的權限，請改用瀏覽器登入"
        case .requestFailed(let status): "額度服務拒絕請求（\(status)）"
        }
    }
}
