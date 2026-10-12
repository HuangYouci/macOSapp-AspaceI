import Foundation

final class AccountStore: Sendable {
    static let shared = AccountStore()

    private init() {}

    struct Loaded: Equatable {
        var accounts: [Account] = []
        /// 已不支援的平台留下的帳號，它們在 Keychain 裡的憑證位置，交給呼叫端刪掉。
        var retiredCredentialReferences: [String] = []
    }

    func load() throws -> Loaded {
        let fileURL = try accountsFileURL()
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return Loaded()
        }
        return try Self.decode(Data(contentsOf: fileURL))
    }

    /// 2026-10-12 移除 GitHub Copilot：舊檔裡這類帳號解不出 `PlatformKind`，整份清單會因此讀不出來。
    /// 改為逐筆讀，平台不認得的只取出憑證位置。
    static func decode(_ data: Data) throws -> Loaded {
        var loaded = Loaded()
        for entry in try JSONDecoder().decode([StoredEntry].self, from: data) {
            switch entry {
            case .account(let account): loaded.accounts.append(account)
            case .retired(let reference): if let reference { loaded.retiredCredentialReferences.append(reference) }
            }
        }
        return loaded
    }

    private enum StoredEntry: Decodable {
        case account(Account)
        case retired(credentialReference: String?)

        private enum CodingKeys: String, CodingKey { case platform, credentialReference }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if PlatformKind(rawValue: try container.decode(String.self, forKey: .platform)) == nil {
                self = .retired(credentialReference: try container.decodeIfPresent(String.self, forKey: .credentialReference))
            } else {
                self = .account(try Account(from: decoder))
            }
        }
    }

    func save(_ accounts: [Account]) throws {
        let fileURL = try accountsFileURL()
        let data = try JSONEncoder().encode(accounts)
        // `.completeFileProtection` 是 iOS 的資料保護等級，macOS 上不生效（檔案仍是 0644），
        // 而且會讓 atomic 寫入在設定屬性那一步回報權限錯誤。權限直接自己設。
        try data.write(to: fileURL, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    private func accountsFileURL() throws -> URL {
        let baseURL = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = baseURL.appending(path: "AspaceI", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        return directory.appending(path: "accounts.json")
    }
}
