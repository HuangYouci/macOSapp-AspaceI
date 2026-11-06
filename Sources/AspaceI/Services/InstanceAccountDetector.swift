import Foundation

/// 掃描各實例的資料夾，找出它們目前登入的帳號。
/// 讀 Claude 時可能跳鑰匙圈授權視窗並阻塞到使用者回應，不可在主執行緒呼叫。
struct InstanceAccountDetector: Sendable {
    struct Result: Sendable {
        var accounts: [DetectedInstanceAccount]
        var errors: [String]
    }

    private let claude: ClaudeDesktopCredentialService

    init(claude: ClaudeDesktopCredentialService = .shared) {
        self.claude = claude
    }

    func allowRetry() {
        claude.allowRetry()
    }

    func detect(_ sources: [InstanceCredentialSource], now: Date = .now) -> Result {
        var accounts: [DetectedInstanceAccount] = []
        var errors: [String] = []
        for source in sources {
            do {
                if let item = try detect(source, now: now) { accounts.append(item) }
            } catch {
                let message = error.localizedDescription
                if !errors.contains(message) { errors.append(message) }
            }
        }
        return Result(accounts: Self.merging(accounts), errors: errors)
    }

    private func detect(_ source: InstanceCredentialSource, now: Date) throws -> DetectedInstanceAccount? {
        switch source.platform {
        case .claude:
            guard let signIn = try claude.signIn(inDataDirectory: source.directory, now: now) else { return nil }
            return DetectedInstanceAccount(
                platform: .claude,
                instanceName: source.instanceName,
                accountUUID: signIn.accountUUID,
                email: nil,
                credential: try signIn.token.map(ClaudeDesktopCredentialService.credentialData(for:))
            )
        case .codex:
            let url = source.directory.appending(path: "auth.json")
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            let data = try Data(contentsOf: url)
            guard let email = AccountManager.credentialEmail(data, platform: .codex) else { return nil }
            return DetectedInstanceAccount(platform: .codex, instanceName: source.instanceName, accountUUID: nil, email: email, credential: data)
        case .antigravity:
            // Antigravity 2.0 起登入放在系統鑰匙圈的同一個位置，整台 Mac 只有一份，由本機匯入處理。
            return nil
        }
    }

    /// 同一個帳號登入在好幾個實例時只留一筆，優先留有可用 token 的那個。
    static func merging(_ items: [DetectedInstanceAccount]) -> [DetectedInstanceAccount] {
        var result: [DetectedInstanceAccount] = []
        for item in items {
            guard let key = item.identityKey else { continue }
            if let index = result.firstIndex(where: { $0.identityKey == key }) {
                if result[index].credential == nil, item.credential != nil { result[index] = item }
            } else {
                result.append(item)
            }
        }
        return result
    }
}
