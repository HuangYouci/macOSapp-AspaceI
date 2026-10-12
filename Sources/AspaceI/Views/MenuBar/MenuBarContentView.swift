import SwiftUI

struct MenuBarContentView: View {
    @Environment(AccountManager.self) private var accountManager
    @Environment(InstanceManager.self) private var instanceManager
    @Environment(AccountLoginManager.self) private var loginManager
    @Environment(UsageManager.self) private var usageManager
    @State private var selection = Section.quota
    @State private var editor: Editor?
    @State private var confirmation: ConfirmationRequest?
    @State private var usageRange = UsageRange.today

    /// popup 四周的留白。留白放在捲動區裡面，捲動區本身貼齊 popup 四邊，邊緣也捲得到。
    private static let inset: CGFloat = 14

    var body: some View {
        page
            .popupBar(edge: .top) {
                if editor == nil {
                    header
                        .padding(.horizontal, Self.inset)
                        .padding(.top, Self.inset)
                        .padding(.bottom, 2)
                }
            }
            .popupBar(edge: .bottom) {
                if let errorMessage = accountManager.errorMessage ?? instanceManager.errorMessage {
                    Text(errorMessage)
                        .font(.scaled(.caption2))
                        .foregroundStyle(.red)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Self.inset)
                        .padding(.vertical, 8)
                }
            }
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

    /// 每一頁各自一個捲動區，切頁時從頂端開始，不沿用上一頁捲到的位置。
    @ViewBuilder
    private var page: some View {
        switch editor {
        case .account:
            scrollPage { AccountEditorView { editor = nil } }
        case .instance(let platform):
            scrollPage { InstanceEditorView(platform: platform) { editor = nil } }
        case nil:
            switch selection {
            case .quota:
                scrollPage { quotaView }
            case .usage:
                scrollPage { usageView }
            case .instances:
                scrollPage { InstanceListView(onAdd: { editor = .instance($0) }, confirm: { confirmation = $0 }) }
            case .settings:
                scrollPage { SettingsView(confirm: { confirmation = $0 }) }
            }
        }
    }

    private func scrollPage<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView {
            content()
                .padding(Self.inset)
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            HStack(spacing: 2) {
                tabButton(.quota)
                tabButton(.usage)
                tabButton(.instances)
                tabButton(.settings)
            }
            .padding(2)
            .background(Color.black.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))

            Spacer(minLength: 4)

            // 內容會捲到列底下，按鈕要有底才看得出是按鈕；樣式與分頁那組一致。
            if selection != .settings {
                HStack(spacing: 2) {
                    actions
                }
                .padding(2)
                .background(Color.black.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch selection {
        case .quota:
            // 一輪要跑完所有帳號約數秒，期間按鈕是停用的。沒有進行中的訊號時，圖示只是變灰再變回來，
            // 百分比與「更新於」又常常原封不動，按下去看起來就像沒有反應。
            refreshButton(isBusy: accountManager.isRefreshing) {
                Task { await accountManager.refreshAllQuotas() }
            }
            headerButton("加入帳號", systemImage: "plus") { editor = .account }
        case .usage:
            refreshButton(isBusy: usageManager.isScanning) {
                Task { await usageManager.refresh(instances: instanceManager) }
            }
        case .instances:
            refreshButton(isBusy: instanceManager.isRefreshingRunning) {
                Task { await instanceManager.refreshRunning() }
            }
        case .settings:
            EmptyView()
        }
    }

    private func refreshButton(isBusy: Bool, action: @escaping () -> Void) -> some View {
        headerButton("更新", systemImage: "arrow.clockwise", action: action)
            .symbolEffect(.rotate, options: .repeating, isActive: isBusy)
            .disabled(isBusy)
    }

    private func headerButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(title, systemImage: systemImage, action: action)
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .frame(width: 28, height: 24)
            .contentShape(Rectangle())
    }

    private var usageView: some View {
        UsageView(
            summary: usageManager.hasScanned ? UsageSummary(records: usageManager.records, range: usageRange, now: Date(), calendar: .current) : nil,
            range: $usageRange
        )
    }

    @ViewBuilder
    private var quotaView: some View {
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
        case usage
        case instances
        case settings

        var title: String {
            switch self {
            case .quota: "額度"
            case .usage: "用量"
            case .instances: "實例"
            case .settings: "設定"
            }
        }

        var symbolName: String {
            switch self {
            case .quota: "gauge.with.dots.needle.50percent"
            case .usage: "chart.bar"
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
