import CommonCrypto
import Foundation
import Testing
@testable import AspaceI

struct ClaudeDesktopCredentialTests {
    private static let account = "ae4d01e7-cc5c-421c-9ac0-0e9167f75c9d"
    private static let other = "10eea265-eb15-4ce1-afbb-00ca1a416138"
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    private static func cacheKey(_ account: String, client: String = "9d1c250a-e61b-44d9-88ed-5944d1962f5e", scopes: String) -> String {
        "acct:\(account)|\(client):d4346b69-0012-45ab-8a86-0f686e206745:https://api.anthropic.com:\(scopes)"
    }

    private static func entry(_ token: String, expiresIn seconds: Double) -> [String: Any] {
        ["token": token, "refreshToken": "r-\(token)", "expiresAt": (now.timeIntervalSince1970 + seconds) * 1000]
    }

    private static func encrypt(_ object: [String: Any], password: String) throws -> String {
        let plain = try JSONSerialization.data(withJSONObject: object)
        let key = try ClaudeDesktopCredentialService.deriveKey(password: password)
        let cipher = try ClaudeDesktopCredentialService.aesCBC(operation: CCOperation(kCCEncrypt), input: plain, key: key)
        return (Data("v10".utf8) + cipher).base64EncodedString()
    }

    @Test("快取 key 解析出帳號與 scope")
    func parsesCacheKey() throws {
        let parsed = try #require(ClaudeDesktopCredentialService.parseCacheKey(Self.cacheKey(Self.account, scopes: "user:inference user:profile")))
        #expect(parsed.accountUUID == Self.account)
        #expect(parsed.scopes == ["user:inference", "user:profile"])
        #expect(ClaudeDesktopCredentialService.parseCacheKey("not-a-key") == nil)
    }

    @Test("只挑這個帳號、帶 user:profile、還沒過期的 token，同帳號取最晚到期")
    func selectsUsableToken() throws {
        let cache: [String: Any] = [
            Self.cacheKey(Self.account, scopes: "user:inference user:profile"): Self.entry("short", expiresIn: 3_600),
            Self.cacheKey(Self.account, client: "a473d7bb-17ac-43a7-abc0-a1343d7c2805", scopes: "user:profile"): Self.entry("long", expiresIn: 86_400),
            Self.cacheKey(Self.account, client: "89355bc3-cbfd-4382-905b-976645cad410", scopes: "user:inference"): Self.entry("noProfile", expiresIn: 999_999),
            Self.cacheKey(Self.account, client: "00000000-0000-4000-8000-000000000000", scopes: "user:profile"): Self.entry("expired", expiresIn: 30),
            Self.cacheKey(Self.other, scopes: "user:profile"): Self.entry("otherAccount", expiresIn: 999_999)
        ]
        let token = try #require(ClaudeDesktopCredentialService.selectToken(fromCache: cache, accountUUID: Self.account.uppercased(), now: Self.now))
        #expect(token.accessToken == "long")
        #expect(ClaudeDesktopCredentialService.selectToken(fromCache: [:], accountUUID: Self.account, now: Self.now) == nil)
    }

    @Test("解開實例的 config.json：登入中的帳號與可用 token，只放 access token")
    func readsSignInFromConfig() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "aspacei-claude-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = [Self.cacheKey(Self.account, scopes: "user:inference user:profile"): Self.entry("access", expiresIn: 86_400)]
        let config: [String: Any] = ["lastKnownAccountUuid": Self.account, "oauth:tokenCacheV2": try Self.encrypt(cache, password: "secret")]
        try JSONSerialization.data(withJSONObject: config).write(to: directory.appending(path: "config.json"))

        let service = ClaudeDesktopCredentialService(readPassword: { "secret" })
        let signIn = try #require(try service.signIn(inDataDirectory: directory, now: Self.now))
        #expect(signIn.accountUUID == Self.account)
        let token = try #require(signIn.token)
        let credential = try ClaudeDesktopCredentialService.credentialData(for: token)
        let root = try #require(try JSONSerialization.jsonObject(with: credential) as? [String: String])
        #expect(root == ["accessToken": "access"])
    }

    @Test("沒登入或實例沒開過時不算偵測到")
    func ignoresSignedOutInstance() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "aspacei-claude-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = ClaudeDesktopCredentialService(readPassword: { "secret" })
        #expect(try service.signIn(inDataDirectory: directory, now: Self.now) == nil)
        try JSONSerialization.data(withJSONObject: ["lastKnownAccountUuid": Self.account]).write(to: directory.appending(path: "config.json"))
        #expect(try service.signIn(inDataDirectory: directory, now: Self.now) == nil)
    }

    @Test("鑰匙圈被拒後不自動重問，使用者按更新才再問一次")
    func doesNotAskAgainAfterDenial() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "aspacei-claude-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let config: [String: Any] = ["lastKnownAccountUuid": Self.account, "oauth:tokenCacheV2": "djEw"]
        try JSONSerialization.data(withJSONObject: config).write(to: directory.appending(path: "config.json"))
        let counter = Counter()
        let service = ClaudeDesktopCredentialService(readPassword: {
            counter.increment()
            throw ClaudeDesktopCredentialError.keyUnavailable(errSecAuthFailed)
        })
        #expect(throws: ClaudeDesktopCredentialError.keyUnavailable(errSecAuthFailed)) { try service.signIn(inDataDirectory: directory, now: Self.now) }
        #expect(throws: ClaudeDesktopCredentialError.keyUnavailable(errSecAuthFailed)) { try service.signIn(inDataDirectory: directory, now: Self.now) }
        #expect(counter.value == 1)
        service.allowRetry()
        #expect(throws: ClaudeDesktopCredentialError.keyUnavailable(errSecAuthFailed)) { try service.signIn(inDataDirectory: directory, now: Self.now) }
        #expect(counter.value == 2)
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
}

