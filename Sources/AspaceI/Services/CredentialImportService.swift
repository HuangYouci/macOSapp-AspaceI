import CryptoKit
import Foundation
import Security

struct ImportedCredential: Sendable {
    let platform: PlatformKind
    let displayName: String
    let sourcePath: String
    let data: Data?
}

final class CredentialImportService: Sendable {
    static let shared = CredentialImportService()
    private init() {}

    func importAvailable(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> [ImportedCredential] {
        let support = homeDirectory.appending(path: "Library/Application Support", directoryHint: .isDirectory)
        let codexHome = homeDirectory.appending(path: ".codex", directoryHint: .isDirectory)
        let claudeHome = homeDirectory.appending(path: ".claude", directoryHint: .isDirectory)
        let antigravityDatabase = support.appending(path: "Antigravity IDE/User/globalStorage/state.vscdb")
        return [
            importedCodex(from: codexHome),
            importedClaude(from: claudeHome),
            importedGitHub(homeDirectory: homeDirectory),
            importedAntigravity(from: antigravityDatabase)
        ].compactMap { $0 }
    }

    func importText(_ value: String, platform: PlatformKind, displayName: String) throws -> ImportedCredential {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CredentialImportError.emptyFile }
        let data: Data
        if let rawData = trimmed.data(using: .utf8),
           (try? JSONSerialization.jsonObject(with: rawData)) != nil {
            data = rawData
        } else {
            let key: String
            switch platform {
            case .claude: key = "accessToken"
            case .antigravity, .codex, .githubCopilot: key = "access_token"
            }
            data = try JSONSerialization.data(withJSONObject: [key: trimmed])
        }
        return ImportedCredential(
            platform: platform,
            displayName: displayName,
            sourcePath: "手動加入",
            data: data
        )
    }

    private func importedCodex(from directory: URL) -> ImportedCredential? {
        let file = directory.appending(path: "auth.json")
        if let data = nonemptyData(at: file) {
            return ImportedCredential(platform: .codex, displayName: PlatformKind.codex.displayName, sourcePath: file.path, data: data)
        }
        let canonicalPath = directory.resolvingSymlinksInPath().path
        let digest = SHA256.hash(data: Data(canonicalPath.utf8)).map { String(format: "%02x", $0) }.joined()
        let account = "cli|\(digest.prefix(16))"
        guard let data = externalKeychainData(service: "Codex Auth", account: account) else { return nil }
        return ImportedCredential(platform: .codex, displayName: PlatformKind.codex.displayName, sourcePath: "macOS Keychain", data: data)
    }

    private func importedClaude(from directory: URL) -> ImportedCredential? {
        if let data = externalKeychainData(service: "Claude Code-credentials", account: NSUserName()) {
            return ImportedCredential(platform: .claude, displayName: PlatformKind.claude.displayName, sourcePath: "macOS Keychain", data: data)
        }
        let file = directory.appending(path: ".credentials.json")
        guard let data = nonemptyData(at: file) else { return nil }
        return ImportedCredential(platform: .claude, displayName: PlatformKind.claude.displayName, sourcePath: file.path, data: data)
    }

    private func importedGitHub(homeDirectory: URL) -> ImportedCredential? {
        let file = homeDirectory.appending(path: ".config/gh/hosts.yml")
        if let data = githubCredentialFromCLI() {
            return ImportedCredential(platform: .githubCopilot, displayName: PlatformKind.githubCopilot.displayName, sourcePath: "GitHub CLI", data: data)
        }
        guard let data = nonemptyData(at: file) else { return nil }
        return ImportedCredential(platform: .githubCopilot, displayName: PlatformKind.githubCopilot.displayName, sourcePath: file.path, data: data)
    }

    private func importedAntigravity(from database: URL) -> ImportedCredential? {
        guard FileManager.default.fileExists(atPath: database.path) else { return nil }
        guard let value = sqliteValue(
            database: database,
            key: "antigravityUnifiedStateSync.oauthToken"
        ), let topic = Data(base64Encoded: value),
              let refreshToken = ProtobufRefreshTokenExtractor.extract(from: topic),
              let data = try? JSONSerialization.data(withJSONObject: ["refresh_token": refreshToken]) else {
            return ImportedCredential(platform: .antigravity, displayName: PlatformKind.antigravity.displayName, sourcePath: database.path, data: nil)
        }
        return ImportedCredential(platform: .antigravity, displayName: PlatformKind.antigravity.displayName, sourcePath: database.path, data: data)
    }

    private func nonemptyData(at url: URL) -> Data? {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
        return data
    }

    private func externalKeychainData(service: String, account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    private func sqliteValue(database: URL, key: String) -> String? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = ["-readonly", database.path, "SELECT value FROM ItemTable WHERE key = '\(key)';"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let value = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    func importFile(at url: URL, platform: PlatformKind) throws -> ImportedCredential {
        let isAntigravityDatabase = platform == .antigravity && url.pathExtension.lowercased() == "vscdb"
        let data: Data? = isAntigravityDatabase ? nil : try Data(contentsOf: url)
        if !isAntigravityDatabase, data?.isEmpty != false { throw CredentialImportError.emptyFile }
        let fileName = url.deletingPathExtension().lastPathComponent
        return ImportedCredential(platform: platform, displayName: fileName.isEmpty ? platform.displayName : fileName, sourcePath: url.path, data: data)
    }

    private func githubCredentialFromCLI() -> Data? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["gh", "auth", "token", "--hostname", "github.com"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        let token = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return nil }
        do {
            return try JSONSerialization.data(withJSONObject: ["access_token": token])
        } catch {
            return nil
        }
    }
}

enum CredentialImportError: LocalizedError {
    case emptyFile
    var errorDescription: String? { "選擇的憑證檔案是空的" }
}
