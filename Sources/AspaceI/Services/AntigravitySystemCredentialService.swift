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

    /// 讀官方 App 目前使用的登入。
    ///
    /// `allowPrompt` 必須由呼叫端決定。AspaceI 自己寫入時用的是「允許所有程式」，但官方 App
    /// 每次自己換 token 都會把項目重寫成只信任它自己，AspaceI 就會被 Keychain 擋下來跳密碼框。
    /// 背景輪詢一律傳 false（跳不出來就當作沒有，改讀 jetski 檔案），否則每五分鐘跳一次。
    /// cockpit-tools 在 macOS 上根本不讀這個項目（`read_antigravity_system_credential` 只編進
    /// Windows），推測是同一個原因。
    func load(allowPrompt: Bool = false) -> Data? {
        guard let raw = rawItem(allowPrompt: allowPrompt) else { return nil }
        return Self.decode(raw)
    }

    /// 寫回官方 App 讀的位置。必須走 `security -A`：以 SecItemAdd 建立的項目只有 AspaceI 自己能讀，
    /// 官方 App 會被 Keychain 拒絕而當成沒登入。先刪再加是為了換掉既有項目的存取控制。
    ///
    /// 憑證只能放在 `-w` 的參數值裡。`-w` 不帶值改由 stdin 讀時，`security` 會在 128 個字元處
    /// 無聲截斷（2026-09-18 實測：送 418 字元讀回 128），寫出一份半截的 JSON 把官方 App 的登入弄壞。
    /// 代價是憑證會短暫出現在行程參數列，取捨後選會動的那個，與 cockpit-tools 相同。
    func save(_ credential: Data) throws {
        let payload = Self.prefix + Self.canonical(credential).base64EncodedString()
        // 寫壞了要能還原：先留住現有項目，驗證沒過就放回去，不留半份憑證在官方 App 的登入位置。
        let previous = rawItem()
        _ = try? run(["delete-generic-password", "-s", Self.service, "-a", Self.account])
        let result = try run(["add-generic-password", "-s", Self.service, "-a", Self.account, "-w", payload, "-A"])
        guard result.status == 0 else {
            try? restore(previous)
            throw CredentialProjectionError.systemCredentialWriteFailed(result.error)
        }
        // 讀回來逐位元組比對。Keychain 寫入沒有回報長度，不驗就可能把截斷或編碼錯誤當成切換成功。
        guard let written = rawItem(), written == Data(payload.utf8) else {
            try? restore(previous)
            throw CredentialProjectionError.systemCredentialWriteFailed("寫入後讀回的內容與原文不符")
        }
    }

    private func restore(_ previous: Data?) throws {
        guard let previous, let text = String(data: previous, encoding: .utf8) else { return }
        _ = try? run(["delete-generic-password", "-s", Self.service, "-a", Self.account])
        _ = try run(["add-generic-password", "-s", Self.service, "-a", Self.account, "-w", text, "-A"])
    }

    /// 項目的原始內容（還沒解 go-keyring 包裝），用於寫入前備份與寫入後比對。
    private func rawItem(allowPrompt: Bool = true) -> Data? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        if !allowPrompt {
            query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUISkip
        }
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
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

    private func run(_ arguments: [String]) throws -> (status: Int32, error: String) {
        let process = Process()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errorPipe
        try process.run()
        let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (process.terminationStatus, message)
    }
}
