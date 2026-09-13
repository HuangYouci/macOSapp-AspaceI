import SwiftUI

@main
struct AspaceIApp: App {
    @State private var accountManager = AccountManager()
    @State private var instanceManager = InstanceManager()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView()
                .environment(accountManager)
        } label: {
            Label(accountManager.menuBarTitle, systemImage: "gauge.with.dots.needle.50percent")
        }
        .menuBarExtraStyle(.window)

        WindowGroup(String(localized: "AccountsWindowTitle", defaultValue: "AspaceI"), id: "accounts") {
            AccountListView()
                .environment(accountManager)
        }
        .defaultSize(width: 620, height: 480)

        WindowGroup(String(localized: "FloatingWindowTitle", defaultValue: "額度"), id: "floating-quota") {
            FloatingQuotaView()
                .environment(accountManager)
        }
        .defaultSize(width: 300, height: 240)
        .windowStyle(.plain)
        .windowLevel(.floating)

        WindowGroup("Instances", id: "instances") {
            NavigationStack { InstanceListView() }
                .environment(instanceManager)
        }
        .defaultSize(width: 620, height: 480)
    }
}
