import Foundation
import Testing
@testable import AspaceI

struct AccountMigrationTests {
    @Test
    func decodesAccountSavedBeforeActiveSelectionExisted() throws {
        let id = UUID()
        let json = """
        {"id":"\(id.uuidString)","platform":"codex","displayName":"Codex"}
        """
        let account = try JSONDecoder().decode(Account.self, from: Data(json.utf8))
        #expect(account.isActive == false)
    }

    @Test("舊資料沒有 origin 時依來源路徑推斷")
    func infersOriginFromLegacySourcePath() {
        #expect(Account.inferOrigin(sourcePath: "GitHub CLI") == .local)
        #expect(Account.inferOrigin(sourcePath: "/Users/a/.config/gh/hosts.yml") == .local)
        #expect(Account.inferOrigin(sourcePath: "/Users/a/.gemini/jetski-standalone-oauth-token") == .local)
        #expect(Account.inferOrigin(sourcePath: "手動加入") == .manual)
        #expect(Account.inferOrigin(sourcePath: "/Users/a/Downloads/work.json") == .file)
    }

    @Test("同平台重複的本機帳號只留有憑證的那一個，並補回目前帳號")
    @MainActor
    func collapsesDuplicateLocalAccounts() {
        let orphan = Account(platform: .githubCopilot, displayName: "GitHub", sourcePath: "hosts.yml", isActive: true, origin: .local)
        let withCredential = Account(platform: .githubCopilot, displayName: "GitHub", credentialReference: "githubCopilot.x", sourcePath: "GitHub CLI", origin: .local)
        let manual = Account(platform: .githubCopilot, displayName: "Work", credentialReference: "githubCopilot.y", origin: .manual)
        let (kept, dropped) = AccountManager.collapsingDuplicateLocalAccounts([orphan, withCredential, manual])
        #expect(dropped.map(\.id) == [orphan.id])
        #expect(kept.map(\.id) == [withCredential.id, manual.id])
        #expect(kept.first?.isActive == true)
    }
}

@MainActor
struct DefaultClientTests {
    @Test("官方 App 目前帳號：切換過就用切換的，否則是本機匯入的帳號")
    func resolvesDefaultClientAccount() {
        let local = Account(platform: .codex, displayName: "local", origin: .local)
        let other = Account(platform: .codex, displayName: "other", origin: .oauth)
        #expect(AccountManager.resolveDefaultClientAccount(for: .codex, accounts: [local, other], mapping: [:])?.id == local.id)
        #expect(AccountManager.resolveDefaultClientAccount(for: .codex, accounts: [local, other], mapping: [.codex: other.id])?.id == other.id)
        #expect(AccountManager.resolveDefaultClientAccount(for: .codex, accounts: [local], mapping: [.codex: UUID()])?.id == local.id)
        #expect(AccountManager.resolveDefaultClientAccount(for: .antigravity, accounts: [local, other], mapping: [:]) == nil)
    }

    @Test("Codex 官方檔的 email 對不上時不覆寫帳號")
    func codexFileIdentityGuard() throws {
        let payload = try JSONSerialization.data(withJSONObject: ["email": "a@x.com"]).base64URLEncoded
        let file = try JSONSerialization.data(withJSONObject: ["tokens": ["id_token": "h.\(payload).s", "access_token": "a", "refresh_token": "r"]])
        #expect(AccountManager.localFile(file, belongsTo: Account(platform: .codex, displayName: "", email: "A@x.com")))
        #expect(!AccountManager.localFile(file, belongsTo: Account(platform: .codex, displayName: "", email: "b@x.com")))
        #expect(AccountManager.localFile(file, belongsTo: Account(platform: .codex, displayName: "", email: nil, origin: .local)))
        #expect(!AccountManager.localFile(file, belongsTo: Account(platform: .codex, displayName: "", email: nil, origin: .oauth)))
    }

