import SwiftUI

struct MenuBarContentView: View {
    @Environment(AccountManager.self) private var accountManager
    @State private var selection = Section.quota

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 4) {
                tabButton(.quota)
                tabButton(.accounts)
                tabButton(.instances)
                tabButton(.settings)
            }
            .padding(3)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 9))

            Group {
                switch selection {
                case .quota:
                    quotaView
                case .accounts:
                    AccountListView()
                case .instances:
                    NavigationStack { InstanceListView() }
                case .settings:
                    SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 460, height: 560)
        .padding(16)
        .background(.ultraThinMaterial)
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
    }

    private func tabButton(_ section: Section) -> some View {
        Button {
            selection = section
        } label: {
            VStack(spacing: 3) {
                Image(systemName: section.symbolName)
                Text(section.title)
                    .font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .foregroundStyle(selection == section ? .primary : .secondary)
            .background(
                selection == section ? AnyShapeStyle(.background) : AnyShapeStyle(.clear),
                in: RoundedRectangle(cornerRadius: 7)
            )
        }
        .buttonStyle(.plain)
    }
}

extension MenuBarContentView {
    enum Section: Hashable {
        case quota
        case accounts
        case instances
        case settings

        var title: String {
            switch self {
            case .quota: "額度"
            case .accounts: "帳號"
            case .instances: "Instances"
            case .settings: "設定"
            }
        }

        var symbolName: String {
            switch self {
            case .quota: "gauge.with.dots.needle.50percent"
            case .accounts: "person.2"
            case .instances: "square.stack.3d.up"
            case .settings: "gearshape"
            }
        }
    }
}
