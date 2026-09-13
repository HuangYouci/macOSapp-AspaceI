import Foundation
import Testing
@testable import AspaceI

struct QuotaServiceTests {
    @Test
    func parsesCodexUsageWindowsAsRemainingPercentage() throws {
        let result = try QuotaService.parseCodexQuota([
            "rate_limit": [
                "primary_window": ["used_percent": 25, "reset_at": 1_800_000_000],
                "secondary_window": ["used_percent": 80, "reset_at": 1_900_000_000]
            ]
        ])
        #expect(result.windows.map(\.remainingPercentage) == [75, 20])
    }

    @Test
    func parsesClaudeUtilizationAsRemainingPercentage() throws {
        let result = try QuotaService.parseClaudeQuota([
            "five_hour": ["utilization": 12.0, "resets_at": "2026-09-13T12:00:00Z"],
            "seven_day": ["utilization": 42.0, "resets_at": "2026-09-20T12:00:00Z"]
        ])
        #expect(result.windows.map(\.remainingPercentage) == [88, 58])
    }

    @Test
    func parsesGitHubRateLimitResources() throws {
        let result = try QuotaService.parseGitHubQuota([
            "resources": ["core": ["limit": 5_000, "remaining": 3_750, "reset": 1_800_000_000]]
        ])
        #expect(result.windows.first?.remainingPercentage == 75)
        #expect(result.windows.first?.id == "core")
    }

    @Test
    func parsesAntigravityQuotaBuckets() throws {
        let result = try QuotaService.parseAntigravityQuota([
            "groups": [[
                "buckets": [["bucketId": "claude-5h", "displayName": "Claude 5h", "remainingFraction": 0.64, "resetTime": "2026-09-13T12:00:00Z"]]
            ]]
        ])
        #expect(result.windows.first?.remainingPercentage == 64)
        #expect(result.windows.first?.title == "Claude 5h")
    }
}
