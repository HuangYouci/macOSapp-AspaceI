import Foundation
import Security

/// 所有帳號憑證集中存成單一 Keychain 項目並快取在記憶體。
/// macOS 每讀一個項目都可能跳授權視窗，分散存放時帳號越多、跳越多次。
final class KeychainService: @unchecked Sendable {
    static let shared = KeychainService()

    private let service = "com.huangyouci.AspaceI"
    private let vaultAccount = "credentials-vault"
    private let legacyServices = ["com.huangyouci.AspaceI", "app.aspacei.credentials"]
    private let lock = NSLock()
    private var cache: [String: Data]?

    private init() {}

    func save(_ data: Data, account: String) throws {
        try lock.withLock {
            var vault = try loadVault()
            vault[account] = data
            try writeVault(vault)
        }
    }

    func load(account: String) throws -> Data? {
        try lock.withLock {
            var vault = try loadVault()
            if let data = vault[account] { return data }
            guard let legacy = try takeLegacyItem(account: account) else { return nil }
            vault[account] = legacy
            try writeVault(vault)
            return legacy
        }
    }

    func delete(account: String) throws {
        try lock.withLock {
            var vault = try loadVault()
            guard vault.removeValue(forKey: account) != nil else { return }
            try writeVault(vault)
        }
    }

    // MARK: Vault

    private func loadVault() throws -> [String: Data] {
        if let cache { return cache }
        var result: CFTypeRef?
        let status = SecItemCopyMatching(vaultQuery(returningData: true) as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { throw KeychainError.unhandledStatus(status) }
            let decoded = try JSONDecoder().decode([String: Data].self, from: data)
            cache = decoded
            return decoded
        case errSecItemNotFound:
            cache = [:]
            return [:]
        default:
            throw KeychainError.unhandledStatus(status)
        }
    }

    private func writeVault(_ vault: [String: Data]) throws {
        let data = try JSONEncoder().encode(vault)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        var status = SecItemUpdate(vaultQuery(returningData: false) as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insertion = vaultQuery(returningData: false)
            attributes.forEach { insertion[$0.key] = $0.value }
            status = SecItemAdd(insertion as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainError.unhandledStatus(status) }
        cache = vault
    }

    private func vaultQuery(returningData: Bool) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: vaultAccount
        ]
        if returningData {
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
        }
        return query
    }

    /// 舊版每個帳號一個項目；讀到後併入 vault 並刪除舊項目，只會發生一次。
    private func takeLegacyItem(account: String) throws -> Data? {
        for legacyService in legacyServices {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: legacyService,
                kSecAttrAccount as String: account,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne
            ]
            var result: CFTypeRef?
            guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { continue }
            let deletion: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: legacyService,
                kSecAttrAccount as String: account
            ]
            let status = SecItemDelete(deletion as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError.unhandledStatus(status) }
            return data
        }
        return nil
    }
}

enum KeychainError: LocalizedError {
    case unhandledStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unhandledStatus(let status):
            String(localized: "KeychainError", defaultValue: "無法存取 Keychain（狀態碼：\(status)）")
        }
    }
}
