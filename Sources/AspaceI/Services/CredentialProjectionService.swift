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

    func projectToDefaultClient(account: Account, credentialData: Data?, homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) throws {
        let support = homeDirectory.appending(path: "Library/Application Support", directoryHint: .isDirectory)
        let profile: URL
        switch account.platform {
        case .codex: profile = homeDirectory.appending(path: ".codex", directoryHint: .isDirectory)
        case .claude: profile = homeDirectory.appending(path: ".claude", directoryHint: .isDirectory)
        case .githubCopilot: throw CredentialProjectionError.githubUsesInstanceToken
        case .antigravity: profile = support.appending(path: "Antigravity IDE", directoryHint: .isDirectory)
        }
        try project(account: account, credentialData: credentialData, to: profile)
    }

    private func write(_ data: Data?, to url: URL) throws {
        guard let data, !data.isEmpty else { throw CredentialProjectionError.credentialMissing }
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

enum CredentialProjectionError: LocalizedError {
    case credentialMissing, sourceMissing, antigravityProfileRequired, githubUsesInstanceToken
    var errorDescription: String? {
        switch self {
        case .credentialMissing: "Keychain 中找不到此帳號的憑證"
        case .sourceMissing: "原始登入資料已不存在"
        case .antigravityProfileRequired: "Antigravity Instance 需綁定 state.vscdb 帳號快照"
        case .githubUsesInstanceToken: "GitHub 帳號切換請透過綁定 Instance 使用，避免覆蓋系統 Keychain"
        }
    }
}
