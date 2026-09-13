import SwiftUI

struct FloatingQuotaView: View {
    @Environment(AccountManager.self) private var accountManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(String(localized: "QuotaTitle", defaultValue: "額度"))
                    .font(.headline)
                Spacer()
                Text(Date.now, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if accountManager.accounts.isEmpty {
                Text(String(localized: "NoAccounts", defaultValue: "尚未加入帳號"))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(accountManager.accounts) { account in
                    AccountQuotaRow(account: account, compact: true)
                }
            }
        }
        .frame(minWidth: 260)
        .padding()
        .background(.regularMaterial)
    }
}
