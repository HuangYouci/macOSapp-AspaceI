import SwiftUI

struct SettingsView: View {
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(AccountManager.self) private var accountManager
    @State private var exportDocument: AccountExportDocument?
    @State private var confirmsExport = false
    @State private var showsImporter = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            section("一般") {
                row {
                    Text(String(localized: "LaunchAtLogin", defaultValue: "登入時開啟"))
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { settingsManager.launchAtLogin },
                        set: { settingsManager.setLaunchAtLogin($0) }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                }
                if let errorMessage = settingsManager.errorMessage {
                    rowDivider
                    row {
                        Text(errorMessage)
                            .font(.scaled(.caption))
                            .foregroundStyle(.red)
                    }
                }
            }

            section("Menu bar", trailing: "\(settingsManager.menuBarAccountIDs.count)/\(MenuBarQuotaItem.limit)") {
                if accountManager.accounts.isEmpty {
                    row {
                        Text("尚未加入帳號")
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(Array(accountManager.accounts.enumerated()), id: \.element.id) { index, account in
                    if index > 0 { rowDivider }
                    menuBarRow(account)
                }
            }

            section("帳號備份") {
                row {
                    Text("匯入帳號")
                    Spacer()
                    Button("選擇檔案…") { showsImporter = true }
                }
                rowDivider
                row {
                    Text("匯出帳號")
                    Spacer()
                    Button("匯出…") { confirmsExport = true }
                        .disabled(accountManager.accounts.isEmpty)
                }
            }

            section("關於") {
                row {
                    Text("作者")
                    Spacer()
                    Text("Huang Youci")
                        .foregroundStyle(.secondary)
                }
                rowDivider
                row {
                    Text("版本")
                    Spacer()
                    Text("26.9.13")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                if let privacyURL = URL(string: "https://huangyouci.com/privacy") {
                    rowDivider
                    linkRow("隱私政策", url: privacyURL)
                }
                if let termsURL = URL(string: "https://huangyouci.com/terms") {
                    rowDivider
                    linkRow("使用條款", url: termsURL)
                }
            }

            card {
                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    row {
                        Text("結束 AspaceI")
                            .foregroundStyle(.red)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, 4)
        .onAppear {
            settingsManager.refreshLaunchAtLoginStatus()
        }
        .confirmationDialog("匯出檔含登入憑證", isPresented: $confirmsExport) {
            Button("匯出全部帳號") {
                do {
                    exportDocument = AccountExportDocument(data: try accountManager.exportData())
                } catch {
                    accountManager.errorMessage = error.localizedDescription
                }
            }
        }
        .fileExporter(
            isPresented: Binding(get: { exportDocument != nil }, set: { if !$0 { exportDocument = nil } }),
            document: exportDocument,
            contentType: .json,
            defaultFilename: "AspaceI-accounts"
        ) { result in
            if case .failure(let error) = result {
                accountManager.errorMessage = error.localizedDescription
            }
            exportDocument = nil
        }
        .fileImporter(isPresented: $showsImporter, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            Task { await accountManager.importAccounts(from: url) }
        }
    }

    private func menuBarRow(_ account: Account) -> some View {
        let shown = settingsManager.isShownInMenuBar(account.id)
        let enabled = shown || settingsManager.canAddMenuBarAccount
        return Button {
            settingsManager.setMenuBar(account.id, shown: !shown)
        } label: {
            row {
                PlatformBadge(platform: account.platform, size: 22)
                VStack(alignment: .leading, spacing: 0) {
                    Text(account.label)
                        .lineLimit(1)
                    Text(account.platform.displayName)
                        .font(.scaled(.caption))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: shown ? "checkmark.circle.fill" : "circle")
                    .font(.scaled(.title3))
                    .foregroundStyle(shown ? Color.accentColor : Color.secondary.opacity(0.5))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
    }

    private func linkRow(_ title: String, url: URL) -> some View {
        Link(destination: url) {
            row {
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.scaled(.caption))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func section<Content: View>(_ title: String, trailing: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.scaled(.caption, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if let trailing {
                    Text(trailing)
                        .font(.scaled(.caption))
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 6)
            card(content)
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func row<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 10) {
            content()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
    }

    private var rowDivider: some View {
        Divider()
            .padding(.leading, 14)
    }
}
