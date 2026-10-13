import SwiftUI

extension SettingsView {
    /// 任務管理：選一個螢幕，左邊側欄列出所有 AI 視窗，右邊放大選中的那個。
    struct TaskModePage: View {
        @Environment(TaskModeManager.self) private var manager
        let onBack: () -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 18) {
                SettingsForm.pageHeader("任務管理", onBack: onBack)

                SettingsForm.card {
                    SettingsForm.row {
                        Text("開啟")
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { manager.isActive },
                            set: { enabled in Task { enabled ? await manager.activate() : await manager.deactivate() } }
                        ))
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .disabled(manager.isChanging)
                    }
                    SettingsForm.divider
                    SettingsForm.row {
                        Text("螢幕")
                        Spacer()
                        displayPicker
                    }
                    SettingsForm.divider
                    SettingsForm.row {
                        Text("快捷鍵")
                        Spacer()
                        shortcutControl
                    }
                    if manager.shortcutConflicted, let shortcut = manager.shortcut {
                        SettingsForm.row {
                            Text("\(shortcut.displayString) 已被其他 App 使用")
                                .font(.scaled(.caption))
                                .foregroundStyle(.red)
                        }
                    }
                }

                if !manager.isTrusted || !manager.canCaptureScreen {
                    SettingsForm.section("權限") {
                        if !manager.isTrusted {
                            permissionRow("輔助使用權限") { manager.requestTrust() }
                        }
                        if !manager.isTrusted && !manager.canCaptureScreen {
                            SettingsForm.divider
                        }
                        if !manager.canCaptureScreen {
                            permissionRow("螢幕錄製權限") { manager.requestScreenCapture() }
                        }
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
            }
            .onDisappear {
                manager.stopRecording()
            }
            .task {
                // 使用者去系統設定按下允許後沒有通知，畫面開著時每秒看一次。
                while !Task.isCancelled {
                    manager.refreshPermissions()
                    try? await Task.sleep(for: .seconds(1))
                }
            }
        }

        private var displayPicker: some View {
            Picker("螢幕", selection: Binding(
                get: { manager.resolvedDisplay?.uuid ?? "" },
                set: { uuid in
                    if let display = manager.displays.first(where: { $0.uuid == uuid }) {
                        manager.setDisplay(display.reference)
                    }
                }
            )) {
                ForEach(manager.displays, id: \.uuid) { display in
                    Text(display.name).tag(display.uuid)
                }
            }
            .labelsHidden()
            .fixedSize()
            .disabled(manager.isActive)
        }

        @ViewBuilder
        private var shortcutControl: some View {
            if manager.isRecording {
                Text("按下快捷鍵 · ⎋ 取消 · ⌫ 清除")
                    .font(.scaled(.callout))
                    .foregroundStyle(Color.accentColor)
                Button("取消") { manager.stopRecording() }
            } else {
                Button(manager.shortcut?.displayString ?? "錄製") {
                    manager.startRecording()
                }
                .monospacedDigit()
                if manager.shortcut != nil {
                    Button("清除快捷鍵", systemImage: "xmark.circle.fill") {
                        manager.setShortcut(nil)
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.tertiary)
                }
            }
        }

        private func permissionRow(_ title: String, action: @escaping () -> Void) -> some View {
            SettingsForm.row {
                Text(title)
                Spacer()
                Text("未允許")
                    .foregroundStyle(.secondary)
                Button("允許…", action: action)
            }
        }
    }
}
