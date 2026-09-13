import Foundation

struct Account: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let platform: PlatformKind
    var displayName: String
    var email: String?
    var planName: String?
    var credentialReference: String?
    var quota: QuotaSnapshot?
    var lastError: String?
    var sourcePath: String?
    var isActive: Bool

    init(
        id: UUID = UUID(),
        platform: PlatformKind,
        displayName: String,
        email: String? = nil,
        planName: String? = nil,
        credentialReference: String? = nil,
        quota: QuotaSnapshot? = nil,
        lastError: String? = nil,
        sourcePath: String? = nil,
        isActive: Bool = false
    ) {
        self.id = id
        self.platform = platform
        self.displayName = displayName
        self.email = email
        self.planName = planName
        self.credentialReference = credentialReference
        self.quota = quota
        self.lastError = lastError
        self.sourcePath = sourcePath
        self.isActive = isActive
    }

    private enum CodingKeys: String, CodingKey {
        case id, platform, displayName, email, planName, credentialReference, quota, lastError, sourcePath, isActive
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        platform = try container.decode(PlatformKind.self, forKey: .platform)
        displayName = try container.decode(String.self, forKey: .displayName)
        email = try container.decodeIfPresent(String.self, forKey: .email)
        planName = try container.decodeIfPresent(String.self, forKey: .planName)
        credentialReference = try container.decodeIfPresent(String.self, forKey: .credentialReference)
        quota = try container.decodeIfPresent(QuotaSnapshot.self, forKey: .quota)
        lastError = try container.decodeIfPresent(String.self, forKey: .lastError)
        sourcePath = try container.decodeIfPresent(String.self, forKey: .sourcePath)
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? false
    }
}
