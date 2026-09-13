import SwiftUI

struct SettingsView: View {
    @Environment(SettingsManager.self) private var settingsManager

    var body: some View {
        Form {
            Toggle(
                String(localized: "LaunchAtLogin", defaultValue: "登入時開啟"),
                isOn: Binding(
                    get: { settingsManager.launchAtLogin },
                    set: { settingsManager.setLaunchAtLogin($0) }
                )
            )

            if let errorMessage = settingsManager.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }

            Section("AspaceI") {
                LabeledContent("作者", value: "Huang Youci")
                LabeledContent("版本", value: "26.9.13")
                if let privacyURL = URL(string: "https://huangyouci.com/privacy") {
                    Link("隱私政策", destination: privacyURL)
                }
                if let termsURL = URL(string: "https://huangyouci.com/terms") {
                    Link("使用條款", destination: termsURL)
                }
            }

            Section {
                Button("結束 AspaceI") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(String(localized: "Settings", defaultValue: "設定"))
        .padding()
        .onAppear {
            settingsManager.refreshLaunchAtLoginStatus()
        }
    }
}
