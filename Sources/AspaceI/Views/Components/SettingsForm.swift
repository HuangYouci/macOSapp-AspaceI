import SwiftUI

/// 設定頁與它的子頁共用的版面：分組標題、白底卡片、列、分隔線、往下一層的列。
@MainActor
enum SettingsForm {
    static func section<Content: View>(_ title: String, trailing: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.scaled(.caption, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if let trailing {
                    Text(trailing)
                        .font(.scaled(.caption))
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 6)
            card(content)
        }
    }

    static func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    static func row<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 10) {
            content()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
    }

    static var divider: some View {
        Divider()
            .padding(.leading, 14)
    }

    /// 整列可點、尾端帶「>」，點下去進子頁。
    static func navigationRow(_ title: String, value: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            row {
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                if let value {
                    Text(value)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Image(systemName: "chevron.right")
                    .font(.scaled(.caption, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    static func linkRow(_ title: String, value: String? = nil, url: URL) -> some View {
        Link(destination: url) {
            row {
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                if let value {
                    Text(value)
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "arrow.up.right")
                    .font(.scaled(.caption))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// 子頁頂端：返回設定與頁名。
    static func pageHeader(_ title: String, onBack: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            Button(action: onBack) {
                Label("設定", systemImage: "chevron.left")
                    .font(.scaled(.callout))
            }
            .buttonStyle(.borderless)
            Spacer()
        }
        .overlay {
            Text(title)
                .font(.scaled(.headline))
        }
        .padding(.horizontal, 2)
    }
}
