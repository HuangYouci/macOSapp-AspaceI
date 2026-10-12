import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

@main
struct AspaceIApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var accountManager: AccountManager
    @State private var instanceManager = InstanceManager()
    @State private var settingsManager = SettingsManager()
    @State private var usageManager = UsageManager()
    @State private var loginManager: AccountLoginManager

    init() {
        let accounts = AccountManager()
        _accountManager = State(initialValue: accounts)
        _loginManager = State(initialValue: AccountLoginManager { credential in
            await accounts.addOAuthCredential(credential)
        })
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView()
                .environment(accountManager)
                .environment(instanceManager)
                .environment(settingsManager)
                .environment(loginManager)
                .environment(usageManager)
        } label: {
            MenuBarLabel(items: MenuBarQuotaItem.items(
                accounts: accountManager.accounts,
                selectedIDs: settingsManager.menuBarAccountIDs,
                mode: settingsManager.menuBarQuotaMode
            ))
                .onChange(of: accountManager.accounts.map(\.label)) {
                    Task { await instanceManager.refreshCloneIcons(accounts: accountManager) }
                }
                .onChange(of: instanceManager.instances) {
                    Task { await instanceManager.refreshCloneIcons(accounts: accountManager) }
                }
                .onChange(of: instanceManager.signedInAccountUUIDs) {
                    Task { await instanceManager.refreshCloneIcons(accounts: accountManager) }
                }
                .task {
                    instanceManager.startMonitoring(accounts: accountManager)
                    await accountManager.autoImportLocalAccounts()
                    accountManager.startAutomaticRefresh()
                    usageManager.startAutomaticRefresh(instances: instanceManager)
                }
        }
        .menuBarExtraStyle(.window)
    }
}
