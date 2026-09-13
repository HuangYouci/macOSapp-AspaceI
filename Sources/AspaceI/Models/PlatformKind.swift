import Foundation

enum PlatformKind: String, Codable, CaseIterable, Identifiable, Sendable {
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
            String(localized: "PlatformGitHubCopilot", defaultValue: "GitHub Copilot")
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