struct InstanceAccountReconcileTests {
    private static let uuid = "ae4d01e7-cc5c-421c-9ac0-0e9167f75c9d"
    private static let credential = Data(#"{"accessToken":"a"}"#.utf8)

    private static func detectedClaude(_ uuid: String = uuid, credential: Data? = credential) -> DetectedInstanceAccount {
        DetectedInstanceAccount(platform: .claude, instanceName: "2-big", accountUUID: uuid, email: nil, credential: credential)
    }

    @Test("瀏覽器登入過的帳號改用實例的登入，不另外加一列")
    func backsExistingAccount() {
        let existing = Account(platform: .claude, displayName: "max-1", email: "claude-max-1@example.com", accountUUID: Self.uuid, credentialReference: "claude.x", isActive: true, origin: .oauth)
        let result = AccountManager.reconcileInstanceAccounts([existing], detected: [Self.detectedClaude(Self.uuid.uppercased())], dismissed: [])
        #expect(result.accounts == [existing])
        #expect(result.backing == [existing.id: .usable(Self.credential)])
    }

    @Test("清單上沒有的帳號自動加入，使用者移除過的不加回")
    func addsNewAccountUnlessDismissed() throws {
        let added = AccountManager.reconcileInstanceAccounts([], detected: [Self.detectedClaude()], dismissed: [])
        let account = try #require(added.accounts.first)
        #expect(added.accounts.count == 1)
        #expect(account.origin == .instance)
        #expect(account.accountUUID == Self.uuid)
        #expect(account.credentialReference == nil)
        #expect(account.isActive)
        #expect(added.backing[account.id] == .usable(Self.credential))

        let dismissed = AccountManager.reconcileInstanceAccounts([], detected: [Self.detectedClaude()], dismissed: ["claude:\(Self.uuid)"])
        #expect(dismissed.accounts.isEmpty)
        #expect(dismissed.backing.isEmpty)
    }

    @Test("實例有登入但 token 過期時標成過期，不退回 AspaceI 自己的登入")
    func marksExpiredInstanceLogin() {
        let existing = Account(platform: .claude, displayName: "max-1", accountUUID: Self.uuid, credentialReference: "claude.x", origin: .oauth)
        let result = AccountManager.reconcileInstanceAccounts([existing], detected: [Self.detectedClaude(credential: nil)], dismissed: [])
        #expect(result.backing == [existing.id: .expired])
    }

    @Test("Codex 依 email 對應，不分大小寫")
    func matchesCodexByEmail() {
        let existing = Account(platform: .codex, displayName: "Codex", email: "User@Example.com", credentialReference: "codex.x", origin: .oauth)
        let detected = DetectedInstanceAccount(platform: .codex, instanceName: "c-1", accountUUID: nil, email: "user@example.com", credential: Self.credential)
        let result = AccountManager.reconcileInstanceAccounts([existing], detected: [detected], dismissed: [])
        #expect(result.accounts == [existing])
        #expect(result.backing == [existing.id: .usable(Self.credential)])
    }

    @Test("同帳號登入在多個實例時留有可用 token 的那個")
    func mergesDuplicateSignIns() {
        let expired = Self.detectedClaude(credential: nil)
        let usable = Self.detectedClaude()
        #expect(InstanceAccountDetector.merging([expired, usable]) == [usable])
        #expect(InstanceAccountDetector.merging([usable, expired]) == [usable])
    }
}

struct CodexInstanceProjectionTests {
    private static func authJSON(email: String) throws -> Data {
        let payload = try JSONSerialization.data(withJSONObject: ["email": email]).base64URLEncoded
        let tokens: [String: Any] = ["id_token": "e30.\(payload).sig", "access_token": "a", "refresh_token": "r"]
        return try JSONSerialization.data(withJSONObject: ["tokens": tokens])
    }

    @Test("實例裡已經是同一個帳號就不覆寫，換帳號或沒有檔案才寫入")
    func skipsProjectionForSameAccount() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "aspacei-codex-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let account = Account(platform: .codex, displayName: "Codex", email: "a@example.com", origin: .oauth)
        #expect(InstanceManager.needsProjection(of: account, into: directory))
        try Self.authJSON(email: "A@example.com").write(to: directory.appending(path: "auth.json"))
        #expect(!InstanceManager.needsProjection(of: account, into: directory))
        try Self.authJSON(email: "b@example.com").write(to: directory.appending(path: "auth.json"))
        #expect(InstanceManager.needsProjection(of: account, into: directory))
    }
}
