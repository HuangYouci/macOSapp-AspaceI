import Foundation
import Testing
@testable import AspaceI

struct OAuthServiceTests {
    @Test("PKCE challenge 符合 RFC 7636 範例")
    func pkceMatchesRFCVector() {
        #expect(PKCE.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk") == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        let generated = PKCE.generate()
        #expect(generated.verifier.count >= 43)
        #expect(!generated.verifier.contains("="))
    }

    @Test("Codex 授權網址使用官方 loopback 回呼與 S256")
    func codexAuthorizationURL() throws {
        let pkce = PKCE(verifier: "v", challenge: "c")
        let authorization = try #require(OAuthService.authorization(for: .codex, pkce: pkce, state: "s"))
        let items = try #require(URLComponents(url: authorization.url, resolvingAgainstBaseURL: false)?.queryItems)
        let query = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        #expect(query["redirect_uri"] == "http://localhost:1455/auth/callback")
        #expect(query["code_challenge"] == "c")
        #expect(query["code_challenge_method"] == "S256")
        #expect(query["state"] == "s")
        #expect(authorization.callbackPort == 1455)
    }

    @Test("Antigravity 授權網址要求 offline 以取得 refresh token")
    func antigravityAuthorizationRequestsOfflineAccess() throws {
        let authorization = try #require(OAuthService.authorization(for: .antigravity))
        let items = try #require(URLComponents(url: authorization.url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(items.contains { $0.name == "access_type" && $0.value == "offline" })
        #expect(items.contains { $0.name == "prompt" && $0.value == "consent" })
        #expect(OAuthService.authorization(for: .githubCopilot) == nil)
    }

    @Test("Claude 授權碼接受 code#state 與完整回呼網址")
    func parsesClaudeCode() {
        #expect(OAuthService.parseClaudeCode(" abc#xyz \n") == ("abc", "xyz"))
        #expect(OAuthService.parseClaudeCode("abc") == ("abc", nil))
        let fromURL = OAuthService.parseClaudeCode("https://platform.claude.com/oauth/code/callback?code=abc&state=xyz")
        #expect(fromURL.code == "abc")
        #expect(fromURL.state == "xyz")
    }

    @Test("Codex 憑證寫成官方 auth.json 形狀並從 id_token 取 email 與 account_id")
    func buildsCodexAuthJSON() throws {
        let claims: [String: Any] = ["email": "a@b.com", "https://api.openai.com/auth": ["chatgpt_account_id": "acct-1"]]
        let payload = try JSONSerialization.data(withJSONObject: claims).base64URLEncoded
        let credential = try OAuthService.codexCredential(from: [
            "access_token": "at", "refresh_token": "rt", "id_token": "h.\(payload).s"
        ])
        let root = try #require(try JSONSerialization.jsonObject(with: credential.data) as? [String: Any])
        let tokens = try #require(root["tokens"] as? [String: Any])
        #expect(tokens["access_token"] as? String == "at")
        #expect(tokens["account_id"] as? String == "acct-1")
        #expect(credential.email == "a@b.com")
    }

    @Test("Claude 憑證寫成 Claude Code 形狀，過期判定提前一分鐘")
    func buildsClaudeCredentialAndDetectsExpiry() throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let credential = try OAuthService.claudeCredential(from: [
            "access_token": "at", "refresh_token": "rt", "expires_in": 3600,
            "account": ["email_address": "c@d.com"]
        ], now: now)
        #expect(credential.email == "c@d.com")
        #expect(!OAuthService.claudeTokenExpired(credential.data, now: now))
        #expect(OAuthService.claudeTokenExpired(credential.data, now: now.addingTimeInterval(3_550)))
    }

    @Test("Antigravity 沒有 refresh token 時拒絕建立帳號")
    func antigravityRequiresRefreshToken() {
        #expect(throws: OAuthError.missingRefreshToken) {
            try OAuthService.antigravityCredential(from: ["access_token": "at"])
        }
    }

    @Test("Antigravity 授權要求 openid 才拿得到 id_token")
    func antigravityAuthorizationRequestsOpenID() throws {
        let authorization = try #require(OAuthService.authorization(for: .antigravity))
        let items = try #require(URLComponents(url: authorization.url, resolvingAgainstBaseURL: false)?.queryItems)
        let scope = try #require(items.first { $0.name == "scope" }?.value)
        #expect(scope.split(separator: " ").contains("openid"))
    }

    @Test("Antigravity 換發：沿用原本的 refresh token，寫入新的 access token 與到期時間")
    func antigravityRefreshKeepsRefreshToken() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let existing = Data(#"{"auth_method":"consumer","token":{"access_token":"old","refresh_token":"1//r","expiry":"1970-01-01T00:00:00Z"}}"#.utf8)
        let refreshed = try OAuthService.antigravityRefreshed(
            from: ["access_token": "new", "expires_in": 3_599 as NSNumber, "id_token": "h.p.s"],
            existing: existing,
            now: now
        )
        let root = try #require(try JSONSerialization.jsonObject(with: refreshed) as? [String: Any])
        let token = try #require(root["token"] as? [String: Any])
        #expect(token["access_token"] as? String == "new")
        #expect(token["refresh_token"] as? String == "1//r")
        #expect(root["id_token"] as? String == "h.p.s")
        let expiry = try #require((token["expiry"] as? String).flatMap(OAuthService.isoDate))
        #expect(expiry > now)
        #expect(AccountManager.antigravityTokenUsable(refreshed, now: now))
        #expect(!AccountManager.antigravityTokenUsable(existing, now: now))
    }

    @Test("Antigravity 換發沒有 access token 就失敗")
    func antigravityRefreshRequiresAccessToken() {
        let existing = Data(#"{"refresh_token":"1//r"}"#.utf8)
        #expect(throws: OAuthError.invalidResponse) {
            try OAuthService.antigravityRefreshed(from: ["expires_in": 3_599 as NSNumber], existing: existing)
        }
    }

    @Test("回呼伺服器只接受指定路徑")
    func parsesCallbackRequest() {
        let query = OAuthCallbackServer.parseRequest("GET /auth/callback?code=abc&state=s HTTP/1.1\r\nHost: localhost\r\n\r\n", expectedPath: "/auth/callback")
        #expect(query == ["code": "abc", "state": "s"])
        #expect(OAuthCallbackServer.parseRequest("GET /favicon.ico HTTP/1.1\r\n\r\n", expectedPath: "/auth/callback") == nil)
    }
}

struct OAuthCallbackServerTests {
    @Test("本機回呼伺服器收到轉址後回傳 query 並關閉")
    func receivesLoopbackRedirect() async throws {
        let server = OAuthCallbackServer()
        async let callback = server.waitForCallback(port: 51_999, path: "/oauth-callback", timeout: .seconds(10))
        try await Task.sleep(for: .milliseconds(300))
        let url = try #require(URL(string: "http://localhost:51999/oauth-callback?code=abc&state=xyz"))
        let (_, response) = try await URLSession.shared.data(from: url)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        let query = try await callback
        #expect(query["code"] == "abc")
        #expect(query["state"] == "xyz")
    }

    @Test("逾時會拋出錯誤")
    func timesOut() async {
        let server = OAuthCallbackServer()
        await #expect(throws: OAuthError.timedOut) {
            try await server.waitForCallback(port: 51_998, path: "/cb", timeout: .milliseconds(200))
        }
    }
}
