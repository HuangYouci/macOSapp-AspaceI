import SwiftUI

struct AccountListView: View {
    @Environment(AccountManager.self) private var accountManager

    var body: some View {
        NavigationStack {
            List(accountManager.accounts) { account in
                VStack(alignment: .leading, spacing: 4) {
                    Label(account.displayName, systemImage: account.platform.symbolName)
                        .font(.headline)
                    Text(account.planName ?? String(localized: "PlanUnknown", defaultValue: "方案未知"))
                        .foregroundStyle(.secondary)
                    if let error = account.lastError {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
                .padding(.vertical, 4)
            }
            .overlay {
                if accountManager.accounts.isEmpty {
                    ContentUnavailableView(
                        String(localized: "NoAccounts", defaultValue: "尚未加入帳號"),
                        systemImage: "person.crop.circle.badge.questionmark"
                    )
                }
            }
            .navigationTitle(String(localized: "AccountsTitle", defaultValue: "帳號與額度"))
            .toolbar {
                Button(String(localized: "ImportAccounts", defaultValue: "匯入本機帳號")) {
                    Task {
                        await accountManager.importLocalAccounts()
                    }
                }
            }
        }
    }
}
