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
