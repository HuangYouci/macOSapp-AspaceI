import Charts
import SwiftUI

/// 本機用量：區間合計、每日（今日為每小時）、模型。資料與區間都由外部注入。
struct UsageView: View {
    let summary: UsageSummary?
    @Binding var range: UsageRange
    @State private var hoveredPeriod: Date?

    private static let valueWidth: CGFloat = 58
    private static let columns = ["輸入", "輸出", "快取", "費用"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("區間", selection: $range) {
                ForEach(UsageRange.allCases) { range in
                    Text(range.title).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            if let summary {
                totals(summary.total, cost: summary.totalCost)
                periodCard(summary)
                modelCard(summary.models)
            } else {
                skeleton
            }
        }
    }

    private func totals(_ tokens: TokenCounts, cost: Double) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(zip(Self.columns, [Self.format(tokens.input), Self.format(tokens.output), Self.format(tokens.cache), Self.formatCost(cost)])), id: \.0) { title, value in
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.scaled(.caption2, weight: .medium))
                        .foregroundStyle(.tertiary)
                    Text(value)
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

    private func periodCard(_ summary: UsageSummary) -> some View {
        VStack(spacing: 0) {
            chart(summary)
                .frame(height: 110)
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 4)
            header(summary.isHourly ? "每小時" : "每日")
            ForEach(Array(summary.periods.reversed().enumerated()), id: \.element.id) { index, period in
                if index > 0 { Divider().padding(.leading, 14) }
                valueRow(title: periodTitle(period.start, hourly: summary.isHourly), platform: nil, tokens: period.tokens, cost: period.tokens.isZero ? nil : period.cost)
            }
        }
        .padding(.bottom, 4)
        .cardStyle()
    }

    private func chart(_ summary: UsageSummary) -> some View {
        let unit: Calendar.Component = summary.isHourly ? .hour : .day
        let hovered = summary.periods.first { $0.start == hoveredPeriod }
        return Chart {
            ForEach(summary.periods) { period in
                BarMark(x: .value("時間", period.start, unit: unit), y: .value("tokens", period.tokens.output))
                    .foregroundStyle(by: .value("種類", "輸出"))
                    .opacity(hovered == nil || hovered?.start == period.start ? 1 : 0.4)
                BarMark(x: .value("時間", period.start, unit: unit), y: .value("tokens", period.tokens.input))
                    .foregroundStyle(by: .value("種類", "輸入"))
                    .opacity(hovered == nil || hovered?.start == period.start ? 1 : 0.4)
            }
            if let hovered {
                RuleMark(x: .value("時間", hovered.start, unit: unit))
                    .foregroundStyle(Color.secondary.opacity(0.25))
                    .annotation(position: .top, spacing: 2, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                        hoverCard(hovered, hourly: summary.isHourly)
                    }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        guard case .active(let location) = phase, let plotFrame = proxy.plotFrame,
                              let date: Date = proxy.value(atX: location.x - geometry[plotFrame].origin.x) else {
                            hoveredPeriod = nil
                            return
                        }
                        hoveredPeriod = summary.periods.last { $0.start <= date }?.start
                    }
            }
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
    }

    private func hoverCard(_ period: UsageSummary.Period, hourly: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(periodTitle(period.start, hourly: hourly))
                .font(.scaled(.caption2, weight: .semibold))
            ForEach(Array(zip(Self.columns, [period.tokens.input.formatted(), period.tokens.output.formatted(), period.tokens.cache.formatted(), Self.formatCost(period.cost)])), id: \.0) { title, value in
                HStack(spacing: 8) {
                    Text(title)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Text(value)
                        .monospacedDigit()
                }
                .font(.scaled(.caption2))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(width: 150)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
    }

    private func modelCard(_ models: [UsageSummary.Model]) -> some View {
        VStack(spacing: 0) {
            header("模型")
            if models.isEmpty {
                Text("沒有用量")
                    .font(.scaled(.caption))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
            }
            ForEach(Array(models.enumerated()), id: \.element.id) { index, model in
                if index > 0 { Divider().padding(.leading, 14) }
                valueRow(title: model.name, platform: model.platform, tokens: model.tokens, cost: model.cost)
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

    private func valueRow(title: String, platform: PlatformKind?, tokens: TokenCounts, cost: Double?) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 7) {
                if let platform {
                    PlatformBadge(platform: platform, size: 16)
                }
                Text(title)
                    .font(.scaled(.subheadline))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(Array([tokens.input, tokens.output, tokens.cache].map { $0 == 0 ? nil : Self.format($0) }.enumerated()) + [(3, cost.map(Self.formatCost))], id: \.0) { _, value in
                Text(value ?? "–")
                    .font(.scaled(.subheadline, weight: .medium, design: .rounded))
                    .foregroundStyle(value == nil ? .quaternary : .primary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(width: Self.valueWidth, alignment: .trailing)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }

    private func periodTitle(_ start: Date, hourly: Bool) -> String {
        hourly
            ? start.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
            : start.formatted(.dateTime.month(.defaultDigits).day().weekday(.abbreviated))
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

    /// 美元：一百以上不帶小數。不用貨幣格式：中文語系會寫成「US$」，欄位放不下。
    static func formatCost(_ value: Double) -> String {
        "$" + value.formatted(.number.grouping(.automatic).precision(.fractionLength(value >= 100 ? 0 : 2)))
    }

    /// 依語系縮寫：中文為「1.52億」，英文為「152M」。
    static func format(_ value: Int) -> String {
        value.formatted(.number.notation(.compactName).precision(.significantDigits(1...3)))
    }
}
