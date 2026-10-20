import SwiftUI

/// 任務管理側欄：每個 AI 視窗一張即時縮圖，下面是名稱、額度與重置倒數。點了就切到那個視窗。
struct TaskSidebarView: View {
    struct Item: Identifiable, Equatable {
        let id: CGWindowID
        let platform: PlatformKind
        let name: String
        let quota: [Quota]
        let title: String
    }

    struct Quota: Equatable {
        let title: String
        let remainingPercentage: Int
        let resetsAt: Date?
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
                // 只有這一段每秒重畫，縮圖與選取框不受影響。
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    quota(item.quota, now: context.date)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(item.title)
    }

    @ViewBuilder
    private func quota(_ lines: [Quota], now: Date) -> some View {
        if lines.isEmpty {
            Text("--")
                .font(.scaled(.caption2))
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(lines, id: \.title) { line in
                    HStack(spacing: 4) {
                        Text("\(line.title) \(line.remainingPercentage)%")
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 4)
                        if let resetsAt = line.resetsAt, let countdown = QuotaCountdown.text(until: resetsAt, now: now) {
                            Text(countdown)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .font(.scaled(.caption2))
                    .monospacedDigit()
                    .lineLimit(1)
                }
            }
        }
    }

    private func preview(_ item: Item, isSelected: Bool) -> some View {
        ZStack {
            Color.black.opacity(0.08)
            Preview(platform: item.platform) { thumbnail(item.id) }
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
