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
                .environment(settingsManager)
        } label: {
            Label(accountManager.menuBarTitle, systemImage: "gauge.with.dots.needle.50percent")
        }
        .menuBarExtraStyle(.window)

        WindowGroup(String(localized: "MainWindowTitle", defaultValue: "AspaceI"), id: "dashboard") {
            DashboardView()
                .environment(accountManager)
                .environment(instanceManager)
                .environment(settingsManager)
        }
        .defaultSize(width: 760, height: 560)

        WindowGroup(String(localized: "FloatingWindowTitle", defaultValue: "額度"), id: "floating-quota") {
            FloatingQuotaView()
                .environment(accountManager)
        }
        .defaultSize(width: 300, height: 240)
        .windowStyle(.plain)
        .windowLevel(.floating)

    }
}
