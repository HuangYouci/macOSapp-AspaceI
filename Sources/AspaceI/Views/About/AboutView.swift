import SwiftUI

struct AboutView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "gauge.with.dots.needle.50percent")
                .font(.largeTitle)
                .foregroundStyle(.tint)

            Text(String(localized: "AppName", defaultValue: "AspaceI"))
                .font(.title)
                .fontWeight(.semibold)

            Text("版本 26.9.13")
                .foregroundStyle(.secondary)

            Text("Huang Youci")

            HStack(spacing: 20) {
                if let privacyURL = URL(string: "https://huangyouci.com/privacy") {
                    Link("隱私政策", destination: privacyURL)
                }
                if let termsURL = URL(string: "https://huangyouci.com/terms") {
                    Link("使用條款", destination: termsURL)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .navigationTitle(String(localized: "About", defaultValue: "關於"))
    }
}
