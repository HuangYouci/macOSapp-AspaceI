import SwiftUI
import UniformTypeIdentifiers

struct AccountListView: View {
    @Environment(AccountManager.self) private var accountManager
    @State private var importPlatform = PlatformKind.codex
    @State private var showsImporter = false
    @State private var credentialName = ""
    @State private var credentialValue = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if accountManager.accounts.isEmpty {
                        ContentUnavailableView(
                            String(localized: "NoAccounts", defaultValue: "尚未加入帳號"),
                            systemImage: "person.crop.circle.badge.questionmark"
                        )
                    }

                    ForEach(accountManager.accounts) { account in
                        AccountQuotaRow(account: account)
                            .contextMenu {
                                Button("設為目前帳號") { accountManager.activate(account) }
                                Button("套用至官方客戶端") { accountManager.applyToDefaultClient(account) }
                                Button("刪除", role: .destructive) { accountManager.remove(account) }
                            }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("加入憑證")
                            .font(.subheadline.weight(.semibold))
                        Picker("平台", selection: $importPlatform) {
                            ForEach(PlatformKind.allCases) { platform in
                                Text(platform.displayName)
                                    .tag(platform)
                            }
                        }
                        .pickerStyle(.segmented)
                        TextField("帳號名稱", text: $credentialName)
                        SecureField("Token 或 JSON", text: $credentialValue)
                        Button("加入") {
                            Task {
                                await accountManager.addCredential(
                                    platform: importPlatform,
                                    displayName: credentialName,
                                    value: credentialValue
                                )
                                credentialName = ""
                                credentialValue = ""
                            }
                        }
                        .disabled(credentialValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(12)
                    .background(.quaternary.opacity(0.65), in: RoundedRectangle(cornerRadius: 12))
                }
                .padding(.vertical, 4)
            }
            .navigationTitle(String(localized: "AccountsTitle", defaultValue: "帳號"))
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
