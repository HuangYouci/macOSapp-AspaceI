import SwiftUI

extension SettingsView {
    /// 勾選要顯示在 menu bar 的帳號，順序依勾選先後。
    struct MenuBarAccountsPage: View {
        @Environment(SettingsManager.self) private var settingsManager
        @Environment(AccountManager.self) private var accountManager
        let onBack: () -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 18) {
                SettingsForm.pageHeader("顯示的帳號", onBack: onBack)
                SettingsForm.section("Menu bar", trailing: "\(settingsManager.menuBarAccountIDs.count)") {
                    if accountManager.accounts.isEmpty {
                        SettingsForm.row {
                            Text("尚未加入帳號")
                                .foregroundStyle(.secondary)
                        }
                    }
                    ForEach(Array(accountManager.accounts.enumerated()), id: \.element.id) { index, account in
                        if index > 0 { SettingsForm.divider }
                        accountRow(account)
                    }
                }
            }
            .padding(.bottom, 4)
        }

        private func accountRow(_ account: Account) -> some View {
            let shown = settingsManager.isShownInMenuBar(account.id)
            return Button {
                settingsManager.setMenuBar(account.id, shown: !shown)
            } label: {
                SettingsForm.row {
                    PlatformBadge(platform: account.platform, size: 22)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(account.label)
                            .lineLimit(1)
                        Text(account.platform.displayName)
                            .font(.scaled(.caption))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: shown ? "checkmark.circle.fill" : "circle")
                        .font(.scaled(.title3))
                        .foregroundStyle(shown ? Color.accentColor : Color.secondary.opacity(0.5))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}
