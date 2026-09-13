import SwiftUI

struct QuotaTableView: View {
    let accounts: [Account]
    let defaultClientAccountIDs: Set<UUID>
    let switchingPlatform: PlatformKind?
    let onSwitch: (Account) -> Void
    let onActivate: (Account) -> Void
    let onRemove: (Account) -> Void

    private static let columns: [QuotaWindow.Kind] = [.fiveHour, .week, .month]
    private static let valueWidth: CGFloat = 58
    private static let menuWidth: CGFloat = 30

    var body: some View {
        VStack(spacing: 10) {
            ForEach(sections, id: \.platform) { section in
                card(section.platform, accounts: section.accounts)
            }
            if let updatedAt = accounts.compactMap(\.quota?.fetchedAt).max() {
                Text("更新於 \(updatedAt.formatted(date: .omitted, time: .shortened))")
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

    private func card(_ platform: PlatformKind, accounts: [Account]) -> some View {
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
                row(account)
            }
        }
        .padding(.bottom, 4)
        .cardStyle()
    }

    private func row(_ account: Account) -> some View {
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
                valueCell(account.quota?.primaryWindows.first { $0.kind == kind })
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

    private func valueCell(_ window: QuotaWindow?) -> some View {
        Group {
            if let window {
                Text("\(window.remainingPercentage)%")
                    .font(.scaled(.subheadline, weight: .medium, design: .rounded))
                    .monospacedDigit()
            } else {
                Text("–")
                    .font(.scaled(.subheadline))
                    .foregroundStyle(.quaternary)
            }
        }
        .frame(width: Self.valueWidth, alignment: .trailing)
    }
}
