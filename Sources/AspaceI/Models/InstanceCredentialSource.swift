import Foundation

/// 一個實例存放登入的資料夾：Claude 是桌面 App 的 user data（內含 config.json），Codex 是 `CODEX_HOME`（內含 auth.json）。
struct InstanceCredentialSource: Equatable, Sendable {
    let platform: PlatformKind
    let instanceName: String
    let directory: URL
}
