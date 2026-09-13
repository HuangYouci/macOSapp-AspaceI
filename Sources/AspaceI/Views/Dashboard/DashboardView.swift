import SwiftUI

struct DashboardView: View {
    @Environment(AccountManager.self) private var accountManager
    @State private var selection = Section.accounts

    var body: some View {
        TabView(selection: $selection) {
            AccountListView()
                .tabItem { Label(String(localized: "Accounts", defaultValue: "帳號"), systemImage: "person.2") }
                .tag(Section.accounts)

            NavigationStack { InstanceListView() }
                .tabItem { Label(String(localized: "Instances", defaultValue: "Instances"), systemImage: "square.stack.3d.up") }
                .tag(Section.instances)

            SettingsView()
                .tabItem { Label(String(localized: "Settings", defaultValue: "設定"), systemImage: "gearshape") }
                .tag(Section.settings)

            AboutView()
                .tabItem { Label(String(localized: "About", defaultValue: "關於"), systemImage: "info.circle") }
                .tag(Section.about)
        }
        .frame(minWidth: 640, minHeight: 460)
        .task {
            accountManager.startAutomaticRefresh()
        }
    }
}

extension DashboardView {
    enum Section: Hashable {
        case accounts
        case instances
        case settings
        case about
    }
}
