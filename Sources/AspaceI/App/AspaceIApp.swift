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
    @State private var accountManager = AccountManager()
    @State private var instanceManager = InstanceManager()
    @State private var settingsManager = SettingsManager()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView()
                .environment(accountManager)
                .environment(instanceManager)
                .environment(settingsManager)
        } label: {
            Label(accountManager.menuBarTitle, systemImage: "gauge.with.dots.needle.50percent")
                .task {
                    await accountManager.autoImportLocalAccounts()
                    accountManager.startAutomaticRefresh()
                }
        }
        .menuBarExtraStyle(.window)
    }
}
