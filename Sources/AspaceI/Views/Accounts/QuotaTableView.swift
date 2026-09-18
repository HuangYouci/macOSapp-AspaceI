import SwiftUI

struct QuotaTableView: View {
    let accounts: [Account]
    let defaultClientAccountIDs: Set<UUID>
    let switchingPlatform: PlatformKind?
    let onSwitch: (Account) -> Void
    let onActivate: (Account) -> Void
    let onRemove: (Account) -> Void

    private static let columns: [QuotaWindow.Kind] = [.fiveHour, .week, .month]
    private static let valueWidth: CGFloat = 64
    private static let menuWidth: CGFloat = 30

    var body: some View {
        // 倒數每秒重畫；popup 收起時視圖消失，不會在背景持續更新。
        TimelineView(.periodic(from: .now, by: 1)) { context in
            content(now: context.date)
        }
    }

    private func content(now: Date) -> some View {
        VStack(spacing: 10) {
            ForEach(sections, id: \.platform) { section in
                card(section.platform, accounts: section.accounts, now: now)
            }
            if let updatedAt = accounts.compactMap(\.quota?.fetchedAt).max() {
                // 帶秒數：手動按更新時，同一分鐘內只有時分的話這行不會變，看起來就像沒更新。
                Text("更新於 \(updatedAt.formatted(date: .omitted, time: .standard))")
                    .font(.scaled(.caption2))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 2)
            }
        }
    }

    private var sections: [(platform: PlatformKind, accounts: [Account])] {
        PlatformKind.allCases.compactMap { platform in
            let matched = accounts.filter { $0.platform == platform }
            return matched.isEmpty ? nil : (platform, matched)
        }
    }

    private func card(_ platform: PlatformKind, accounts: [Account], now: Date) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                HStack(spacing: 7) {
                    PlatformBadge(platform: platform, size: 18)
                    Text(platform.displayName)
                        .font(.scaled(.caption, weight: .semibold))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(Self.columns, id: \.self) { kind in
                    Text(kind.shortTitle)
                        .font(.scaled(.caption2, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .frame(width: Self.valueWidth, alignment: .trailing)
                }
                Color.clear.frame(width: Self.menuWidth)
            }
            .padding(.horizontal, 14)
            .padding(.top, 11)
            .padding(.bottom, 6)

            ForEach(Array(accounts.enumerated()), id: \.element.id) { index, account in
                if index > 0 {
                    Divider().padding(.leading, 14)
                }
                row(account, now: now)
            }
        }
        .padding(.bottom, 4)
        .cardStyle()
    }

    private func row(_ account: Account, now: Date) -> some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(account.label)
                        .font(.scaled(.subheadline, weight: account.isActive ? .semibold : .regular))
                        .foregroundStyle(account.isActive ? .primary : .secondary)
                        .lineLimit(1)
                    if let plan = account.planName {
                        Text(plan)
                            .font(.scaled(.caption2, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.black.opacity(0.05), in: Capsule())
                            .fixedSize()
                    }
                }
                if let error = account.lastError {
                    Text(error)
                        .font(.scaled(.caption2))
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(Self.columns, id: \.self) { kind in
                valueCell(account.quota?.primaryWindows.first { $0.kind == kind }, now: now)
            }

            Menu {
                actions(account)
            } label: {
                Image(nsImage: .verticalEllipsis)
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 22)
                    .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .frame(width: Self.menuWidth, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .contextMenu {
            actions(account)
        }
    }

    @ViewBuilder
    private func actions(_ account: Account) -> some View {
        if account.platform.supportsDefaultSwitch {
            if defaultClientAccountIDs.contains(account.id) {
                Button("\(account.platform.clientName) 使用中", systemImage: "checkmark") {}
                    .disabled(true)
            } else {
                Button("切換 \(account.platform.clientName) 到此帳號", systemImage: "arrow.left.arrow.right") { onSwitch(account) }
                    .disabled(switchingPlatform != nil)
            }
        } else if !account.isActive {
            Button("設為目前帳號", systemImage: "checkmark.circle") { onActivate(account) }
        }
        Divider()
        Button("刪除…", systemImage: "trash", role: .destructive) { onRemove(account) }
    }

    private func valueCell(_ window: QuotaWindow?, now: Date) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            if let window {
                Text("\(window.remainingPercentage)%")
                    .font(.scaled(.subheadline, weight: .medium, design: .rounded))
                    .monospacedDigit()
                if let resetsAt = window.resetsAt, let countdown = QuotaCountdown.text(until: resetsAt, now: now) {
                    Text(countdown)
                        .font(.scaled(.caption2))
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            } else {
                Text("–")
                    .font(.scaled(.subheadline))
                    .foregroundStyle(.quaternary)
            }
        }
        .frame(width: Self.valueWidth, alignment: .trailing)
    }
}
