import SwiftUI

extension PlatformKind {
    var initials: String {
        switch self {
        case .antigravity: "AG"
        case .codex: "CX"
        case .claude: "CL"
        case .githubCopilot: "GH"
        }
    }

    var tint: Color {
        switch self {
        case .antigravity: .blue
        case .codex: .primary
        case .claude: .orange
        case .githubCopilot: .purple
        }
    }
}
