import SwiftUI

struct MenuBarContentView: View {
    @Environment(AccountManager.self) private var accountManager
    @Environment(InstanceManager.self) private var instanceManager
    @Environment(AccountLoginManager.self) private var loginManager
    @State private var selection = Section.quota
    @State private var editor: Editor?
    @State private var confirmation: ConfirmationRequest?

    var body: some View {
        VStack(spacing: 10) {
            switch editor {
            case .account:
                ScrollView { AccountEditorView { editor = nil }.padding(2) }
            case .instance(let platform):
                ScrollView { InstanceEditorView(platform: platform) { editor = nil }.padding(2) }
            case nil:
                header
                switch selection {
                case .quota:
                    quotaView
                case .instances:
                    InstanceListView { editor = .instance($0) }
                case .settings:
                    ScrollView { SettingsView(confirm: { confirmation = $0 }).padding(2) }
                }
            }

            if let errorMessage = accountManager.errorMessage ?? instanceManager.errorMessage {
                Text(errorMessage)
                    .font(.scaled(.caption2))
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .frame(width: 456, height: 640, alignment: .top)
        .font(.scaled(.body))
        .background(Color(nsColor: .windowBackgroundColor))
        .background(PopupWindowConfigurator())
        .environment(\.colorScheme, .light)
        .onAppear {
            accountManager.startAutomaticRefresh()
            switch loginManager.phase {
            case .idle: break
            case .succeeded: loginManager.cancel()
            default: editor = .account
            }
        }
        .overlay {
            if let request = confirmation {
                ConfirmationOverlay(request: request) { confirmation = nil }
            }
        }
        .onChange(of: loginManager.phase) { _, phase in
            if case .succeeded = phase {
                editor = nil
                loginManager.cancel()
            }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            HStack(spacing: 2) {
                tabButton(.quota)
                tabButton(.instances)
                tabButton(.settings)
            }
            .padding(2)
            .background(Color.black.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))

            Spacer(minLength: 4)

            actions
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch selection {
        case .quota:
            // 一輪要跑完所有帳號約數秒，期間按鈕是停用的。沒有進行中的訊號時，圖示只是變灰再變回來，
            // 百分比與「更新於」又常常原封不動，按下去看起來就像沒有反應。
            Button("更新", systemImage: "arrow.clockwise") {
                Task { await accountManager.refreshAllQuotas() }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .symbolEffect(.rotate, options: .repeating, isActive: accountManager.isRefreshing)
            .disabled(accountManager.isRefreshing)
            Button("加入帳號", systemImage: "plus") { editor = .account }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
        case .instances:
            Button("更新", systemImage: "arrow.clockwise") { instanceManager.refreshRunning() }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
        case .settings:
            EmptyView()
        }
    }

    private var quotaView: some View {
        ScrollView {
            if accountManager.accounts.isEmpty {
                Text("尚未加入帳號")
                    .font(.scaled(.callout))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                QuotaTableView(
                    accounts: accountManager.accounts,
                    defaultClientAccountIDs: Set(PlatformKind.allCases.filter(\.supportsDefaultSwitch).compactMap { accountManager.defaultClientAccount(for: $0)?.id }),
                    switchingPlatform: instanceManager.switchingPlatform,
                    onSwitch: { account in
                        Task {
                            if let appName = await instanceManager.runningDefaultAppName(for: account.platform) {
                                confirmation = ConfirmationRequest(
                                    title: "切換到 \(account.label)？",
                                    message: "\(appName) 正在執行，未儲存的內容可能遺失。",
                                    confirmTitle: "關閉 \(appName) 並切換",
                                    isDestructive: false
                                ) {
                                    Task { await instanceManager.switchDefault(to: account, accounts: accountManager) }
                                }
                            } else {
                                await instanceManager.switchDefault(to: account, accounts: accountManager)
                            }
                        }
                    },
                    onActivate: { accountManager.activate($0) },
                    onRemove: { account in
                        confirmation = ConfirmationRequest(
                            title: "刪除 \(account.label)？",
                            message: "\(account.platform.displayName) 的登入資料會從 AspaceI 移除，官方 App 的登入不受影響。",
                            confirmTitle: "刪除"
                        ) {
                            accountManager.remove(account)
                        }
                    }
                )
                    .padding(2)
            }
        }
    }

    private func tabButton(_ section: Section) -> some View {
        Button {
            selection = section
        } label: {
            HStack(spacing: 4) {
                Image(systemName: section.symbolName)
                    .font(.scaled(.caption))
                Text(section.title)
                    .font(.scaled(.caption))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .foregroundStyle(selection == section ? .primary : .secondary)
            .background(
                selection == section ? AnyShapeStyle(Color(nsColor: .textBackgroundColor)) : AnyShapeStyle(.clear),
                in: RoundedRectangle(cornerRadius: 6)
            )
        }
        .buttonStyle(.plain)
    }
}

extension MenuBarContentView {
    enum Section: Hashable {
        case quota
        case instances
        case settings

        var title: String {
            switch self {
            case .quota: "額度"
            case .instances: "實例"
            case .settings: "設定"
            }
        }

        var symbolName: String {
            switch self {
            case .quota: "gauge.with.dots.needle.50percent"
            case .instances: "square.stack.3d.up"
            case .settings: "gearshape"
            }
        }
    }

    enum Editor: Hashable {
        case account
        case instance(PlatformKind)
    }
}
