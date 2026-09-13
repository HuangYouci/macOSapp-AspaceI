import Foundation

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
        let sources: [(PlatformKind, URL)] = [
            (.codex, homeDirectory.appending(path: ".codex/auth.json")),
            (.claude, homeDirectory.appending(path: ".claude/.credentials.json")),
            (.githubCopilot, homeDirectory.appending(path: ".config/gh/hosts.yml")),
            (.antigravity, support.appending(path: "Antigravity IDE/User/globalStorage/state.vscdb"))
        ]
        return sources.compactMap { platform, url in
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            if platform == .antigravity {
                return ImportedCredential(platform: platform, displayName: platform.displayName, sourcePath: url.path, data: nil)
            }
            if platform == .githubCopilot, let data = githubCredentialFromCLI() {
                return ImportedCredential(platform: platform, displayName: platform.displayName, sourcePath: url.path, data: data)
            }
            let data: Data
            do {
                data = try Data(contentsOf: url)
            } catch {
                return nil
            }
            guard !data.isEmpty else { return nil }
            return ImportedCredential(platform: platform, displayName: platform.displayName, sourcePath: url.path, data: data)
        }
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
