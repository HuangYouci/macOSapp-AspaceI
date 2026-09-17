import Foundation

enum PlatformKind: String, Codable, CodingKeyRepresentable, CaseIterable, Identifiable, Sendable {
    case antigravity
    case codex
    case claude
    case githubCopilot

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .antigravity:
            String(localized: "PlatformAntigravity", defaultValue: "Antigravity")
        case .codex:
            String(localized: "PlatformCodex", defaultValue: "Codex")
        case .claude:
            String(localized: "PlatformClaude", defaultValue: "Claude")
        case .githubCopilot:
            String(localized: "PlatformGitHub", defaultValue: "GitHub")
        }
    }

    /// 實例分組使用的桌面 App 名稱。
    var clientName: String {
        switch self {
        case .githubCopilot: "VS Code"
        case .antigravity: "Antigravity"
        case .claude: "Claude"
        case .codex: "Codex"
        }
    }

    /// 能否把帳號寫進官方 App 的預設位置（切換預設實例的帳號）。
    var supportsDefaultSwitch: Bool {
        switch self {
        case .codex, .antigravity: true
        case .claude, .githubCopilot: false
        }
    }

    /// 實例綁定帳號時，AspaceI 能否把憑證放進該 App 讀得到的位置。
    func supportsAccountBinding(isDefault: Bool) -> Bool {
        switch self {
        case .codex: !isDefault
        case .antigravity, .claude, .githubCopilot: false
        }
    }

    /// 除了檔案，官方客戶端也可能只把登入資料放在 Keychain。
    var hasKeychainLocalSource: Bool {
        switch self {
        case .codex, .claude, .githubCopilot, .antigravity: true
        }
    }

    var pastePlaceholder: String {
        switch self {
        case .codex: "auth.json 內容"
        case .claude: ".credentials.json 內容或 sk-ant-oat token"
        case .antigravity: "token 檔內容或 1// refresh token"
        case .githubCopilot: "gh auth token 輸出（gho_…）"
        }
    }

    var symbolName: String {
        switch self {
        case .antigravity: "sparkles"
        case .codex: "chevron.left.forwardslash.chevron.right"
        case .claude: "brain.head.profile"
        case .githubCopilot: "chevron.left.forwardslash.chevron.right"
        }
    }
}
