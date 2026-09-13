import Foundation
import Testing
@testable import AspaceI

struct CredentialDetectorTests {
    @Test("各平台官方憑證檔內容")
    func detectsOfficialFiles() {
        #expect(CredentialDetector.detect(#"{"OPENAI_API_KEY":null,"tokens":{"id_token":"i","access_token":"a","refresh_token":"r"}}"#) == .credential(.codex))
        #expect(CredentialDetector.detect(#"{"claudeAiOauth":{"accessToken":"a","refreshToken":"r"}}"#) == .credential(.claude))
        #expect(CredentialDetector.detect(#"{"auth_method":"consumer","token":{"access_token":"a","refresh_token":"1//r"}}"#) == .credential(.antigravity))
        #expect(CredentialDetector.detect("github.com:\n    oauth_token: gho_x\n    user: octocat") == .credential(.githubCopilot))
    }

    @Test("單一 token 依前綴判斷")
    func detectsRawTokens() {
        #expect(CredentialDetector.detect("sk-ant-oat01-abc") == .credential(.claude))
        #expect(CredentialDetector.detect(" 1//0e-refresh ") == .credential(.antigravity))
        #expect(CredentialDetector.detect("gho_abc") == .credential(.githubCopilot))
        #expect(CredentialDetector.detect("hello") == .unknown)
    }

    @Test("Codex access token 是帶 OpenAI claim 的 JWT")
    func detectsCodexJWT() throws {
        let payload = try JSONSerialization.data(withJSONObject: ["https://api.openai.com/auth": ["chatgpt_account_id": "x"]]).base64URLEncoded
        #expect(CredentialDetector.detect("eyJhbGciOiJSUzI1NiJ9.\(payload).sig") == .credential(.codex))
    }

    @Test("帳號備份檔與 cockpit 陣列")
    func detectsAccountFiles() throws {
        let export = try AccountTransferService.encode([
            AccountTransferItem(platform: .codex, displayName: "a", email: nil, credential: Data(#"{"tokens":{"access_token":"a"}}"#.utf8))
        ])
        #expect(CredentialDetector.detect(String(decoding: export, as: UTF8.self)) == .accountFile(count: 1))
        #expect(CredentialDetector.detect(#"[{"email":"a","tokens":{"access_token":"a"}},{"github_access_token":"gho_x"}]"#) == .accountFile(count: 2))
    }

    @Test("Antigravity 貼上 refresh token 存成 refresh_token；GitHub hosts.yml 保留原文")
    func wrapsPlainText() throws {
        let antigravity = try CredentialImportService.shared.importText("1//abc", platform: .antigravity, displayName: "")
        let data = try #require(antigravity.data)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: String])
        #expect(object == ["refresh_token": "1//abc"])
        let yaml = "github.com:\n    oauth_token: gho_x\n"
        #expect(try CredentialImportService.shared.importText(yaml, platform: .githubCopilot, displayName: "").data == Data(yaml.trimmingCharacters(in: .whitespacesAndNewlines).utf8))
    }
}
