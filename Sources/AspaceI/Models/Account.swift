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

    init(
        id: UUID = UUID(),
        platform: PlatformKind,
        displayName: String,
        email: String? = nil,
        planName: String? = nil,
        credentialReference: String? = nil,
        quota: QuotaSnapshot? = nil,
        lastError: String? = nil,
        sourcePath: String? = nil
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
    }
}
