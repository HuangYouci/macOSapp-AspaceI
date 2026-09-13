import SwiftUI

struct AccountQuotaRow: View {
    let account: Account
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(account.platform.initials)
                    .font(.caption2.weight(.bold))
                    .frame(width: 24, height: 24)
                    .foregroundStyle(account.platform.tint)
                    .background(account.platform.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))

                Text(account.displayName)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if account.isActive {
                    Text("目前")
                        .font(.caption)
                        .foregroundStyle(.tint)
                }
            }

            if let windows = account.quota?.windows, !windows.isEmpty {
                HStack(spacing: 18) {
                    ForEach(compact ? Array(windows.prefix(2)) : windows) { window in
                        VStack(spacing: 5) {
                            ZStack {
                                Circle()
                                    .stroke(.quaternary, lineWidth: 5)
                                Circle()
                                    .trim(from: 0, to: Double(window.remainingPercentage) / 100)
                                    .stroke(account.platform.tint, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                                    .rotationEffect(.degrees(-90))
                                Text("\(window.remainingPercentage)%")
                                    .font(.caption.weight(.semibold))
                                    .monospacedDigit()
                            }
                            .frame(width: 52, height: 52)

                            Text(window.title)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            if let resetsAt = window.resetsAt {
                                Text(resetsAt, style: .relative)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
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
        .padding(12)
        .background(.quaternary.opacity(0.65), in: RoundedRectangle(cornerRadius: 12))
    }
}

extension PlatformKind {
    var initials: String {
        switch self {
        case .antigravity: "AG"
        case .codex: "CX"
        case .claude: "CL"
        case .githubCopilot: "GH"
        }
    }

    var tint: Color {
        switch self {
        case .antigravity: .purple
        case .codex: .blue
        case .claude: .orange
        case .githubCopilot: .cyan
        }
    }
}
