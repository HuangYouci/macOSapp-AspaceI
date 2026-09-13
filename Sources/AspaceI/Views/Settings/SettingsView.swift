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
        }
        .formStyle(.grouped)
        .navigationTitle(String(localized: "Settings", defaultValue: "設定"))
        .padding()
        .onAppear {
            settingsManager.refreshLaunchAtLoginStatus()
        }
    }
}
