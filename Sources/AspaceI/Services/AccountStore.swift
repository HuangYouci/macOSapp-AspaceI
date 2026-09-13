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
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
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
