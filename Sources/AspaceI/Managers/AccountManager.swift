import Foundation
import Observation

@MainActor
@Observable
final class AccountManager {
    private(set) var accounts: [Account] = []
    private(set) var isDiscovering = false
    var errorMessage: String?

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
                let account = Account(id: id, platform: item.platform, displayName: item.displayName, credentialReference: reference, sourcePath: item.sourcePath)
                if let existing { accounts[existing] = account } else { accounts.append(account) }
            } catch { errorMessage = error.localizedDescription }
        }
        persistAccounts()
        await refreshAllQuotas()
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
