import Charts
import SwiftUI

/// 本機用量：區間合計、每日、模型、帳號。資料與篩選都由外部注入。
struct UsageView: View {
    let summary: UsageSummary?
    @Binding var range: UsageRange
    @Binding var filter: UsageOwnerKey?
    let filterTitle: String?

    private static let valueWidth: CGFloat = 66
    private static let columns = ["輸入", "輸出", "快取"]

    var body: some View {
        VStack(spacing: 10) {
            controls
            if let summary {
                totals(summary.total)
                dailyCard(summary.days)
                tableCard("模型", rows: summary.models, selectable: false)
                tableCard("帳號", rows: summary.owners, selectable: true)
            } else {
                skeleton
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Picker("區間", selection: $range) {
                ForEach(UsageRange.allCases) { range in
                    Text(range.title).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            Spacer(minLength: 4)
            if let filterTitle {
                Button {
                    filter = nil
                } label: {
                    HStack(spacing: 4) {
                        Text(filterTitle)
                            .lineLimit(1)
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .font(.scaled(.caption))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(0.05), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func totals(_ tokens: TokenCounts) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(zip(Self.columns, [tokens.input, tokens.output, tokens.cache])), id: \.0) { title, value in
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.scaled(.caption2, weight: .medium))
                        .foregroundStyle(.tertiary)
                    Text(Self.format(value))
                        .font(.scaled(.title3, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .cardStyle()
    }

    private func dailyCard(_ days: [UsageSummary.Day]) -> some View {
        VStack(spacing: 0) {
            header("每日")
            Chart(days) { day in
                BarMark(x: .value("日", day.day, unit: .day), y: .value("tokens", day.tokens.output))
                    .foregroundStyle(by: .value("種類", "輸出"))
                BarMark(x: .value("日", day.day, unit: .day), y: .value("tokens", day.tokens.input))
                    .foregroundStyle(by: .value("種類", "輸入"))
            }
            .chartForegroundStyleScale(["輸出": Color.accentColor, "輸入": Color.accentColor.opacity(0.35)])
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let number = value.as(Int.self) { Text(Self.format(number)) }
                    }
                }
            }
            .chartLegend(.hidden)
            .frame(height: 110)
            .padding(.horizontal, 14)
            .padding(.bottom, 8)

            ForEach(Array(days.reversed().enumerated()), id: \.element.id) { index, day in
                Divider().padding(.leading, 14)
                valueRow(title: day.day.formatted(.dateTime.month(.defaultDigits).day().weekday(.abbreviated)), platform: nil, tokens: day.tokens, isSelected: false)
            }
        }
        .padding(.bottom, 4)
        .cardStyle()
    }

    private func tableCard(_ title: String, rows: [UsageSummary.Row], selectable: Bool) -> some View {
        VStack(spacing: 0) {
            header(title)
            if rows.isEmpty {
                Text("沒有用量")
                    .font(.scaled(.caption))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
            }
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 { Divider().padding(.leading, 14) }
                if selectable, let platform = row.platform {
                    let key = ownerKey(rowID: row.id, platform: platform)
                    Button {
                        filter = filter == key ? nil : key
                    } label: {
                        valueRow(title: row.title, platform: platform, tokens: row.tokens, isSelected: filter == key)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    valueRow(title: row.title, platform: row.platform, tokens: row.tokens, isSelected: false)
                }
            }
        }
        .padding(.bottom, 4)
        .cardStyle()
    }

    private func header(_ title: String) -> some View {
        HStack(spacing: 0) {
            Text(title)
                .font(.scaled(.caption, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(Self.columns, id: \.self) { column in
                Text(column)
                    .font(.scaled(.caption2, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .frame(width: Self.valueWidth, alignment: .trailing)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 11)
        .padding(.bottom, 6)
    }

    private func valueRow(title: String, platform: PlatformKind?, tokens: TokenCounts, isSelected: Bool) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 7) {
                if let platform {
                    PlatformBadge(platform: platform, size: 16)
                }
                Text(title)
                    .font(.scaled(.subheadline, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(Array([tokens.input, tokens.output, tokens.cache].enumerated()), id: \.offset) { _, value in
                Text(value == 0 ? "–" : Self.format(value))
                    .font(.scaled(.subheadline, weight: .medium, design: .rounded))
                    .foregroundStyle(value == 0 ? .quaternary : .primary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(width: Self.valueWidth, alignment: .trailing)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }

    private var skeleton: some View {
        VStack(spacing: 10) {
            ForEach([56, 200, 120], id: \.self) { height in
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: CGFloat(height))
                    .shimmering(cornerRadius: 12)
            }
        }
    }

    private func ownerKey(rowID: String, platform: PlatformKind) -> UsageOwnerKey {
        let owner = String(rowID.dropFirst(platform.rawValue.count + 1))
        return UsageOwnerKey(platform: platform, owner: owner.isEmpty ? nil : owner)
    }

    /// 依語系縮寫：中文為「1.52億」，英文為「152M」。
    static func format(_ value: Int) -> String {
        value.formatted(.number.notation(.compactName).precision(.significantDigits(1...3)))
    }
}
