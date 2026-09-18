import Foundation

final class AccountStore: Sendable {
    static let shared = AccountStore()

    private init() {}

    func load() throws -> [Account] {
        let fileURL = try accountsFileURL()
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode([Account].self, from: data)
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
