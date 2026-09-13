import Foundation

struct LocalAccountCandidate: Equatable, Sendable {
    let platform: PlatformKind
    let sourceDescription: String
}

final class LocalAccountDiscoveryService: Sendable {
    static let shared = LocalAccountDiscoveryService()

    private init() {}

    /// 只檢查登入儲存是否存在，不讀取憑證內容。
    func discover(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> [LocalAccountCandidate] {
        let applicationSupport = homeDirectory
            .appending(path: "Library/Application Support", directoryHint: .isDirectory)
        let candidates: [(PlatformKind, URL)] = [
            (.codex, homeDirectory.appending(path: ".codex/auth.json")),
            (.claude, homeDirectory.appending(path: ".claude/.credentials.json")),
            (.antigravity, applicationSupport.appending(path: "Antigravity/User/globalStorage/state.vscdb")),
            (.githubCopilot, homeDirectory.appending(path: ".config/gh/hosts.yml"))
        ]

        return candidates.compactMap { platform, url in
            guard FileManager.default.fileExists(atPath: url.path) else {
                return nil
            }
            return LocalAccountCandidate(
                platform: platform,
                sourceDescription: url.lastPathComponent
            )
        }
    }
}
