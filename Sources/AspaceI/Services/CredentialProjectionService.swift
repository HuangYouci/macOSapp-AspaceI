import Foundation

final class CredentialProjectionService: Sendable {
    static let shared = CredentialProjectionService()
    private init() {}

    func project(account: Account, credentialData: Data?, to profileDirectory: URL) throws {
        try FileManager.default.createDirectory(at: profileDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        switch account.platform {
        case .codex:
            try write(credentialData, to: profileDirectory.appending(path: "auth.json"))
        case .claude:
            try write(credentialData, to: profileDirectory.appending(path: ".credentials.json"))
        case .githubCopilot:
            return
        case .antigravity:
            guard let sourcePath = account.sourcePath, FileManager.default.fileExists(atPath: sourcePath) else { throw CredentialProjectionError.sourceMissing }
            guard URL(fileURLWithPath: sourcePath).pathExtension.lowercased() == "vscdb" else { throw CredentialProjectionError.antigravityProfileRequired }
            let directory = profileDirectory.appending(path: "User/globalStorage", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let target = directory.appending(path: "state.vscdb")
            if URL(fileURLWithPath: sourcePath).standardizedFileURL == target.standardizedFileURL { return }
            if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
            try FileManager.default.copyItem(at: URL(fileURLWithPath: sourcePath), to: target)
        }
    }

    /// 把帳號寫進官方 App 預設讀取的位置，讓「切換」後重開的官方 App 用這個帳號。
    func projectToDefaultClient(account: Account, credentialData: Data?, homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) throws {
        guard let credentialData else { throw CredentialProjectionError.credentialMissing }
        switch account.platform {
        case .codex:
            guard Self.isCompleteCodexAuth(credentialData) else { throw CredentialProjectionError.incompleteCredential }
            let directory = homeDirectory.appending(path: ".codex", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try write(credentialData, to: directory.appending(path: "auth.json"))
        case .antigravity:
            let directory = homeDirectory.appending(path: ".gemini", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try write(try Self.antigravityTokenFile(from: credentialData), to: directory.appending(path: "jetski-standalone-oauth-token"))
        case .claude, .githubCopilot:
            throw CredentialProjectionError.switchUnsupported
        }
    }

    static func isCompleteCodexAuth(_ data: Data) -> Bool {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = root["tokens"] as? [String: Any] else { return false }
        return tokens["access_token"] is String && tokens["refresh_token"] is String
    }

    /// 轉成 Antigravity 官方 token 檔的形狀；只有 refresh token 時給一個已過期的 access token，讓官方 App 自己換新。
    static func antigravityTokenFile(from data: Data) throws -> Data {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw CredentialProjectionError.incompleteCredential }
        let token = root["token"] as? [String: Any] ?? root
        guard let refreshToken = token["refresh_token"] as? String ?? token["refreshToken"] as? String, !refreshToken.isEmpty else {
            throw CredentialProjectionError.incompleteCredential
        }
        let object: [String: Any] = [
            "auth_method": root["auth_method"] as? String ?? "consumer",
            "token": [
                "access_token": token["access_token"] as? String ?? "",
                "refresh_token": refreshToken,
                "token_type": token["token_type"] as? String ?? "Bearer",
                "expiry": token["expiry"] as? String ?? "1970-01-01T00:00:00Z"
            ]
        ]
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private func write(_ data: Data?, to url: URL) throws {
        guard let data, !data.isEmpty else { throw CredentialProjectionError.credentialMissing }
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

enum CredentialProjectionError: LocalizedError {
    case credentialMissing, sourceMissing, antigravityProfileRequired, incompleteCredential, switchUnsupported
    var errorDescription: String? {
        switch self {
        case .credentialMissing: "Keychain 中找不到此帳號的憑證"
        case .sourceMissing: "原始登入資料已不存在"
        case .antigravityProfileRequired: "Antigravity Instance 需綁定 state.vscdb 帳號快照"
        case .incompleteCredential: "此帳號沒有完整的登入資料（缺 refresh token），請改用瀏覽器登入後再切換"
        case .switchUnsupported: "此服務的 App 不支援由 AspaceI 切換帳號"
        }
    }
}
