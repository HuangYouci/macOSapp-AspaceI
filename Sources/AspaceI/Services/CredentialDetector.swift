import Foundation

/// 判斷使用者貼上或拖入的內容是哪一種憑證，讓匯入畫面不必先選對平台。
enum CredentialDetector {
    enum Result: Equatable {
        case credential(PlatformKind)
        case accountFile(count: Int)
        case unknown
    }

    static func detect(_ text: String) -> Result {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .unknown }
        let data = Data(trimmed.utf8)

        if let object = try? JSONSerialization.jsonObject(with: data) {
            if let root = object as? [String: Any], root["format"] as? String == AccountTransferService.format {
                return .accountFile(count: (root["accounts"] as? [Any])?.count ?? 0)
            }
            if object is [Any], let items = try? AccountTransferService.decode(data) {
                return .accountFile(count: items.count)
            }
            if let root = object as? [String: Any] {
                if root["claudeAiOauth"] is [String: Any] { return .credential(.claude) }
                if let item = AccountTransferService.decodeForeign(root) { return .credential(item.platform) }
            }
            return .unknown
        }

        if trimmed.contains("oauth_token:") { return .credential(.githubCopilot) }
        let prefixes: [(String, PlatformKind)] = [
            ("sk-ant-", .claude),
            ("1//", .antigravity),
            ("ya29.", .antigravity),
            ("gho_", .githubCopilot),
            ("ghu_", .githubCopilot),
            ("ghp_", .githubCopilot),
            ("github_pat_", .githubCopilot)
        ]
        if let match = prefixes.first(where: { trimmed.hasPrefix($0.0) }) { return .credential(match.1) }
        if trimmed.hasPrefix("eyJ"), let claims = OAuthService.jwtClaims(trimmed), claims["https://api.openai.com/auth"] != nil {
            return .credential(.codex)
        }
        return .unknown
    }
}
