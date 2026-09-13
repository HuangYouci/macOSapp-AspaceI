import Foundation
import Testing
@testable import AspaceI

struct AccountTransferServiceTests {
    @Test("匯出後再匯入保留平台、名稱與憑證；非 JSON 憑證以文字保存")
    func roundTrips() throws {
        let items = [
            AccountTransferItem(platform: .codex, displayName: "work", email: "w@x.com", credential: Data(#"{"tokens":{"access_token":"a"}}"#.utf8)),
            AccountTransferItem(platform: .githubCopilot, displayName: "GitHub", email: nil, credential: Data("github.com:\n  oauth_token: gho_x\n".utf8))
        ]
        let decoded = try AccountTransferService.decode(try AccountTransferService.encode(items))
        #expect(decoded.map(\.platform) == [.codex, .githubCopilot])
        #expect(decoded.first?.email == "w@x.com")
        #expect(decoded.last?.credential == items.last?.credential)
        let codex = try #require(try JSONSerialization.jsonObject(with: decoded[0].credential) as? [String: Any])
        #expect((codex["tokens"] as? [String: Any])?["access_token"] as? String == "a")
    }

    @Test("其他工具的陣列格式依欄位判斷平台")
    func detectsForeignAccounts() throws {
        let json = """
        [
          {"email": "g@x.com", "refresh_token": "1//r", "project_id": "p"},
          {"email": "c@x.com", "tokens": {"access_token": "a", "refresh_token": "r"}},
          {"github_access_token": "ghu_abc"},
          {"unknown": true}
        ]
        """
        let items = try AccountTransferService.decode(Data(json.utf8))
        #expect(items.map(\.platform) == [.antigravity, .codex, .githubCopilot])
        let antigravity = try #require(try JSONSerialization.jsonObject(with: items[0].credential) as? [String: Any])
        #expect(antigravity["project_id"] as? String == "p")
    }

    @Test("cockpit-tools 各平台匯出格式")
    func detectsCockpitExports() throws {
        let json = """
        [
          {"id": "1", "email": "g@x.com", "token": {"access_token": "a", "refresh_token": "1//r", "expires_in": 3599, "expiry_timestamp": 1, "token_type": "Bearer", "project_id": "p"}},
          {"id": "2", "email": "c@x.com", "tokens": {"id_token": "i", "access_token": "a", "refresh_token": "r"}},
          {"id": "3", "email": "k@x.com", "auth_mode": "oauth", "claude_credentials_raw": {"claudeAiOauth": {"accessToken": "a", "refreshToken": "r"}}},
          {"id": "4", "github_login": "octocat", "github_id": 1, "github_access_token": "gho_x", "copilot_token": "t"}
        ]
        """
        let items = try AccountTransferService.decode(Data(json.utf8))
        #expect(items.map(\.platform) == [.antigravity, .codex, .claude, .githubCopilot])
        #expect(items.map(\.email) == ["g@x.com", "c@x.com", "k@x.com", "octocat"])
        let claude = try #require(try JSONSerialization.jsonObject(with: items[2].credential) as? [String: Any])
        #expect((claude["claudeAiOauth"] as? [String: Any])?["accessToken"] as? String == "a")
    }

    @Test("沒有可辨識的帳號時回報錯誤")
    func rejectsEmpty() {
        #expect(throws: AccountTransferError.self) {
            try AccountTransferService.decode(Data(#"{"hello":"world"}"#.utf8))
        }
    }
}
