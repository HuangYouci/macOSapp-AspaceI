import Foundation
import Observation

@MainActor
@Observable
final class AccountManager {
    static let refreshInterval: Duration = .seconds(300)

    private static let defaultClientKey = "defaultClientAccountIDs"
    private static let dismissedLocalKey = "dismissedLocalPlatforms"

    private(set) var accounts: [Account] = []
    private(set) var isRefreshing = false
    /// 目前寫在官方 App 預設位置的帳號；沒有紀錄時就是本機匯入的那個帳號。
    private(set) var defaultClientAccountIDs: [PlatformKind: UUID] = [:]
    var errorMessage: String?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var didAutoImport = false
    @ObservationIgnored private var quotaRefreshInFlight = false
    @ObservationIgnored private var quotaRefreshPending = false

    private let accountStore: AccountStore
    private let importService = CredentialImportService.shared
    private let keychainService = KeychainService.shared
    private let quotaService = QuotaService.shared
    @ObservationIgnored private let defaults: UserDefaults

    init(accountStore: AccountStore = .shared, defaults: UserDefaults = .standard) {
        self.accountStore = accountStore
        self.defaults = defaults
        if let stored = defaults.dictionary(forKey: Self.defaultClientKey) as? [String: String] {
            for (platform, id) in stored {
                if let kind = PlatformKind(rawValue: platform), let uuid = UUID(uuidString: id) {
                    defaultClientAccountIDs[kind] = uuid
                }
            }
        }
        loadAccounts()
    }

    func defaultClientAccount(for platform: PlatformKind) -> Account? {
        Self.resolveDefaultClientAccount(for: platform, accounts: accounts, mapping: defaultClientAccountIDs)
    }

    static func resolveDefaultClientAccount(for platform: PlatformKind, accounts: [Account], mapping: [PlatformKind: UUID]) -> Account? {
        if let id = mapping[platform], let account = accounts.first(where: { $0.id == id && $0.platform == platform }) {
            return account
        }
        return accounts.first { $0.platform == platform && $0.origin == .local }
    }

    /// 把帳號寫進官方 App 的預設位置並設為目前帳號；關閉與重開 App 由 `InstanceManager` 負責。
    func switchDefaultClient(to account: Account) throws {
        let data = try account.credentialReference.flatMap { try keychainService.load(account: $0) }
        try CredentialProjectionService.shared.projectToDefaultClient(account: account, credentialData: data)
        defaultClientAccountIDs[account.platform] = account.id
        persistDefaultClientAccounts()
        activate(account)
    }