    @Test("Antigravity 官方檔換成別的帳號時不覆寫切換進來的帳號")
    func antigravityFileIdentityGuard() throws {
        let payload = try JSONSerialization.data(withJSONObject: ["email": "a@x.com"]).base64URLEncoded
        let file = try JSONSerialization.data(withJSONObject: [
            "id_token": "h.\(payload).s",
            "token": ["access_token": "a", "refresh_token": "ra"]
        ])
        let switched = Account(platform: .antigravity, displayName: "b", email: "b@x.com", origin: .file)
        #expect(!AccountManager.localFile(file, belongsTo: switched))
        #expect(AccountManager.localFile(file, belongsTo: Account(platform: .antigravity, displayName: "a", email: "a@x.com", origin: .file)))
    }

    @Test("身分不明時比對 refresh token：同一個登入才同步回帳號")
    func antigravityRefreshTokenGuard() throws {
        let file = try JSONSerialization.data(withJSONObject: ["token": ["access_token": "new", "refresh_token": "ra"]])
        let sameLogin = try JSONSerialization.data(withJSONObject: ["refresh_token": "ra"])
        let otherLogin = try JSONSerialization.data(withJSONObject: ["refresh_token": "rb"])
        let account = Account(platform: .antigravity, displayName: "b", origin: .file)
        #expect(AccountManager.localFile(file, belongsTo: account, credential: sameLogin))
        #expect(!AccountManager.localFile(file, belongsTo: account, credential: otherLogin))
    }
}

struct DefaultClientProjectionTests {
    @Test("切換 Codex 需要完整 auth.json 並寫入 ~/.codex")
    func projectsCodex() throws {
        let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: home) }
        let account = Account(platform: .codex, displayName: "c")
        let full = Data(#"{"tokens":{"access_token":"a","refresh_token":"r","id_token":"i"}}"#.utf8)
        try CredentialProjectionService.shared.projectToDefaultClient(account: account, credentialData: full, homeDirectory: home)
        #expect(try Data(contentsOf: home.appending(path: ".codex/auth.json")) == full)
        #expect(throws: CredentialProjectionError.self) {
            try CredentialProjectionService.shared.projectToDefaultClient(account: account, credentialData: Data(#"{"access_token":"a"}"#.utf8), homeDirectory: home)
        }
    }

    @Test("切換 Antigravity 寫出完整憑證，只有 refresh token 時拒絕")
    func projectsAntigravity() throws {
        let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: home) }
        let account = Account(platform: .antigravity, displayName: "g")
        // 絕不能用預設的寫入器：那會改到這台機器上 Antigravity 正在用的登入 Keychain。
        var written: [Data] = []
        let complete = Data(#"{"auth_method":"consumer","token":{"access_token":"ya29.a","refresh_token":"1//r","token_type":"Bearer","expiry":"2099-01-01T00:00:00Z"}}"#.utf8)
        try CredentialProjectionService.shared.projectToDefaultClient(
            account: account,
            credentialData: complete,
            homeDirectory: home,
            writeSystemCredential: { written.append($0) }
        )
        #expect(written.count == 1)
        let keychain = try #require(try JSONSerialization.jsonObject(with: written[0]) as? [String: Any])
        #expect((keychain["token"] as? [String: Any])?["refresh_token"] as? String == "1//r")
        #expect(keychain["auth_method"] as? String == "consumer")
        // jetski 檔案仍然同步一份給 Gemini CLI 與舊版。
        let file = try JSONSerialization.jsonObject(with: try Data(contentsOf: home.appending(path: ".gemini/jetski-standalone-oauth-token"))) as? [String: Any]
        #expect((file?["token"] as? [String: Any])?["access_token"] as? String == "ya29.a")

        // 只有 refresh token 時會被擋下，而且不碰任何目的地。
        #expect(throws: CredentialProjectionError.self) {
            try CredentialProjectionService.shared.projectToDefaultClient(
                account: account,
                credentialData: Data(#"{"refresh_token":"1//r"}"#.utf8),
                homeDirectory: home,
                writeSystemCredential: { written.append($0) }
            )
        }
        #expect(written.count == 1)
    }

    @Test("Claude 與 Copilot 不支援切換")
    func rejectsUnsupported() {
        #expect(throws: CredentialProjectionError.self) {
            try CredentialProjectionService.shared.projectToDefaultClient(account: Account(platform: .claude, displayName: ""), credentialData: Data("{}".utf8))
        }
    }
}
