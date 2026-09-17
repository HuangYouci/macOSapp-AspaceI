import Foundation
import Security

/// Antigravity 2.0 起把登入放在 macOS 登入 Keychain（service `gemini`、account `antigravity`），
/// 內容是 go-keyring 的 `go-keyring-base64:<base64(JSON)>` 包裝；`~/.gemini/jetski-standalone-oauth-token`
/// 只是附帶產物，官方 App 不從那裡讀登入身分。切換帳號沒寫這個項目就不會生效。
/// 判定與封裝形狀比對自 jlcodes99/cockpit-tools `antigravity_credential.rs`。
final class AntigravitySystemCredentialService: Sendable {
    static let shared = AntigravitySystemCredentialService()
    private init() {}

    static let service = "gemini"
    static let account = "antigravity"
    private static let prefix = "go-keyring-base64:"

    /// 讀官方 App 目前使用的登入。這個項目由官方 App 以「允許所有程式」建立，讀取不會跳授權視窗。
    func load() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let raw = result as? Data else { return nil }
        return Self.decode(raw)
    }

    /// 寫回官方 App 讀的位置。必須走 `security -A`：以 SecItemAdd 建立的項目只有 AspaceI 自己能讀，
    /// 官方 App 會被 Keychain 拒絕而當成沒登入。先刪再加是為了換掉既有項目的存取控制。
    func save(_ credential: Data) throws {
        let payload = Self.prefix + Self.canonical(credential).base64EncodedString()
        _ = try? run(["delete-generic-password", "-s", Self.service, "-a", Self.account], input: nil)
        // `-w` 不帶值時改從 stdin 讀（要輸入兩次），避免憑證出現在行程的參數列裡。
        let result = try run(
            ["add-generic-password", "-s", Self.service, "-a", Self.account, "-A", "-w"],
            input: "\(payload)\n\(payload)\n"
        )
        guard result.status == 0 else {
            throw CredentialProjectionError.systemCredentialWriteFailed(result.error)
        }
    }

    /// go-keyring 會把內容包成 base64；官方 App 也可能直接存 JSON，兩種都接。
    static func decode(_ raw: Data) -> Data? {
        guard let text = String(data: raw, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return raw.isEmpty ? nil : raw
        }
        guard text.hasPrefix(prefix) else {
            return Data(text.utf8)
        }
        return Data(base64Encoded: String(text.dropFirst(prefix.count)))
    }

    /// 官方檔案與 Keychain 用的是同一個形狀，共用 `antigravityTokenFile` 的正規化結果。
    static func canonical(_ credential: Data) -> Data {
        (try? CredentialProjectionService.antigravityTokenFile(from: credential)) ?? credential
    }

    private func run(_ arguments: [String], input: String?) throws -> (status: Int32, error: String) {
        let process = Process()
        let errorPipe = Pipe()
        let inputPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = arguments
        process.standardInput = input == nil ? FileHandle.nullDevice : inputPipe
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errorPipe
        try process.run()
        if let input {
            inputPipe.fileHandleForWriting.write(Data(input.utf8))
            try? inputPipe.fileHandleForWriting.close()
        }
        let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (process.terminationStatus, message)
    }
}
