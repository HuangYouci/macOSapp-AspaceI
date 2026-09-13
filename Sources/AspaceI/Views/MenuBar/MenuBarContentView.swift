import SwiftUI

struct MenuBarContentView: View {
    @Environment(AccountManager.self) private var accountManager
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "AppName", defaultValue: "AspaceI"))
                .font(.headline)

            if accountManager.accounts.isEmpty {
                Text(String(localized: "NoAccounts", defaultValue: "尚未加入帳號"))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(accountManager.accounts) { account in
                    AccountQuotaRow(account: account, compact: true)
                }
            }

            Divider()

            if let error = accountManager.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button(String(localized: "ImportAccounts", defaultValue: "匯入本機帳號")) {
                Task {
                    await accountManager.importLocalAccounts()
                }
            }

            Button(String(localized: "RefreshQuota", defaultValue: "更新額度")) {
                Task { await accountManager.refreshAllQuotas() }
            }
            .disabled(accountManager.isDiscovering)

            Button(String(localized: "OpenDashboard", defaultValue: "開啟 AspaceI")) {
                openWindow(id: "dashboard")
                NSApplication.shared.activate()
            }

            Button(String(localized: "OpenFloatingQuota", defaultValue: "顯示漂浮額度")) {
                openWindow(id: "floating-quota")
                NSApplication.shared.activate()
            }

            Toggle(
                String(localized: "LaunchAtLogin", defaultValue: "登入時開啟"),
                isOn: Binding(
                    get: { settingsManager.launchAtLogin },
                    set: { settingsManager.setLaunchAtLogin($0) }
                )
            )

            Divider()

            Button(String(localized: "Quit", defaultValue: "結束 AspaceI")) {
                NSApplication.shared.terminate(nil)
            }
        }
        .frame(width: 300)
        .padding()
        .onAppear { accountManager.startAutomaticRefresh() }
    }
}
