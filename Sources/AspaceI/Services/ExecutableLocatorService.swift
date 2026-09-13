import AppKit

final class ExecutableLocatorService: Sendable {
    static let shared = ExecutableLocatorService()
    private init() {}

    /// 找到各服務桌面 App 的 bundle 路徑；實例一律以 App 形式啟動。
    /// 先依 bundle identifier 向系統查（App 可能改名，例如 Codex 現在叫 ChatGPT.app），找不到再比對常見檔名。
    func locate(
        _ platform: PlatformKind,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        bundleLookup: (String) -> String? = { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)?.path },
        exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> String? {
        for identifier in Self.bundleIdentifiers(for: platform) {
            if let path = bundleLookup(identifier), exists(path) { return path }
        }
        return Self.candidatePaths(for: platform, homeDirectory: homeDirectory).first(where: exists)
    }

    static func bundleIdentifiers(for platform: PlatformKind) -> [String] {
        switch platform {
        case .githubCopilot: ["com.microsoft.VSCode", "com.microsoft.VSCodeInsiders"]
        case .antigravity: ["com.google.antigravity", "com.google.antigravity-ide"]
        case .claude: ["com.anthropic.claudefordesktop"]
        case .codex: ["com.openai.codex"]
        }
    }

    static func candidatePaths(for platform: PlatformKind, homeDirectory: URL) -> [String] {
        let names: [String] = switch platform {
        case .githubCopilot: ["Visual Studio Code.app", "Visual Studio Code - Insiders.app"]
        case .antigravity: ["Antigravity.app", "Antigravity IDE.app"]
        case .claude: ["Claude.app"]
        case .codex: ["ChatGPT.app", "Codex.app"]
        }
        return names.flatMap { ["/Applications/\($0)", "\(homeDirectory.path)/Applications/\($0)"] }
    }
}
