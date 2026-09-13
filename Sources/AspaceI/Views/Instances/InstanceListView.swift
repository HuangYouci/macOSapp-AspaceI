import SwiftUI

struct InstanceListView: View {
    @Environment(InstanceManager.self) private var instanceManager
    @Environment(AccountManager.self) private var accountManager
    let onAdd: (PlatformKind) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(instanceManager.groups) { group in
                    section(group)
                }
            }
            .padding(2)
        }
        .onAppear { instanceManager.refreshRunning() }
    }

    private func section(_ group: InstanceManager.Group) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                PlatformBadge(platform: group.platform, size: 20)
                Text(group.platform.clientName)
                    .font(.scaled(.subheadline, weight: .semibold))
                if !group.isInstalled {
                    Text("未安裝")
                        .font(.scaled(.caption))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Button("新增實例", systemImage: "plus") { onAdd(group.platform) }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .disabled(!group.isInstalled)
            }
            .padding(.horizontal, 6)

            VStack(spacing: 0) {
                ForEach(Array(group.all.enumerated()), id: \.element.id) { index, instance in
                    if index > 0 { Divider().padding(.leading, 31) }
                    row(instance, installed: group.isInstalled)
                }
            }
            .cardStyle()
        }
    }

    private func row(_ instance: Instance, installed: Bool) -> some View {
        let running = instanceManager.isRunning(instance)
        let isDefault = instanceManager.isDefault(instance)
        return HStack(spacing: 10) {
            Circle()
                .fill(running ? Color.green : Color.black.opacity(0.12))
                .frame(width: 7, height: 7)

            Text(instance.name)
                .font(.scaled(.subheadline, weight: isDefault ? .semibold : .regular))
                .lineLimit(1)

            Spacer(minLength: 8)

            if isDefault, instance.platform.supportsDefaultSwitch {
                defaultAccountMenu(instance.platform)
            } else if instance.platform.supportsAccountBinding(isDefault: isDefault) {
                accountMenu(instance)
            }

            Button(running ? "停止" : "啟動") {
                if running {
                    instanceManager.stop(instance)
                } else {
                    instanceManager.launch(instance, accounts: accountManager)
                }
            }
            .buttonStyle(.bordered)
            .tint(running ? .red : .accentColor)
            .disabled(!installed)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .contextMenu {
            if !isDefault {
                Button("刪除", role: .destructive) { Task { await instanceManager.remove(instance) } }
            }
        }
    }

    /// 預設實例的帳號就是官方 App 目前登入的帳號；選另一個會關閉官方 App、寫入後重開。
    private func defaultAccountMenu(_ platform: PlatformKind) -> some View {
        let current = accountManager.defaultClientAccount(for: platform)
        let switching = instanceManager.switchingPlatform == platform
        return Menu {
            ForEach(accountManager.accounts.filter { $0.platform == platform }) { account in
                Button {
                    guard account.id != current?.id else { return }
                    Task { await instanceManager.switchDefault(to: account, accounts: accountManager) }
                } label: {
                    if account.id == current?.id {
                        Label(account.label, systemImage: "checkmark")
                    } else {
                        Text(account.label)
                    }
                }
            }
        } label: {
            Text(switching ? "切換中" : (current?.label ?? "未登入"))
                .font(.scaled(.caption))
                .foregroundStyle(current == nil ? .tertiary : .secondary)
                .lineLimit(1)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(instanceManager.switchingPlatform != nil)
    }

    private func accountMenu(_ instance: Instance) -> some View {
        let candidates = accountManager.accounts.filter { $0.platform == instance.platform }
        let bound = candidates.first { $0.id == instance.accountID }
        return Menu {
            Button("不綁定") { instanceManager.bind(instance, accountID: nil) }
            Divider()
            ForEach(candidates) { account in
                Button(account.label) { instanceManager.bind(instance, accountID: account.id) }
            }
        } label: {
            Text(bound?.label ?? "不綁定")
                .font(.scaled(.caption))
                .foregroundStyle(bound == nil ? .tertiary : .secondary)
                .lineLimit(1)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}
