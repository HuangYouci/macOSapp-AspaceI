import CommonCrypto
import Foundation
import Security

/// 讀 Claude 桌面 App（預設與 AspaceI 實例）已經拿到的 OAuth access token，只拿來查額度。
///
/// 同一個帳號在桌面 App 與 AspaceI 各自登入時，伺服器會在幾小時後作廢其中一份的 refresh token，
/// 所以 AspaceI 不自己保管這種帳號的登入，也絕不使用快取裡的 refresh token（換新交給桌面 App）。
/// 快取以 Electron safeStorage 加密：所有複本的 App 名稱都是 Claude，共用鑰匙圈的「Claude Safe Storage」。
final class ClaudeDesktopCredentialService: @unchecked Sendable {
    struct Token: Equatable, Sendable {
        let accountUUID: String
        let accessToken: String
        let expiresAt: Date
    }

    /// 實例資料夾讀到的結果：登入了哪個帳號，以及有沒有可用的 token。
    struct SignIn: Equatable, Sendable {
        let accountUUID: String
        let token: Token?
    }

    static let shared = ClaudeDesktopCredentialService()
    static let cacheFields = ["oauth:tokenCacheV2", "oauth:tokenCache"]

    private let lock = NSLock()
    private var cachedKey: Data?
    private var keyFailure: ClaudeDesktopCredentialError?
    private let readPassword: @Sendable () throws -> String

    /// `readPassword` 必須可抽換：預設會讀系統鑰匙圈並跳授權視窗，測試不能碰。
    init(readPassword: @escaping @Sendable () throws -> String = ClaudeDesktopCredentialService.readSafeStoragePassword) {
        self.readPassword = readPassword
    }

