import Foundation

struct Account: Codable, Identifiable, Equatable, Sendable {
    enum Origin: String, Codable, Sendable {
        case local, manual, file, oauth
    }

    let id: UUID
    let platform: PlatformKind
    var displayName: String
    var email: String?
    var planName: String?
    /// Antigravity 的原始 tier id（例如 `g1-pro-tier`、`standard-tier`），決定要問哪個 cloud code 後端。
    var tierID: String?
    var credentialReference: String?
    var quota: QuotaSnapshot?
    var lastError: String?
    var sourcePath: String?
    var isActive: Bool
    var origin: Origin

    /// 畫面與 menu bar 使用的名稱：有登入身分時取 email 的使用者名稱。
    var label: String {
        guard let email, !email.isEmpty else { return displayName }
        return String(email.split(separator: "@").first ?? Substring(email))
    }

    init(
        id: UUID = UUID(),
        platform: PlatformKind,
        displayName: String,
        email: String? = nil,
        planName: String? = nil,
        tierID: String? = nil,
        credentialReference: String? = nil,
        quota: QuotaSnapshot? = nil,
        lastError: String? = nil,
        sourcePath: String? = nil,
        isActive: Bool = false,
        origin: Origin = .manual
    ) {
        self.id = id
        self.platform = platform
        self.displayName = displayName
        self.email = email
        self.planName = planName
        self.tierID = tierID
        self.credentialReference = credentialReference
        self.quota = quota
        self.lastError = lastError
        self.sourcePath = sourcePath
        self.isActive = isActive
        self.origin = origin
    }

    private enum CodingKeys: String, CodingKey {
        case id, platform, displayName, email, planName, tierID, credentialReference, quota, lastError, sourcePath, isActive, origin
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        platform = try container.decode(PlatformKind.self, forKey: .platform)
        displayName = try container.decode(String.self, forKey: .displayName)
        email = try container.decodeIfPresent(String.self, forKey: .email)
        planName = try container.decodeIfPresent(String.self, forKey: .planName)
        tierID = try container.decodeIfPresent(String.self, forKey: .tierID)
        credentialReference = try container.decodeIfPresent(String.self, forKey: .credentialReference)
        quota = try container.decodeIfPresent(QuotaSnapshot.self, forKey: .quota)
        lastError = try container.decodeIfPresent(String.self, forKey: .lastError)
        sourcePath = try container.decodeIfPresent(String.self, forKey: .sourcePath)
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? false
        origin = try container.decodeIfPresent(Origin.self, forKey: .origin) ?? Self.inferOrigin(sourcePath: sourcePath)
    }

    static func inferOrigin(sourcePath: String?) -> Origin {
        guard let sourcePath else { return .local }
        if sourcePath == "手動加入" { return .manual }
        let localMarkers = ["macOS Keychain", "GitHub CLI", "/.codex/", "/.claude/", "/gh/hosts.yml", "Antigravity IDE/User/globalStorage/state.vscdb", "/.gemini/jetski-standalone-oauth-token"]
        return localMarkers.contains { sourcePath.contains($0) } ? .local : .file
    }
}
