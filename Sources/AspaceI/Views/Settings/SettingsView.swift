import SwiftUI

struct SettingsView: View {
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(AccountManager.self) private var accountManager
    @Environment(UsageManager.self) private var usageManager
    @Environment(DisplaySwapManager.self) private var displaySwapManager
    @Environment(TaskModeManager.self) private var taskModeManager
    @Environment(BlackoutManager.self) private var blackoutManager
    /// 二次確認交給 popup 外層呈現：MenuBarExtra 的面板收不到系統對話框的點擊。
    let confirm: (ConfirmationRequest) -> Void
    let onOpen: (Page) -> Void
    @State private var exportDocument: AccountExportDocument?
    @State private var showsImporter = false
    @State private var usageExport: AccountExportDocument?

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
                rowDivider
                SettingsForm.navigationRow("螢幕互換", value: displaySwapSummary) { onOpen(.displaySwap) }
                rowDivider
                SettingsForm.navigationRow("任務管理", value: taskModeSummary) { onOpen(.taskMode) }
                rowDivider
                row {
                    Text("螢幕全黑")
                    Spacer()
                    Button("開始") { blackoutManager.start() }
                }
            }

            section("Menu bar") {
                row {
                    Text("額度")
                    Spacer()
                    Picker("額度", selection: Binding(
                        get: { settingsManager.menuBarQuotaMode },
                        set: { settingsManager.setMenuBarQuotaMode($0) }
                    )) {
                        ForEach(MenuBarQuotaMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                rowDivider
                SettingsForm.navigationRow("顯示的帳號", value: "\(settingsManager.menuBarAccountIDs.count)") { onOpen(.menuBarAccounts) }
            }

            section("資料") {
                row {
                    Text("匯入帳號")
                    Spacer()
                    Button("選擇檔案…") { showsImporter = true }
                }
                rowDivider
                row {
                    Text("匯出帳號")
                    Spacer()
                    Button("匯出…") {
                        confirm(ConfirmationRequest(
                            title: "匯出檔含登入憑證",
                            message: "匯出的檔案包含所有帳號的完整登入憑證，拿到檔案的人就能登入這些帳號。",
                            confirmTitle: "匯出全部帳號",
                            isDestructive: false
                        ) {
                            do {
                                exportDocument = AccountExportDocument(data: try accountManager.exportData())
                            } catch {
                                accountManager.errorMessage = error.localizedDescription
                            }
                        })
                    }
                    .disabled(accountManager.accounts.isEmpty)
                }
                rowDivider
                row {
                    Text("匯出用量")
                    Spacer()
                    Button("匯出…") {
                        usageExport = AccountExportDocument(data: Data(UsageExport.csv(usageManager.records, timeZone: .current).utf8))
                    }
                    .disabled(usageManager.records.isEmpty)
                    .fileExporter(
                        isPresented: Binding(get: { usageExport != nil }, set: { if !$0 { usageExport = nil } }),
                        document: usageExport,
                        contentType: .commaSeparatedText,
                        defaultFilename: "AspaceI-usage"
                    ) { result in
                        if case .failure(let error) = result {
                            usageManager.errorMessage = error.localizedDescription
                        }
                        usageExport = nil
                    }
                }
            }

            SettingsForm.card {
                SettingsForm.navigationRow("關於", value: Self.version) { onOpen(.about) }
            }

            SettingsForm.card {
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

    /// 只有一組時直接顯示它的快捷鍵，多組時顯示組數。
    private var displaySwapSummary: String? {
        switch displaySwapManager.rules.count {
        case 0: nil
        case 1: displaySwapManager.rules.first?.shortcut?.displayString
        default: "\(displaySwapManager.rules.count)"
        }
    }

    private var taskModeSummary: String? {
        taskModeManager.isActive ? "開啟中" : taskModeManager.shortcut?.displayString
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        SettingsForm.section(title, content: content)
    }

    private func row<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        SettingsForm.row(content)
    }

    private var rowDivider: some View {
        SettingsForm.divider
    }
}

extension SettingsView {
    static let version = "26.10.27"

    /// 設定的子頁，由 popup 外層負責切換，進出子頁時捲動位置從頂端開始。
    enum Page: Hashable {
        case displaySwap
        case taskMode
        case menuBarAccounts
        case about
    }
}