    /// 讀不到 config.json（實例從沒開過）或沒登入時回傳 nil。會阻塞到使用者回應鑰匙圈視窗，不可在主執行緒呼叫。
    func signIn(inDataDirectory directory: URL, now: Date = .now) throws -> SignIn? {
        let url = directory.appending(path: "config.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        guard let accountUUID = InstanceService.parseClaudeSignedInAccountUUID(data),
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let key = try safeStorageKey()
        var best: Token?
        for field in Self.cacheFields {
            guard let blob = root[field] as? String, !blob.isEmpty else { continue }
            let cache = try Self.decryptCache(blob, key: key)
            if let token = Self.selectToken(fromCache: cache, accountUUID: accountUUID, now: now),
               token.expiresAt > (best?.expiresAt ?? .distantPast) {
                best = token
            }
        }
        return SignIn(accountUUID: accountUUID, token: best)
    }

    /// 給 `QuotaService` 的憑證形狀；只有 access token，換不了新。
    static func credentialData(for token: Token) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["accessToken": token.accessToken], options: [.sortedKeys])
    }

    // MARK: 鑰匙

    /// 使用者按「更新」時再問一次：電腦閒置時視窗會被系統直接取消，不一定是使用者拒絕。
    func allowRetry() {
        lock.withLock { keyFailure = nil }
    }

    /// 使用者拒絕過就不在這次執行期間自動重問，否則每五分鐘跳一次視窗。
    private func safeStorageKey() throws -> Data {
        try lock.withLock {
            if let cachedKey { return cachedKey }
            if let keyFailure { throw keyFailure }
            do {
                let key = try Self.deriveKey(password: readPassword())
                cachedKey = key
                return key
            } catch let error as ClaudeDesktopCredentialError {
                keyFailure = error
                throw error
            }
        }
    }

    static func readSafeStoragePassword() throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Safe Storage",
            kSecAttrAccount as String: "Claude Key",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { throw ClaudeDesktopCredentialError.keyUnavailable(status) }
        guard let data = result as? Data, let password = String(data: data, encoding: .utf8), !password.isEmpty else {
            throw ClaudeDesktopCredentialError.keyUnavailable(status)
        }
        return password
    }

    /// Electron safeStorage（macOS）：PBKDF2-SHA1、salt `saltysalt`、1003 次、16 bytes。
    static func deriveKey(password: String) throws -> Data {
        let salt = Array("saltysalt".utf8)
        var key = [UInt8](repeating: 0, count: kCCKeySizeAES128)
        let passwordBytes = Array(password.utf8)
        let status = passwordBytes.withUnsafeBufferPointer { passwordPointer in
            passwordPointer.baseAddress.map { base in
                base.withMemoryRebound(to: Int8.self, capacity: passwordBytes.count) { password in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2), password, passwordBytes.count,
                        salt, salt.count, CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1), 1003,
                        &key, key.count
                    )
                }
            } ?? Int32(kCCParamError)
        }
        guard status == kCCSuccess else { throw ClaudeDesktopCredentialError.decryptFailed }
        return Data(key)
    }

    // MARK: 解密與挑選

    /// 內容是 base64(`v10` + AES-128-CBC)，IV 為 16 個空白。
    static func decryptCache(_ blob: String, key: Data) throws -> [String: Any] {
        guard let raw = Data(base64Encoded: blob), raw.count > 3, raw.prefix(3) == Data("v10".utf8) else {
            throw ClaudeDesktopCredentialError.unsupportedFormat
        }
        let plain = try aesCBC(operation: CCOperation(kCCDecrypt), input: raw.dropFirst(3), key: key)
        guard let object = try JSONSerialization.jsonObject(with: plain) as? [String: Any] else {
            throw ClaudeDesktopCredentialError.unsupportedFormat
        }
        return object
    }

    static func aesCBC(operation: CCOperation, input: Data, key: Data) throws -> Data {
        let iv = [UInt8](repeating: 0x20, count: kCCBlockSizeAES128)
        var output = [UInt8](repeating: 0, count: input.count + kCCBlockSizeAES128)
        var written = 0
        let outputCapacity = output.count
        let status = key.withUnsafeBytes { keyBytes in
            input.withUnsafeBytes { inputBytes in
                CCCrypt(
                    operation, CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
                    keyBytes.baseAddress, key.count, iv,
                    inputBytes.baseAddress, input.count,
                    &output, outputCapacity, &written
                )
            }
        }
        guard status == kCCSuccess else { throw ClaudeDesktopCredentialError.decryptFailed }
        return Data(output.prefix(written))
    }

    /// 快取的 key 形如 `acct:<uuid>|<client id>:<org id>:https://api.anthropic.com:<scopes>`。
    /// 額度端點要 `user:profile`；同帳號有多筆時取最晚到期的。
    static func selectToken(fromCache cache: [String: Any], accountUUID: String, now: Date) -> Token? {
        let wanted = accountUUID.lowercased()
        return cache.compactMap { key, value -> Token? in
            guard let parsed = parseCacheKey(key), parsed.accountUUID == wanted, parsed.scopes.contains("user:profile"),
                  let entry = value as? [String: Any],
                  let accessToken = entry["token"] as? String, !accessToken.isEmpty,
                  let expiresAt = (entry["expiresAt"] as? NSNumber)?.doubleValue else { return nil }
            let date = Date(timeIntervalSince1970: expiresAt / 1000)
            guard date > now.addingTimeInterval(60) else { return nil }
            return Token(accountUUID: wanted, accessToken: accessToken, expiresAt: date)
        }
        .max { $0.expiresAt < $1.expiresAt }
    }

    static func parseCacheKey(_ key: String) -> (accountUUID: String, scopes: Set<String>)? {
        let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2, parts[0].hasPrefix("acct:") else { return nil }
        let accountUUID = String(parts[0].dropFirst("acct:".count)).lowercased()
        guard UUID(uuidString: accountUUID) != nil,
              let scheme = parts[1].range(of: "://"),
              let scopeStart = parts[1][scheme.upperBound...].firstIndex(of: ":") else { return nil }
        let scopes = parts[1][parts[1].index(after: scopeStart)...].split(separator: " ").map(String.init)
        return (accountUUID, Set(scopes))
    }
}

enum ClaudeDesktopCredentialError: LocalizedError, Equatable {
    case keyUnavailable(OSStatus), unsupportedFormat, decryptFailed

    var errorDescription: String? {
        switch self {
        case .keyUnavailable(let status):
            String(localized: "ClaudeDesktopKeyUnavailable", defaultValue: "無法讀取 Claude 桌面版的登入（狀態碼：\(status)）")
        case .unsupportedFormat:
            String(localized: "ClaudeDesktopUnsupportedFormat", defaultValue: "Claude 桌面版的登入格式無法識別")
        case .decryptFailed:
            String(localized: "ClaudeDesktopDecryptFailed", defaultValue: "無法解開 Claude 桌面版的登入")
        }
    }
}
