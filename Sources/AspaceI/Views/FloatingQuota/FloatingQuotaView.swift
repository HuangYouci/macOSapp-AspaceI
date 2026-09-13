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
                    VStack(alignment: .leading, spacing: 4) {
                        Label(account.displayName, systemImage: account.platform.symbolName)
                            .font(.subheadline)
                        if let window = account.quota?.windows.first {
                            ProgressView(value: Double(window.remainingPercentage), total: 100)
                            Text("\(window.remainingPercentage)%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text(String(localized: "QuotaUnavailable", defaultValue: "額度尚未取得"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .frame(minWidth: 260)
        .padding()
        .background(.regularMaterial)
    }
}
