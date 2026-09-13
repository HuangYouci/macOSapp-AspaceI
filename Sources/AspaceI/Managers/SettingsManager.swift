import Foundation
import Observation
import ServiceManagement

@MainActor
@Observable
final class SettingsManager {
    private static let menuBarAccountsKey = "menuBarAccountIDs"

    private(set) var launchAtLogin = false
    private(set) var menuBarAccountIDs: [UUID] = []
    var errorMessage: String?

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        menuBarAccountIDs = (defaults.stringArray(forKey: Self.menuBarAccountsKey) ?? []).compactMap(UUID.init(uuidString:))
        refreshLaunchAtLoginStatus()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            refreshLaunchAtLoginStatus()
            errorMessage = nil
        } catch {
            refreshLaunchAtLoginStatus()
            errorMessage = error.localizedDescription
        }
    }

    func refreshLaunchAtLoginStatus() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func isShownInMenuBar(_ accountID: UUID) -> Bool {
        menuBarAccountIDs.contains(accountID)
    }

    var canAddMenuBarAccount: Bool {
        menuBarAccountIDs.count < MenuBarQuotaItem.limit
    }

    func setMenuBar(_ accountID: UUID, shown: Bool) {
        if shown {
            guard !menuBarAccountIDs.contains(accountID), canAddMenuBarAccount else { return }
            menuBarAccountIDs.append(accountID)
        } else {
            menuBarAccountIDs.removeAll { $0 == accountID }
        }
        defaults.set(menuBarAccountIDs.map(\.uuidString), forKey: Self.menuBarAccountsKey)
    }
}