    func importLocalAccounts(includeKeychain: Bool = true, platforms: Set<PlatformKind> = Set(PlatformKind.allCases)) async {
        if includeKeychain {
            let remaining = (defaults.stringArray(forKey: Self.dismissedLocalKey) ?? []).filter { raw in
                !platforms.contains { $0.rawValue == raw }
            }
            defaults.set(remaining, forKey: Self.dismissedLocalKey)
        }
        isRefreshing = true
        defer { isRefreshing = false }
        let imported = await Task.detached(priority: .userInitiated) { [importService] in
            importService.importAvailable(includeKeychain: includeKeychain, platforms: platforms)
        }.value
        guard !Task.isCancelled else { return }
        for item in imported {
            if let switched = defaultClientAccountIDs[item.platform],
               let target = accounts.first(where: { $0.id == switched && $0.origin != .local }) {
                if let data = item.data, let reference = target.credentialReference, Self.localFile(data, belongsTo: target) {
                    do {
                        try keychainService.save(data, account: reference)
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
                continue
            }
            let existing = accounts.firstIndex { $0.platform == item.platform && $0.origin == .local }
            let id = existing.map { accounts[$0].id } ?? UUID()
            let reference = "\(item.platform.rawValue).\(id.uuidString)"
            do {
                guard let data = item.data else { continue }
                try keychainService.save(data, account: reference)
                if let existing {
                    accounts[existing].credentialReference = reference
                    accounts[existing].sourcePath = item.sourcePath
                    accounts[existing].lastError = nil
                } else {
                    accounts.append(Account(
                        id: id,
                        platform: item.platform,
                        displayName: item.displayName,
                        credentialReference: reference,
                        sourcePath: item.sourcePath,
                        isActive: !accounts.contains { $0.platform == item.platform && $0.isActive },
                        origin: .local
                    ))
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        persistAccounts()
        await refreshAllQuotas()
    }

    /// 使用者刪掉的本機帳號不在啟動時自動加回；按「讀取這台 Mac」才會重新加入。
    func autoImportLocalAccounts() async {
        guard !didAutoImport else { return }
        didAutoImport = true
        let dismissed = Set((defaults.stringArray(forKey: Self.dismissedLocalKey) ?? []).compactMap(PlatformKind.init(rawValue:)))
        await importLocalAccounts(includeKeychain: false, platforms: Set(PlatformKind.allCases).subtracting(dismissed))
    }

    func importFile(at url: URL, platform: PlatformKind) async {
        do {
            let item = try importService.importFile(at: url, platform: platform)
            guard let data = item.data else { throw CredentialImportError.emptyFile }
            let id = UUID()
            let reference = "\(platform.rawValue).\(id.uuidString)"
            try keychainService.save(data, account: reference)
            accounts.append(Account(
                id: id,
                platform: platform,
                displayName: item.displayName,
                credentialReference: reference,
                sourcePath: item.sourcePath,
                isActive: !accounts.contains { $0.platform == platform && $0.isActive },
                origin: .file
            ))
            errorMessage = nil
            persistAccounts()
            await refreshAllQuotas()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addCredential(platform: PlatformKind, displayName: String, value: String) async {
        do {
            let item = try importService.importText(value, platform: platform, displayName: displayName)
            guard let data = item.data else { throw CredentialImportError.emptyFile }
            let resolvedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            let id = UUID()
            let reference = "\(platform.rawValue).\(id.uuidString)"
            try keychainService.save(data, account: reference)
            accounts.append(Account(
                id: id,
                platform: platform,
                displayName: resolvedName.isEmpty ? platform.displayName : resolvedName,
                credentialReference: reference,
                sourcePath: item.sourcePath,
                isActive: !accounts.contains { $0.platform == platform && $0.isActive },
                origin: .manual
            ))
            errorMessage = nil
            persistAccounts()
            await refreshAllQuotas()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addOAuthCredential(_ credential: OAuthCredential) async {
        await storeAccount(
            platform: credential.platform,
            displayName: credential.email ?? credential.platform.displayName,
            email: credential.email,
            data: credential.data,
            sourcePath: "OAuth",
            origin: .oauth
        )
    }

    func exportData(accountIDs: [UUID]? = nil) throws -> Data {
        let selected = accounts.filter { accountIDs?.contains($0.id) ?? true }
        let items = try selected.compactMap { account -> AccountTransferItem? in
            guard let reference = account.credentialReference, let data = try keychainService.load(account: reference) else { return nil }
            return AccountTransferItem(platform: account.platform, displayName: account.displayName, email: account.email, credential: data)
        }
        guard !items.isEmpty else { throw AccountTransferError.noAccounts }
        return try AccountTransferService.encode(items)
    }

    /// 先當作帳號匯出檔解析；不是的話視為指定平台的單一憑證檔。
    func importFile(at url: URL, fallbackPlatform platform: PlatformKind) async {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        let isTransferFile = (try? Data(contentsOf: url)).map { (try? AccountTransferService.decode($0)) != nil } ?? false
        if isTransferFile {
            await importAccounts(from: url)
        } else {
            await importFile(at: url, platform: platform)
        }
    }

    func importAccounts(from url: URL) async {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        do {
            await importAccounts(data: try Data(contentsOf: url), sourceName: url.lastPathComponent)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func importAccounts(data: Data, sourceName: String) async {
        do {
            let items = try AccountTransferService.decode(data)
            for item in items {
                await storeAccount(
                    platform: item.platform,
                    displayName: item.displayName,
                    email: item.email,
                    data: item.credential,
                    sourcePath: sourceName,
                    origin: .file,
                    refreshAfterward: false
                )
            }
            errorMessage = nil
            await refreshAllQuotas()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 同平台同 email 的帳號視為同一人，覆寫憑證而不重複新增。
    private func storeAccount(
        platform: PlatformKind,
        displayName: String,
        email: String?,
        data: Data,
        sourcePath: String,
        origin: Account.Origin,
        refreshAfterward: Bool = true
    ) async {
        do {
            let existing = email.flatMap { email in
                accounts.firstIndex { $0.platform == platform && $0.origin != .local && $0.email?.caseInsensitiveCompare(email) == .orderedSame }
            }
            let id = existing.map { accounts[$0].id } ?? UUID()
            let reference = "\(platform.rawValue).\(id.uuidString)"
            try keychainService.save(data, account: reference)
            if let existing {
                accounts[existing].credentialReference = reference
                accounts[existing].sourcePath = sourcePath
                accounts[existing].origin = origin
                accounts[existing].lastError = nil
            } else {
                accounts.append(Account(
                    id: id,
                    platform: platform,
                    displayName: displayName,
                    email: email,
                    credentialReference: reference,
                    sourcePath: sourcePath,
                    isActive: !accounts.contains { $0.platform == platform && $0.isActive },
                    origin: origin
                ))
            }
            errorMessage = nil
            persistAccounts()
            if refreshAfterward { await refreshAllQuotas() }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func activate(_ account: Account) {
        for index in accounts.indices where accounts[index].platform == account.platform {
            accounts[index].isActive = accounts[index].id == account.id
        }
        persistAccounts()
    }

    func remove(_ account: Account) {
        if let reference = account.credentialReference {
            do {
                try keychainService.delete(account: reference)
            } catch {
                errorMessage = error.localizedDescription
                return
            }
        }
        accounts.removeAll { $0.id == account.id }
        if account.origin == .local {
            let dismissed = Set(defaults.stringArray(forKey: Self.dismissedLocalKey) ?? []).union([account.platform.rawValue])
            defaults.set(Array(dismissed).sorted(), forKey: Self.dismissedLocalKey)
        }
        if defaultClientAccountIDs[account.platform] == account.id {
            defaultClientAccountIDs[account.platform] = nil
            persistDefaultClientAccounts()
        }
        if !accounts.contains(where: { $0.platform == account.platform && $0.isActive }),
           let index = accounts.firstIndex(where: { $0.platform == account.platform }) {
            accounts[index].isActive = true
        }
        persistAccounts()
    }

    func credentialData(for accountID: UUID) throws -> Data? {
        guard let account = accounts.first(where: { $0.id == accountID }), let reference = account.credentialReference else { return nil }
        return try keychainService.load(account: reference)
    }

    /// 同一時間只跑一輪；Codex／Claude 的 refresh token 用過即失效，兩輪同時換發會把帳號弄壞。
    func refreshAllQuotas() async {
        guard !quotaRefreshInFlight else {
            quotaRefreshPending = true
            return
        }
        quotaRefreshInFlight = true
        isRefreshing = true
        defer {
            quotaRefreshInFlight = false
            isRefreshing = false
        }
        repeat {
            quotaRefreshPending = false
            await syncLocalCredentials()
            await refreshQuotasOnce()
        } while quotaRefreshPending && !Task.isCancelled
    }

    /// 官方客戶端會自己換新 token；每輪先從它們的檔案同步最新憑證，避免 AspaceI 手上的副本過期。只讀檔案，不讀 Keychain。
    private func syncLocalCredentials() async {
        let imported = await Task.detached(priority: .utility) { [importService] in
            importService.importAvailable(includeKeychain: false)
        }.value
        for item in imported {
            guard let data = item.data,
                  let account = defaultClientAccount(for: item.platform),
                  let reference = account.credentialReference,
                  Self.localFile(data, belongsTo: account) else { continue }
            do {
                guard try keychainService.load(account: reference) != data else { continue }
                try keychainService.save(data, account: reference)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// 使用者可能在官方 App 裡自己換了帳號；Codex 的檔案帶 email，對不上就不覆寫。
    static func localFile(_ data: Data, belongsTo account: Account) -> Bool {
        guard account.platform == .codex, let email = account.email,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let idToken = (root["tokens"] as? [String: Any])?["id_token"] as? String,
              let fileEmail = OAuthService.jwtClaims(idToken)?["email"] as? String else { return true }
        return fileEmail.caseInsensitiveCompare(email) == .orderedSame
    }

    private func refreshQuotasOnce() async {
        for account in accounts {
            guard !Task.isCancelled else { return }
            do {
                guard let reference = account.credentialReference,
                      let data = try keychainService.load(account: reference) else {
                    throw QuotaError.missingToken
                }
                let snapshot = try await fetchQuota(for: account, data: data, reference: reference)
                guard let index = accounts.firstIndex(where: { $0.id == account.id }) else { continue }
                accounts[index].quota = snapshot
                if let identity = snapshot.identity { accounts[index].email = identity }
                if let plan = snapshot.plan { accounts[index].planName = plan }
                accounts[index].lastError = nil
            } catch is CancellationError {
                return
            } catch {
                guard let index = accounts.firstIndex(where: { $0.id == account.id }) else { continue }
                accounts[index].lastError = error.localizedDescription
            }
        }
        persistAccounts()
    }

    /// 正在官方 App 裡使用的帳號由官方 App 換新 token，AspaceI 再換會讓官方 App 被登出；其他帳號才由 AspaceI 換新。
    private func fetchQuota(for account: Account, data: Data, reference: String) async throws -> QuotaSnapshot {
        let inOfficialClient = account.platform.supportsDefaultSwitch
            ? defaultClientAccount(for: account.platform)?.id == account.id
            : account.origin == .local
        let canRotate = !inOfficialClient && account.origin != .local && (account.platform == .codex || account.platform == .claude)
        var credential = data
        let expiresSoon = account.platform == .claude
            ? OAuthService.claudeTokenExpired(credential)
            : OAuthService.codexNeedsRefresh(credential)
        if canRotate, expiresSoon {
            credential = try await rotate(account, credential: credential, reference: reference)
        }
        do {
            return try await quotaService.fetch(for: account, credentialData: credential)
        } catch QuotaError.tokenExpired where canRotate {
            do {
                credential = try await rotate(account, credential: credential, reference: reference)
            } catch OAuthError.missingRefreshToken {
                throw account.platform == .claude ? QuotaError.tokenCannotReadUsage : QuotaError.tokenExpired
            }
            return try await quotaService.fetch(for: account, credentialData: credential)
        }
    }

    private func rotate(_ account: Account, credential: Data, reference: String) async throws -> Data {
        let refreshed = account.platform == .codex
            ? try await OAuthService.shared.refreshCodex(credential)
            : try await OAuthService.shared.refreshClaude(credential)
        try keychainService.save(refreshed, account: reference)
        return refreshed
    }

    func startAutomaticRefresh() {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: Self.refreshInterval)
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                await self?.refreshAllQuotas()
            }
        }
    }

    private func loadAccounts() {
        do {
            let loaded = try accountStore.load()
            let (kept, dropped) = Self.collapsingDuplicateLocalAccounts(loaded)
            accounts = kept
            for account in dropped {
                if let reference = account.credentialReference { try keychainService.delete(account: reference) }
            }
            if !dropped.isEmpty { persistAccounts() }
            alignActiveWithDefaultClient()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 每個平台只保留一個本機匯入帳號；優先保留有憑證、再來是目前帳號。
    static func collapsingDuplicateLocalAccounts(_ accounts: [Account]) -> (kept: [Account], dropped: [Account]) {
        var keeperByPlatform: [PlatformKind: UUID] = [:]
        for platform in PlatformKind.allCases {
            let locals = accounts.filter { $0.platform == platform && $0.origin == .local }
            let keeper = locals.first { $0.credentialReference != nil && $0.isActive }
                ?? locals.first { $0.credentialReference != nil }
                ?? locals.first
            keeperByPlatform[platform] = keeper?.id
        }
        var kept: [Account] = []
        var dropped: [Account] = []
        for account in accounts {
            if account.origin == .local, keeperByPlatform[account.platform] != account.id {
                dropped.append(account)
            } else {
                kept.append(account)
            }
        }
        for platform in PlatformKind.allCases where !kept.contains(where: { $0.platform == platform && $0.isActive }) {
            if let index = kept.firstIndex(where: { $0.platform == platform }) { kept[index].isActive = true }
        }
        return (kept, dropped)
    }

    private func alignActiveWithDefaultClient() {
        for platform in PlatformKind.allCases where platform.supportsDefaultSwitch {
            guard let current = defaultClientAccount(for: platform) else { continue }
            for index in accounts.indices where accounts[index].platform == platform {
                accounts[index].isActive = accounts[index].id == current.id
            }
        }
    }

    private func persistDefaultClientAccounts() {
        defaults.set(Dictionary(uniqueKeysWithValues: defaultClientAccountIDs.map { ($0.key.rawValue, $0.value.uuidString) }), forKey: Self.defaultClientKey)
    }

    private func persistAccounts() {
        do {
            try accountStore.save(accounts)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
