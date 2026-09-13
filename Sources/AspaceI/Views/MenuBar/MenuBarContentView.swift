import SwiftUI

struct MenuBarContentView: View {
    @Environment(AccountManager.self) private var accountManager
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
                    Label(account.displayName, systemImage: account.platform.symbolName)
                }
            }

            Divider()

            Button(String(localized: "DiscoverAccounts", defaultValue: "偵測本機帳號")) {
                Task {
                    await accountManager.discoverLocalAccounts()
                }
            }
            .disabled(accountManager.isDiscovering)

            Button(String(localized: "OpenAccounts", defaultValue: "帳號與額度")) {
                openWindow(id: "accounts")
            }

            Button(String(localized: "OpenFloatingQuota", defaultValue: "顯示漂浮額度")) {
                openWindow(id: "floating-quota")
            }

            Divider()

            Button(String(localized: "Quit", defaultValue: "結束 AspaceI")) {
                NSApplication.shared.terminate(nil)
            }
        }
        .frame(width: 260)
        .padding()
    }
}
