import Foundation
import Testing
@testable import AspaceI

struct QuotaServiceTests {
    @Test
    func parsesCodexUsageWindowsAsRemainingPercentage() throws {
        let result = try QuotaService.parseCodexQuota([
            "email": "someone@example.com",
            "rate_limit": [
                "primary_window": ["used_percent": 25, "limit_window_seconds": 18_000, "reset_at": 1_800_000_000],
                "secondary_window": ["used_percent": 80, "limit_window_seconds": 604_800, "reset_at": 1_900_000_000]
            ]
        ])
        #expect(result.windows.map(\.remainingPercentage) == [75, 20])
        #expect(result.windows.map(\.kind) == [.fiveHour, .week])
        #expect(result.identity == "someone@example.com")
    }

    @Test("Codex 只有週額度時，primary_window 依時窗長度判定為 7d")
    func classifiesCodexWeeklyOnlyPrimaryWindow() throws {
        let result = try QuotaService.parseCodexQuota([
            "rate_limit": [
                "primary_window": ["used_percent": 73, "limit_window_seconds": 604_800, "reset_at": 1_789_817_273],
                "secondary_window": NSNull()
            ]
        ])
        #expect(result.windows.count == 1)
        #expect(result.windows.first?.kind == .week)
        #expect(result.windows.first?.remainingPercentage == 27)
    }

    @Test
    func parsesClaudeUtilizationAsRemainingPercentage() throws {
        let result = try QuotaService.parseClaudeQuota([
            "five_hour": ["utilization": 12.0, "resets_at": "2026-09-13T12:00:00.123+00:00"],
            "seven_day": ["utilization": 42.0, "resets_at": "2026-09-20T12:00:00Z"]
        ])
        #expect(result.windows.map(\.remainingPercentage) == [88, 58])
        #expect(result.windows.map(\.kind) == [.fiveHour, .week])
        #expect(result.windows.allSatisfy { $0.resetsAt != nil })
    }

    @Test("Copilot 付費方案取 premium requests")
    func parsesCopilotPremiumInteractions() throws {
        let result = try QuotaService.parseCopilotQuota([
            "login": "octocat",
            "quota_reset_date_utc": "2026-10-01T00:00:00.000Z",
            "quota_snapshots": [
                "chat": ["percent_remaining": 100.0, "entitlement": 0, "unlimited": true],
                "premium_interactions": ["percent_remaining": 62.4, "entitlement": 300, "unlimited": false]
            ]
        ])
        #expect(result.windows.first?.id == "premium")
        #expect(result.windows.first?.remainingPercentage == 62)
        #expect(result.windows.first?.kind == .month)
        #expect(result.windows.first?.resetsAt != nil)
        #expect(result.identity == "octocat")
    }

    @Test("Copilot 免費方案沒有 premium 額度時退回 chat")
    func fallsBackToCopilotChatOnFreePlan() throws {
        let result = try QuotaService.parseCopilotQuota([
            "quota_snapshots": [
                "chat": ["percent_remaining": 85.0, "entitlement": 200, "unlimited": false],
                "premium_interactions": ["percent_remaining": 0.0, "entitlement": 0, "unlimited": false]
            ]
        ])
        #expect(result.windows.first?.id == "chat")
        #expect(result.windows.first?.remainingPercentage == 85)
    }

    @Test("Antigravity 只取 Gemini 群組的額度")
    func parsesAntigravityQuotaGroups() throws {
        let result = try QuotaService.parseAntigravityQuota([
            "groups": [
                [
                    "displayName": "Gemini Models",
                    "buckets": [
                        ["bucketId": "gemini-weekly", "window": "weekly", "remainingFraction": 0.19336277, "resetTime": "2026-09-18T06:06:20Z"],
                        ["bucketId": "gemini-5h", "window": "5h", "remainingFraction": 0.9899, "resetTime": "2026-09-13T17:28:01Z"]
                    ]
                ],
                [
                    "displayName": "Claude and GPT models",
                    "buckets": [
                        ["bucketId": "3p-weekly", "window": "weekly", "remainingFraction": 0],
                        ["bucketId": "3p-5h", "window": "5h", "disabled": true, "remainingFraction": 1]
                    ]
                ]
            ]
        ])
        #expect(result.primaryWindows.map(\.kind) == [.fiveHour, .week])
        #expect(result.primaryWindows.map(\.remainingPercentage) == [99, 19])
        #expect(result.windows.map(\.id).sorted() == ["gemini-5h", "gemini-weekly"])
    }

