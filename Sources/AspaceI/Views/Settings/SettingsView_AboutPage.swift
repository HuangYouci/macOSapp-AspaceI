import SwiftUI

extension SettingsView {
    struct AboutPage: View {
        let onBack: () -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 18) {
                SettingsForm.pageHeader("關於", onBack: onBack)
                SettingsForm.card {
                    SettingsForm.row {
                        Text("作者")
                        Spacer()
                        Text("Huang Youci")
                            .foregroundStyle(.secondary)
                    }
                    SettingsForm.divider
                    SettingsForm.row {
                        Text("版本")
                        Spacer()
                        Text(SettingsView.version)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    if let source = URL(string: UsagePricing.bundled.table.source) {
                        SettingsForm.divider
                        SettingsForm.linkRow("價格表", value: "LiteLLM · \(UsagePricing.bundled.table.fetchedAt)", url: source)
                    }
                    if let privacyURL = URL(string: "https://huangyouci.com/privacy") {
                        SettingsForm.divider
                        SettingsForm.linkRow("隱私政策", url: privacyURL)
                    }
                    if let termsURL = URL(string: "https://huangyouci.com/terms") {
                        SettingsForm.divider
                        SettingsForm.linkRow("使用條款", url: termsURL)
                    }
                }
            }
            .padding(.bottom, 4)
        }
    }
}
