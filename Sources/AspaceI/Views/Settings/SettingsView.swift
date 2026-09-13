import SwiftUI

struct SettingsView: View {
    @Environment(SettingsManager.self) private var settingsManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("設定")
                    .font(.headline)

                Toggle(
                    String(localized: "LaunchAtLogin", defaultValue: "登入時開啟"),
                    isOn: Binding(
                        get: { settingsManager.launchAtLogin },
                        set: { settingsManager.setLaunchAtLogin($0) }
                    )
                )
                .toggleStyle(.switch)
                .padding(12)
                .background(.quaternary.opacity(0.65), in: RoundedRectangle(cornerRadius: 12))

                if let errorMessage = settingsManager.errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }

                VStack(spacing: 0) {
                    LabeledContent("作者", value: "Huang Youci")
                        .padding(.vertical, 9)
                    Divider()
                    LabeledContent("版本", value: "26.9.13")
                        .padding(.vertical, 9)
                    Divider()
                    if let privacyURL = URL(string: "https://huangyouci.com/privacy") {
                        Link("隱私政策", destination: privacyURL)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 9)
                    }
                    Divider()
                    if let termsURL = URL(string: "https://huangyouci.com/terms") {
                        Link("使用條款", destination: termsURL)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 9)
                    }
                }
                .padding(.horizontal, 12)
                .background(.quaternary.opacity(0.65), in: RoundedRectangle(cornerRadius: 12))

                Button("結束 AspaceI") {
                    NSApplication.shared.terminate(nil)
                }
                .foregroundStyle(.red)
            }
        }
        .onAppear {
            settingsManager.refreshLaunchAtLoginStatus()
        }
    }
}