    @Test("找不到 Gemini 群組時不退回第一個群組")
    func rejectsAntigravityQuotaWithoutGeminiGroup() {
        #expect(throws: QuotaError.self) {
            try QuotaService.parseAntigravityQuota([
                "groups": [
                    [
                        "displayName": "Claude and GPT models",
                        "buckets": [
                            ["bucketId": "3p-weekly", "window": "weekly", "remainingFraction": 0.42],
                            ["bucketId": "3p-5h", "window": "5h", "remainingFraction": 0.77]
                        ]
                    ]
                ]
            ])
        }
    }

    @Test("5h 桶回週的重置時間時視為未使用，不顯示倒數")
    func normalisesAntigravityFiveHourCappedByWeekly() throws {
        let now = Date(timeIntervalSince1970: 1_789_000_000)
        let weeklyReset = ISO8601DateFormatter().string(from: now.addingTimeInterval(72 * 3_600))
        let result = try QuotaService.parseAntigravityQuota([
            "groups": [
                [
                    "buckets": [
                        ["bucketId": "gemini-weekly", "window": "weekly", "remainingFraction": 0, "resetTime": weeklyReset],
                        ["bucketId": "gemini-5h", "window": "5h", "remainingFraction": 0, "resetTime": weeklyReset]
                    ]
                ]
            ]
        ], now: now)
        let fiveHour = try #require(result.windows.first { $0.kind == .fiveHour })
        #expect(fiveHour.remainingPercentage == 100)
        #expect(fiveHour.resetsAt == nil)
        let week = try #require(result.windows.first { $0.kind == .week })
        #expect(week.remainingPercentage == 0)
        #expect(week.resetsAt != nil)
    }

    @Test("沒用過的 5h 視窗剛好超過五小時時仍保留倒數")
    func keepsFreshAntigravityFiveHourBeyondThreshold() throws {
        // 2026-09-18 的真實回應：5h 重置在 5.08 小時後、週重置在 6.2 小時後，兩個都還沒被壓住。
        let now = Date(timeIntervalSince1970: 1_789_000_000)
        let iso = ISO8601DateFormatter()
        let result = try QuotaService.parseAntigravityQuota([
            "groups": [
                [
                    "buckets": [
                        ["bucketId": "gemini-weekly", "window": "weekly", "remainingFraction": 0.20294766,
                         "resetTime": iso.string(from: now.addingTimeInterval(6.2 * 3_600))],
                        ["bucketId": "gemini-5h", "window": "5h", "remainingFraction": 1,
                         "resetTime": iso.string(from: now.addingTimeInterval(5.08 * 3_600))]
                    ]
                ]
            ]
        ], now: now)
        let fiveHour = try #require(result.windows.first { $0.kind == .fiveHour })
        #expect(fiveHour.remainingPercentage == 100)
        #expect(fiveHour.resetsAt != nil)
        let week = try #require(result.windows.first { $0.kind == .week })
        #expect(week.remainingPercentage == 20)
    }

    @Test("5h 桶的重置時間在五小時內時照實顯示")
    func keepsAntigravityFiveHourWithinWindow() throws {
        let now = Date(timeIntervalSince1970: 1_789_000_000)
        let reset = ISO8601DateFormatter().string(from: now.addingTimeInterval(3_600))
        let result = try QuotaService.parseAntigravityQuota([
            "groups": [
                ["buckets": [["bucketId": "gemini-5h", "window": "5h", "remainingFraction": 0.25, "resetTime": reset]]]
            ]
        ], now: now)
        let fiveHour = try #require(result.windows.first { $0.kind == .fiveHour })
        #expect(fiveHour.remainingPercentage == 25)
        #expect(fiveHour.resetsAt != nil)
    }

    @Test("不支援的時窗長度不顯示")
    func dropsUnsupportedCodexWindow() throws {
        let result = try QuotaService.parseCodexQuota([
            "rate_limit": [
                "primary_window": ["used_percent": 10, "limit_window_seconds": 3_600],
                "secondary_window": ["used_percent": 20, "limit_window_seconds": 604_800]
            ]
        ])
        #expect(result.windows.map(\.kind) == [.week])
    }

    @Test
    func classifiesWindowKindBySeconds() {
        #expect(QuotaWindow.Kind.from(seconds: 18_000) == .fiveHour)
        #expect(QuotaWindow.Kind.from(seconds: 604_800) == .week)
        #expect(QuotaWindow.Kind.from(seconds: 3_600) == .other)
    }
}

