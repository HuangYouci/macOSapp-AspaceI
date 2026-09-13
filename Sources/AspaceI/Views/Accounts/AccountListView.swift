import SwiftUI
import UniformTypeIdentifiers

struct AccountListView: View {
    @Environment(AccountManager.self) private var accountManager
    @State private var importPlatform = PlatformKind.codex
    @State private var showsImporter = false

    var body: some View {
        NavigationStack {
            List(accountManager.accounts) { account in
                VStack(alignment: .leading, spacing: 4) {
                    Label(account.displayName, systemImage: account.platform.symbolName)
                        .font(.headline)
                    Text(account.planName ?? String(localized: "PlanUnknown", defaultValue: "方案未知"))
                        .foregroundStyle(.secondary)
                    if let error = account.lastError {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
                .padding(.vertical, 4)
                .contextMenu {
                    Button("設為目前帳號") { accountManager.activate(account) }
                    Button("刪除", role: .destructive) { accountManager.remove(account) }
                }
            }
            .overlay {
                if accountManager.accounts.isEmpty {
                    ContentUnavailableView(
                        String(localized: "NoAccounts", defaultValue: "尚未加入帳號"),
                        systemImage: "person.crop.circle.badge.questionmark"
                    )
                }
            }
            .navigationTitle(String(localized: "AccountsTitle", defaultValue: "帳號與額度"))
            .toolbar {
                Button(String(localized: "ImportAccounts", defaultValue: "匯入本機帳號")) {
                    Task {
                        await accountManager.importLocalAccounts()
                    }
                }
                Menu("從檔案加入") {
                    ForEach(PlatformKind.allCases) { platform in
                        Button(platform.displayName) {
                            importPlatform = platform
                            showsImporter = true
                        }
                    }
                }
            }
            .fileImporter(isPresented: $showsImporter, allowedContentTypes: [.data, .json, .yaml], allowsMultipleSelection: false) { result in
                guard case .success(let urls) = result, let url = urls.first else { return }
                Task { await accountManager.importFile(at: url, platform: importPlatform) }
            }
        }
    }
}
