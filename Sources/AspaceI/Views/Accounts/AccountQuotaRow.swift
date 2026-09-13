import SwiftUI

struct AccountQuotaRow: View {
    let account: Account
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(account.displayName, systemImage: account.platform.symbolName)
                    .font(.subheadline.weight(.medium))
                Spacer()
                if account.isActive {
                    Text("目前")
                        .font(.caption)
                        .foregroundStyle(.tint)
                }
            }

            if let windows = account.quota?.windows, !windows.isEmpty {
                ForEach(compact ? Array(windows.prefix(2)) : windows) { window in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(window.title)
                            Spacer()
                            Text("\(window.remainingPercentage)%")
                                .monospacedDigit()
                        }
                        .font(.caption)
                        ProgressView(value: Double(window.remainingPercentage), total: 100)
                        if let resetsAt = window.resetsAt {
                            Text(resetsAt, style: .relative)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                if let error = account.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                } else {
                    Text("額度尚未取得")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
