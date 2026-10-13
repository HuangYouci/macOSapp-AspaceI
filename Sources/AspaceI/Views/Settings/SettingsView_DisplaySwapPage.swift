import SwiftUI

extension SettingsView {
    /// 螢幕互換：每一組是兩個螢幕加一組快捷鍵，按下去兩邊的視窗整批對調。
    struct DisplaySwapPage: View {
        @Environment(DisplaySwapManager.self) private var manager
        let onBack: () -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 18) {
                SettingsForm.pageHeader("螢幕互換", onBack: onBack)

                if !manager.isTrusted {
                    SettingsForm.card {
                        SettingsForm.row {
                            Text("輔助使用權限")
                            Spacer()
                            Text("未允許")
                                .foregroundStyle(.secondary)
                            Button("允許…") { manager.requestTrust() }
                        }
                    }
                }

                ForEach(Array(manager.rules.enumerated()), id: \.element.id) { index, rule in
                    ruleSection(rule, number: index + 1)
                }

                if manager.displays.count < 2 {
                    SettingsForm.card {
                        SettingsForm.row {
                            Text("只接了 \(manager.displays.count) 個螢幕")
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    SettingsForm.card {
                        Button {
                            manager.addRule()
                        } label: {
                            SettingsForm.row {
                                Label("新增組合", systemImage: "plus")
                                    .foregroundStyle(Color.accentColor)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let errorMessage = manager.errorMessage {
                    Text(errorMessage)
                        .font(.scaled(.caption))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 6)
                }
            }
            .padding(.bottom, 4)
            .onAppear {
                manager.refreshDisplays()
                manager.addRuleIfEmpty()
            }
            .onDisappear {
                manager.stopRecording()
            }
            .task {
                // 使用者去系統設定按下允許後沒有通知，畫面開著時每秒看一次。
                while !Task.isCancelled {
                    manager.refreshTrust()
                    try? await Task.sleep(for: .seconds(1))
                }
            }
        }

        private func ruleSection(_ rule: DisplaySwapRule, number: Int) -> some View {
            SettingsForm.section(manager.rules.count > 1 ? "組合 \(number)" : "螢幕") {
                SettingsForm.row {
                    displayPicker(rule.first) { manager.setDisplays(rule.id, first: $0) }
                    Image(systemName: "arrow.left.arrow.right")
                        .foregroundStyle(.secondary)
                    displayPicker(rule.second) { manager.setDisplays(rule.id, second: $0) }
                }
                SettingsForm.divider
                SettingsForm.row {
                    Text("快捷鍵")
                    Spacer()
                    shortcutControl(rule)
                }
                if manager.conflictedRuleIDs.contains(rule.id), let shortcut = rule.shortcut {
                    SettingsForm.row {
                        Text("\(shortcut.displayString) 已被其他 App 使用")
                            .font(.scaled(.caption))
                            .foregroundStyle(.red)
                    }
                }
                SettingsForm.divider
                SettingsForm.row {
                    Button("立即互換") {
                        Task { await manager.swap(rule.id) }
                    }
                    .disabled(manager.isSwapping || rule.first.uuid == rule.second.uuid)
                    Spacer()
                    Button("刪除組合", systemImage: "trash", role: .destructive) {
                        manager.remove(rule.id)
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                }
            }
        }

        private func displayPicker(_ selection: DisplayReference, onChange: @escaping (DisplayReference) -> Void) -> some View {
            Picker("螢幕", selection: Binding(get: { selection.uuid }, set: { uuid in
                if let display = manager.displays.first(where: { $0.uuid == uuid }) {
                    onChange(display.reference)
                }
            })) {
                ForEach(manager.displays, id: \.uuid) { display in
                    Text(display.name).tag(display.uuid)
                }
                if manager.display(for: selection) == nil {
                    Text("\(selection.name) · 未接上").tag(selection.uuid)
                }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity)
        }

        @ViewBuilder
        private func shortcutControl(_ rule: DisplaySwapRule) -> some View {
            if manager.recordingRuleID == rule.id {
                Text("按下快捷鍵 · ⎋ 取消 · ⌫ 清除")
                    .font(.scaled(.callout))
                    .foregroundStyle(Color.accentColor)
                Button("取消") { manager.stopRecording() }
            } else {
                Button(rule.shortcut?.displayString ?? "錄製") {
                    manager.startRecording(rule.id)
                }
                .monospacedDigit()
                if rule.shortcut != nil {
                    Button("清除快捷鍵", systemImage: "xmark.circle.fill") {
                        manager.clearShortcut(rule.id)
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.tertiary)
                }
            }
        }
    }
}
