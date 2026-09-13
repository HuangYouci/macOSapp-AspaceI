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
            (.antigravity, support.appending(path: "Antigravity/User/globalStorage/state.vscdb"))
        ]
        return sources.compactMap { platform, url in
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            if platform == .antigravity {
                return ImportedCredential(platform: platform, displayName: platform.displayName, sourcePath: url.path, data: nil)
            }
            guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
            return ImportedCredential(platform: platform, displayName: platform.displayName, sourcePath: url.path, data: data)
        }
    }
}
