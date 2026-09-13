import SwiftUI

struct InstanceEditorView: View {
    @Environment(InstanceManager.self) private var instanceManager
    @Environment(AccountManager.self) private var accountManager
    let platform: PlatformKind
    let onDone: () -> Void
    @State private var name = ""
    @State private var accountID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                PlatformBadge(platform: platform, size: 24)
                Text("新增 \(platform.clientName) 實例")
                    .font(.scaled(.headline))
                Spacer()
                Button("關閉", systemImage: "xmark", action: onDone)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
            }

            TextField("名稱", text: $name)
                .textFieldStyle(.roundedBorder)

            if platform.supportsAccountBinding(isDefault: false) {
                Picker("帳號", selection: $accountID) {
                    Text("不綁定").tag(UUID?.none)
                    ForEach(accountManager.accounts.filter { $0.platform == platform }) { account in
                        Text(account.label).tag(Optional(account.id))
                    }
                }
            }

            HStack {
                Spacer()
                Button("取消", action: onDone)
                Button("建立") {
                    instanceManager.add(name: name.trimmingCharacters(in: .whitespaces), platform: platform, accountID: accountID)
                    onDone()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .onAppear {
            let existing = instanceManager.instances.filter { $0.platform == platform }.count
            name = "\(platform.clientName) \(existing + 2)"
            accountID = accountManager.accounts.first { $0.platform == platform && $0.isActive }?.id
        }
    }
}