struct PlanParsingTests {
    @Test("Codex plan_type")
    func codex() throws {
        let snapshot = try QuotaService.parseCodexQuota([
            "plan_type": "pro",
            "rate_limit": ["primary_window": ["used_percent": 1, "limit_window_seconds": 604_800]]
        ])
        #expect(snapshot.plan == "Pro 20x")
        #expect(QuotaService.codexPlanName("prolite") == "Pro 5x")
        #expect(QuotaService.codexPlanName("pro_max") == "Pro 20x")
        #expect(QuotaService.codexPlanName("plus") == "Plus")
        #expect(QuotaService.codexPlanName("unknown") == nil)
    }

    @Test("Claude 以 rate_limit_tier 細分 Max，其餘看 organization_type")
    func claude() {
        #expect(QuotaService.parseClaudePlan(["organization": ["organization_type": "claude_max", "rate_limit_tier": "default_claude_max_20x"]]) == "Max 20x")
        #expect(QuotaService.parseClaudePlan(["organization": ["organization_type": "claude_pro"]]) == "Pro")
        #expect(QuotaService.parseClaudePlan(["organization": ["organization_type": "personal"]]) == nil)
    }

    @Test("Antigravity 付費 tier 優先")
    func antigravity() {
        #expect(QuotaService.parseAntigravityPlan(["currentTier": ["id": "free-tier"], "paidTier": ["id": "g1-ultra-tier"]]) == "Ultra")
        #expect(QuotaService.parseAntigravityPlan(["currentTier": ["id": "free-tier"]]) == "Free")
    }

    @Test("Copilot 依 sku 與 copilot_plan")
    func copilot() {
        #expect(QuotaService.parseCopilotPlan(["access_type_sku": "free_limited_copilot", "copilot_plan": "individual"]) == "Free")
        #expect(QuotaService.parseCopilotPlan(["access_type_sku": "copilot_pro_plus", "copilot_plan": "individual"]) == "Pro+")
        #expect(QuotaService.parseCopilotPlan(["copilot_plan": "business"]) == "Business")
    }

    @Test("Codex 超過 7 天或沒有換新紀錄時提早換 token")
    func codexRefreshSchedule() throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        func credential(_ lastRefresh: Date?) throws -> Data {
            var root: [String: Any] = ["tokens": ["access_token": "a", "refresh_token": "r"]]
            if let lastRefresh { root["last_refresh"] = ISO8601DateFormatter().string(from: lastRefresh) }
            return try JSONSerialization.data(withJSONObject: root)
        }
        #expect(!OAuthService.codexNeedsRefresh(try credential(now.addingTimeInterval(-86_400)), now: now))
        #expect(OAuthService.codexNeedsRefresh(try credential(now.addingTimeInterval(-8 * 86_400)), now: now))
        #expect(OAuthService.codexNeedsRefresh(try credential(nil), now: now))
        #expect(!OAuthService.codexNeedsRefresh(Data(#"{"access_token":"a"}"#.utf8), now: now))
    }

    @Test("消費者方案與 gmail 帳號走 daily 後端，GCP ToS 走 prod")
    func resolvesAntigravityHost() {
        let daily = QuotaService.antigravityDailyHost
        let prod = QuotaService.antigravityProdHost
        // 問錯後端不會報錯，只會回一份永遠 100% 的額度，所以預設一律 daily。
        #expect(QuotaService.antigravityHost(tierID: nil, email: nil) == daily)
        #expect(QuotaService.antigravityHost(tierID: "g1-pro-tier", email: "a@example.com") == daily)
        #expect(QuotaService.antigravityHost(tierID: "free-tier", email: "a@example.com") == daily)
        #expect(QuotaService.antigravityHost(tierID: "standard-tier", email: "a@corp.com") == prod)
        // gmail／googlemail 一律不是 GCP ToS，即使 tier 對得上。
        #expect(QuotaService.antigravityHost(tierID: "standard-tier", email: "a@gmail.com") == daily)
        #expect(QuotaService.antigravityHost(tierID: "standard-tier", email: "A@GoogleMail.com") == daily)
    }

    @Test("tier id 取付費方案優先")
    func parsesAntigravityTierID() {
        #expect(QuotaService.parseAntigravityTierID(["paidTier": ["id": "g1-pro-tier"], "currentTier": ["id": "free-tier"]]) == "g1-pro-tier")
        #expect(QuotaService.parseAntigravityTierID(["currentTier": ["id": "free-tier"]]) == "free-tier")
        #expect(QuotaService.parseAntigravityTierID([:]) == nil)
    }
}
