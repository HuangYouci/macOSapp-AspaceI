import Foundation

/// 從實例資料夾讀到的登入。AspaceI 只拿來查額度：不存進 Keychain、不換新，換新由實例的 App 負責。
struct DetectedInstanceAccount: Equatable, Sendable {
    let platform: PlatformKind
    let instanceName: String
    /// Claude 以帳號編號辨識。
    let accountUUID: String?
    /// Codex 以 id_token 裡的 email 辨識。
    let email: String?
    /// nil 代表實例有登入但手上的 token 已過期（通常是實例很久沒開）。
    let credential: Data?

    /// 同一個人在帳號清單與「使用者移除過」清單裡的識別字串。
    var identityKey: String? {
        Self.identityKey(platform: platform, accountUUID: accountUUID, email: email)
    }

    static func identityKey(platform: PlatformKind, accountUUID: String?, email: String?) -> String? {
        switch platform {
        case .claude:
            accountUUID.map { "\(platform.rawValue):\($0.lowercased())" }
        case .codex:
            email.map { "\(platform.rawValue):\($0.lowercased())" }
        case .antigravity:
            nil
        }
    }
}
