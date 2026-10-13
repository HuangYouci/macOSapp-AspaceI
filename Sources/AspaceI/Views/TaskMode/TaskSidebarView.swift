import SwiftUI

/// 任務管理側欄：每個 AI 視窗一張即時縮圖，下面是名稱與額度。點了就切到那個視窗。
struct TaskSidebarView: View {
    struct Item: Identifiable, Equatable {
        let id: CGWindowID
        let platform: PlatformKind
        let name: String
        let quota: String
        let title: String
    }

    let items: [Item]
    let selectedID: CGWindowID?
    let thumbnail: (CGWindowID) -> CGImage?
    let onSelect: (CGWindowID) -> Void
    let onExit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("任務管理")
                    .font(.scaled(.caption, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("結束任務管理", systemImage: "xmark", action: onExit)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 4)

            if items.isEmpty {
                Text("沒有開著的 AI 視窗")
                    .font(.scaled(.caption))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(items) { item in
                            row(item)
                        }
                    }
                    .padding(10)
                }
            }
        }
    }

    private func row(_ item: Item) -> some View {
        let isSelected = item.id == selectedID
        return Button {
            onSelect(item.id)
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                preview(item, isSelected: isSelected)
                HStack(spacing: 5) {
                    PlatformBadge(platform: item.platform, size: 14)
                    Text(item.name)
                        .font(.scaled(.caption, weight: .semibold))
                        .lineLimit(1)
                }
                Text(item.quota)
                    .font(.scaled(.caption2))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(item.title)
    }

    private func preview(_ item: Item, isSelected: Bool) -> some View {
        ZStack {
            Color.black.opacity(0.08)
            if let image = thumbnail(item.id) {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                PlatformBadge(platform: item.platform, size: 28)
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(16 / 10, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2.5)
        }
    }
}
