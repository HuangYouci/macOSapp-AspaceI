import Foundation

struct AccountTransferItem: Equatable, Sendable {
    let platform: PlatformKind
    let displayName: String
    let email: String?
    let credential: Data
}

/// 帳號匯出／匯入格式。匯出檔含完整登入憑證，只寫到使用者指定的位置。
enum AccountTransferService {
    static let format = "aspacei.accounts"
    static let version = 1

    static func encode(_ items: [AccountTransferItem], exportedAt: Date = .now) throws -> Data {
        let accounts: [[String: Any]] = items.map { item in
            var entry: [String: Any] = [
                "platform": item.platform.rawValue,
                "displayName": item.displayName
            ]
            if let email = item.email { entry["email"] = email }
            if let object = try? JSONSerialization.jsonObject(with: item.credential) {
                entry["credential"] = object
            } else {
                entry["credentialText"] = String(decoding: item.credential, as: UTF8.self)
            }
            return entry
        }
        let root: [String: Any] = [
            "format": format,
            "version": version,
            "exportedAt": ISO8601DateFormatter().string(from: exportedAt),
            "accounts": accounts
        ]
        return try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
    }

    static func decode(_ data: Data) throws -> [AccountTransferItem] {
        let object = try JSONSerialization.jsonObject(with: data)
        let items: [AccountTransferItem]
        if let root = object as? [String: Any], root["format"] as? String == format {
            items = (root["accounts"] as? [[String: Any]] ?? []).compactMap(decodeNative)
        } else if let array = object as? [[String: Any]] {
            items = array.compactMap(decodeForeign)
        } else if let single = object as? [String: Any] {
            items = [decodeForeign(single)].compactMap { $0 }
        } else {
            items = []
        }
        guard !items.isEmpty else { throw AccountTransferError.noAccounts }
        return items
    }

    private static func decodeNative(_ entry: [String: Any]) -> AccountTransferItem? {
        guard let platform = (entry["platform"] as? String).flatMap(PlatformKind.init(rawValue:)) else { return nil }
        let credential: Data?
        if let object = entry["credential"], JSONSerialization.isValidJSONObject(object) {
            credential = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        } else {
            credential = (entry["credentialText"] as? String).map { Data($0.utf8) }
        }
        guard let credential, !credential.isEmpty else { return nil }
        return AccountTransferItem(
            platform: platform,
            displayName: entry["displayName"] as? String ?? platform.displayName,
            email: entry["email"] as? String,
            credential: credential
        )
    }

    /// 其他工具（例如 cockpit-tools）匯出的帳號：依欄位形狀判斷平台。
    static func decodeForeign(_ entry: [String: Any]) -> AccountTransferItem? {
        let email = entry["email"] as? String ?? entry["github_email"] as? String ?? entry["github_login"] as? String
        func item(_ platform: PlatformKind, _ credential: Any) -> AccountTransferItem? {
            guard JSONSerialization.isValidJSONObject(credential),
                  let data = try? JSONSerialization.data(withJSONObject: credential, options: [.sortedKeys]) else { return nil }
            return AccountTransferItem(platform: platform, displayName: email ?? platform.displayName, email: email, credential: data)
        }

        if let tokens = entry["tokens"] as? [String: Any], tokens["access_token"] is String {
            return item(.codex, ["tokens": tokens])
        }
        if let oauth = entry["claudeAiOauth"] as? [String: Any] {
            return item(.claude, ["claudeAiOauth": oauth])
        }
        if let raw = entry["claude_credentials_raw"] as? [String: Any], raw["claudeAiOauth"] is [String: Any] {
            return item(.claude, raw)
        }
        if entry["auth_mode"] as? String == "setup_token", let token = entry["api_key"] as? String {
            return item(.claude, ["accessToken": token])
        }
        let githubToken = entry["github_access_token"] as? String
            ?? (entry["access_token"] as? String).flatMap { $0.hasPrefix("gh") ? $0 : nil }
        if let githubToken {
            return item(.githubCopilot, ["access_token": githubToken])
        }
        let token = entry["token"] as? [String: Any]
        if let refreshToken = entry["refresh_token"] as? String ?? entry["refreshToken"] as? String ?? token?["refresh_token"] as? String {
            var credential: [String: Any] = ["refresh_token": refreshToken]
            if let project = entry["project_id"] as? String ?? entry["projectId"] as? String ?? token?["project_id"] as? String {
                credential["project_id"] = project
            }
            return item(.antigravity, credential)
        }
        return nil
    }
}

enum AccountTransferError: LocalizedError {
    case noAccounts

    var errorDescription: String? {
        "檔案中沒有可匯入的帳號"
    }
}
