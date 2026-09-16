import SwiftUI

/// 等待確認的動作；由畫面外部建立後交給 `ConfirmationOverlay` 呈現。
struct ConfirmationRequest: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let confirmTitle: String
    var isDestructive: Bool = true
    let action: () -> Void
}

/// MenuBarExtra 的 popup 是非啟用面板，系統對話框（confirmationDialog／alert）會畫出來但收不到點擊，
/// popup 內的二次確認一律用這張蓋在上面的卡片。
struct ConfirmationOverlay: View {
    let request: ConfirmationRequest
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.2)
                .contentShape(Rectangle())
                .onTapGesture { onDismiss() }

            VStack(alignment: .leading, spacing: 8) {
                Text(request.title)
                    .font(.scaled(.headline))
                    .fixedSize(horizontal: false, vertical: true)
                Text(request.message)
                    .font(.scaled(.callout))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Button("取消") { onDismiss() }
                        .buttonStyle(.bordered)
                        .keyboardShortcut(.cancelAction)
                    Button(request.confirmTitle) {
                        onDismiss()
                        request.action()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(request.isDestructive ? .red : .accentColor)
                    .keyboardShortcut(.defaultAction)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.top, 4)
            }
            .padding(16)
            .frame(width: 320, alignment: .leading)
            .cardStyle(cornerRadius: 14)
        }
    }
}
