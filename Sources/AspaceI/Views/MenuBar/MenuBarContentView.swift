import SwiftUI

struct MenuBarContentView: View {
    @Environment(AccountManager.self) private var accountManager
    @State private var selection = Section.quota

    var body: some View {
        TabView(selection: $selection) {
            quotaView
                .tabItem { Label("額度", systemImage: "gauge.with.dots.needle.50percent") }
                .tag(Section.quota)

            AccountListView()
                .tabItem { Label("帳號", systemImage: "person.2") }
                .tag(Section.accounts)

            NavigationStack { InstanceListView() }
                .tabItem { Label("Instances", systemImage: "square.stack.3d.up") }
                .tag(Section.instances)

            SettingsView()
                .tabItem { Label("設定", systemImage: "gearshape") }
                .tag(Section.settings)
        }
        .frame(width: 460, height: 560)
        .onAppear {
            accountManager.startAutomaticRefresh()
        }
    }

    private var quotaView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("AspaceI")
                    .font(.headline)
                Spacer()
                Button("更新", systemImage: "arrow.clockwise") {
                    Task { await accountManager.refreshAllQuotas() }
                }
                .labelStyle(.iconOnly)
                .disabled(accountManager.isDiscovering)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if accountManager.accounts.isEmpty {
                        ContentUnavailableView("尚未加入帳號", systemImage: "person.crop.circle.badge.questionmark")
                    } else {
                        ForEach(accountManager.accounts) { account in
                            AccountQuotaRow(account: account)
                        }
                    }
                }
            }

            if let errorMessage = accountManager.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding()
    }
}

extension MenuBarContentView {
    enum Section: Hashable {
        case quota
        case accounts
        case instances
        case settings
    }
}
