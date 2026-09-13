import Foundation
import Observation

@MainActor
@Observable
final class AccountManager {
    private(set) var accounts: [Account] = []
    private(set) var isDiscovering = false
    var errorMessage: String?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    private let accountStore: AccountStore
    private let discoveryService: LocalAccountDiscoveryService
    private let importService = CredentialImportService.shared
    private let keychainService = KeychainService.shared
    private let quotaService = QuotaService.shared

    init(
        accountStore: AccountStore = .shared,
        discoveryService: LocalAccountDiscoveryService = .shared
    ) {
        self.accountStore = accountStore
        self.discoveryService = discoveryService
        loadAccounts()
    }

    var menuBarTitle: String {
        let percentages = accounts
            .compactMap(\.quota)
            .flatMap(\.windows)
            .map(\.remainingPercentage)
        guard let minimum = percentages.min() else {
            return "AspaceI"
        }
        return "\(minimum)%"
    }

    func discoverLocalAccounts() async {
        isDiscovering = true
        defer { isDiscovering = false }

        let candidates = await Task.detached(priority: .userInitiated) { [discoveryService] in
            discoveryService.discover()
        }.value
        guard !Task.isCancelled else { return }

        for candidate in candidates where !accounts.contains(where: { $0.platform == candidate.platform }) {
            accounts.append(
                Account(
                    platform: candidate.platform,
                    displayName: candidate.platform.displayName
                )
            )
        }
        persistAccounts()
    }

    func importLocalAccounts() async {
        isDiscovering = true
        defer { isDiscovering = false }
        let imported = await Task.detached(priority: .userInitiated) { [importService] in importService.importAvailable() }.value
        guard !Task.isCancelled else { return }
        for item in imported {
            let existing = accounts.firstIndex { $0.platform == item.platform && $0.sourcePath == item.sourcePath }
            let id = existing.map { accounts[$0].id } ?? UUID()
            let reference = item.data.map { _ in "\(item.platform.rawValue).\(id.uuidString)" }
            do {
                if let data = item.data, let reference {
                    try keychainService.save(data, account: reference)
                }
                let wasActive = existing.map { accounts[$0].isActive } ?? !accounts.contains { $0.platform == item.platform && $0.isActive }
                let account = Account(id: id, platform: item.platform, displayName: item.displayName, credentialReference: reference, sourcePath: item.sourcePath, isActive: wasActive)
                if let existing { accounts[existing] = account } else { accounts.append(account) }
            } catch { errorMessage = error.localizedDescription }
        }
        persistAccounts()
        await refreshAllQuotas()
    }

    func importFile(at url: URL, platform: PlatformKind) async {
        do {
            let item = try importService.importFile(at: url, platform: platform)
            let id = UUID()
            let reference = item.data.map { _ in "\(platform.rawValue).\(id.uuidString)" }
            if let data = item.data, let reference { try keychainService.save(data, account: reference) }
            accounts.append(Account(id: id, platform: platform, displayName: "\(platform.displayName) \(accounts.filter { $0.platform == platform }.count + 1)", credentialReference: reference, sourcePath: item.sourcePath, isActive: !accounts.contains { $0.platform == platform && $0.isActive }))
            persistAccounts()
            await refreshAllQuotas()
        } catch { errorMessage = error.localizedDescription }
    }

    func activate(_ account: Account) {
        for index in accounts.indices where accounts[index].platform == account.platform { accounts[index].isActive = accounts[index].id == account.id }
        persistAccounts()
    }

    func remove(_ account: Account) {
        if let reference = account.credentialReference { try? keychainService.delete(account: reference) }
        accounts.removeAll { $0.id == account.id }
        if !accounts.contains(where: { $0.platform == account.platform && $0.isActive }), let index = accounts.firstIndex(where: { $0.platform == account.platform }) { accounts[index].isActive = true }
        persistAccounts()
    }

    func credentialData(for accountID: UUID) throws -> Data? {
        guard let account = accounts.first(where: { $0.id == accountID }), let reference = account.credentialReference else { return nil }
        return try keychainService.load(account: reference)
    }

    func refreshAllQuotas() async {
        for index in accounts.indices {
            guard !Task.isCancelled else { return }
            guard let reference = accounts[index].credentialReference else { continue }
            do {
                guard let data = try keychainService.load(account: reference) else { throw QuotaError.missingToken }
                accounts[index].quota = try await quotaService.fetch(for: accounts[index], credentialData: data)
                accounts[index].lastError = nil
            } catch { accounts[index].lastError = error.localizedDescription }
        }
        persistAccounts()
    }

    func startAutomaticRefresh() {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(300))
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
            accounts = try accountStore.load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func persistAccounts() {
        do {
            try accountStore.save(accounts)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
