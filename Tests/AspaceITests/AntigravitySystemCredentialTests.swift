import Foundation
import Testing
@testable import AspaceI

@MainActor
@Suite("Antigravity 系統憑據")
struct AntigravitySystemCredentialTests {
    private func credential(email: String? = nil, refreshToken: String = "1//0eSAMPLE") -> Data {
        var object: [String: Any] = [
            "auth_method": "consumer",
            "token": [
                "access_token": "ya29.sample",
                "refresh_token": refreshToken,
                "token_type": "Bearer",
                "expiry": "2026-09-18T08:16:41Z"
            ]
        ]
        if let email {
            let claims = try! JSONSerialization.data(withJSONObject: ["email": email])
            let body = claims.base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
            object["id_token"] = "header.\(body).signature"
        }
        return try! JSONSerialization.data(withJSONObject: object)
    }

    @Test("go-keyring 的 base64 包裝可以還原成 JSON")
    func decodesGoKeyringWrapper() throws {
        let payload = credential()
        let wrapped = Data("go-keyring-base64:\(payload.base64EncodedString())".utf8)
        let decoded = try #require(AntigravitySystemCredentialService.decode(wrapped))
        let root = try #require(try JSONSerialization.jsonObject(with: decoded) as? [String: Any])
        let token = try #require(root["token"] as? [String: Any])
        #expect(token["refresh_token"] as? String == "1//0eSAMPLE")
    }

    @Test("沒有包裝的純 JSON 也接受")
    func decodesPlainJSON() throws {
        let payload = credential()
        let decoded = try #require(AntigravitySystemCredentialService.decode(payload))
        #expect((try? JSONSerialization.jsonObject(with: decoded)) != nil)
    }

    @Test("寫入前正規化成官方檔案的形狀並保留 id_token")
    func canonicalKeepsIdentity() throws {
        let payload = credential(email: "someone@example.com")
        let canonical = AntigravitySystemCredentialService.canonical(payload)
        let root = try #require(try JSONSerialization.jsonObject(with: canonical) as? [String: Any])
        #expect(root["auth_method"] as? String == "consumer")
        #expect(root["id_token"] != nil)
        #expect(AccountManager.credentialEmail(canonical, platform: .antigravity) == "someone@example.com")
    }
}
