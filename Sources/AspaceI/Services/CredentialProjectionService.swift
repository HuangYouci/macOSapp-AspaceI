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
            let directory = profileDirectory.appending(path: ".config/gh", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try write(credentialData, to: directory.appending(path: "hosts.yml"))
        case .antigravity:
            guard let sourcePath = account.sourcePath, FileManager.default.fileExists(atPath: sourcePath) else { throw CredentialProjectionError.sourceMissing }
            let directory = profileDirectory.appending(path: "User/globalStorage", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let target = directory.appending(path: "state.vscdb")
            if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
            try FileManager.default.copyItem(at: URL(fileURLWithPath: sourcePath), to: target)
        }
    }

    private func write(_ data: Data?, to url: URL) throws {
        guard let data, !data.isEmpty else { throw CredentialProjectionError.credentialMissing }
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

enum CredentialProjectionError: LocalizedError {
    case credentialMissing, sourceMissing
    var errorDescription: String? {
        switch self {
        case .credentialMissing: "Keychain 中找不到此帳號的憑證"
        case .sourceMissing: "原始登入資料已不存在"
        }
    }
}
