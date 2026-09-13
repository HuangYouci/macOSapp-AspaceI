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
        } label: {
            MenuBarLabel(items: MenuBarQuotaItem.items(accounts: accountManager.accounts, selectedIDs: settingsManager.menuBarAccountIDs))
                .task {
                    await accountManager.autoImportLocalAccounts()
                    accountManager.startAutomaticRefresh()
                }
        }
        .menuBarExtraStyle(.window)
    }
}
