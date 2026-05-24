import CodexUsageCore
import SwiftUI

struct UsageView: View {
    @Bindable var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("CodexUsage.showTrend") private var showsTrend = false
    @State private var trendMode: TrendMode = .hours

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.strings.codexUsageTitle)
                            .font(.headline)
                        Text("\(model.strings.lastUpdated): \(formatRefreshTime(model.snapshot.generatedAt))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        model.refresh()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help(model.strings.refresh)
                }

                Toggle(model.strings.alwaysOnTop, isOn: $model.isAlwaysOnTop)
                    .toggleStyle(.checkbox)
                    .font(.caption)

                HStack(spacing: 10) {
                    metric(title: model.strings.today, summary: model.snapshot.today)
                    metric(title: model.strings.thisHour, summary: model.snapshot.currentHour)
                }

                Text(model.strings.recentHours)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                let maxHourTokens = model.snapshot.recentHours.map(\.summary.totals.totalTokens).max() ?? 0
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(model.snapshot.recentHours) { bucket in
                        Capsule()
                            .fill(Color.accentColor.opacity(0.65))
                            .frame(width: 7, height: barHeight(bucket.summary.totals.totalTokens, maxTokens: maxHourTokens))
                    }
                }
                .frame(height: 36, alignment: .bottom)

                trendSection

                if let first = model.snapshot.modelBreakdown.first {
                    Text("\(model.strings.models): \(first.model)")
                        .font(.caption)
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }

                Text(model.statusMessage)
                    .font(.caption2)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
        }
        .frame(width: 360)
        .background(panelBackground)
        .clipShape(panelShape)
        .overlay(
            panelShape
                .stroke(panelBorderColor, lineWidth: 1)
        )
        .shadow(color: panelShadowColor, radius: 22, x: 0, y: 12)
        .padding(10)
    }

    private func metric(title: String, summary: UsageSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 6)
                Text(formatCost(summary.cost))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(costNeedsDisclosure(summary.cost) ? .orange : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            Text(formatTokens(summary.totals.totalTokens))
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            VStack(alignment: .leading, spacing: 3) {
                tokenBreakdownRow(label: model.strings.inputShort, value: formatTokens(summary.totals.inputTokens))
                tokenBreakdownRow(label: model.strings.cachedShort, value: formatTokens(summary.totals.cachedInputTokens))
                tokenBreakdownRow(label: model.strings.outputShort, value: formatTokens(summary.totals.outputTokens))
                if summary.totals.reasoningTokens > 0 {
                    tokenBreakdownRow(label: model.strings.reasoningShort, value: formatTokens(summary.totals.reasoningTokens))
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
        .padding(12)
        .background(cardFill, in: RoundedRectangle(cornerRadius: 8))
    }

    private var trendSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle(model.strings.showTrend, isOn: $showsTrend)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                Spacer()

                if showsTrend {
                    Picker(model.strings.usageTrend, selection: $trendMode) {
                        Text(model.strings.last24Hours).tag(TrendMode.hours)
                        Text(model.strings.last7Days).tag(TrendMode.days)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 138)
                }
            }

            if showsTrend {
                trendTable(rows: trendRows)
            }
        }
    }

    private var trendRows: [TrendRow] {
        switch trendMode {
        case .hours:
            return model.snapshot.recentHours.reversed().map {
                TrendRow(
                    id: $0.start,
                    period: $0.start.formatted(date: .omitted, time: .shortened),
                    summary: $0.summary
                )
            }
        case .days:
            return model.snapshot.recentDays.reversed().map {
                TrendRow(
                    id: $0.start,
                    period: $0.start.formatted(.dateTime.month(.twoDigits).day(.twoDigits)),
                    summary: $0.summary
                )
            }
        }
    }

    private func trendTable(rows: [TrendRow]) -> some View {
        VStack(spacing: 0) {
            trendHeader
            ScrollView {
                LazyVStack(spacing: 0) {
                    let maxTokens = rows.map(\.summary.totals.totalTokens).max() ?? 0
                    ForEach(rows) { row in
                        trendRow(row, maxTokens: maxTokens)
                    }
                }
            }
            .frame(height: 154)
            .scrollIndicators(.hidden)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.quaternary, lineWidth: 1)
        )
    }

    private var trendHeader: some View {
        HStack(spacing: 8) {
            Text(model.strings.period)
                .frame(width: 52, alignment: .leading)
            Text(model.strings.tokens)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(model.strings.cost)
                .frame(width: 78, alignment: .trailing)
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(tableHeaderFill)
    }

    private func trendRow(_ row: TrendRow, maxTokens: Int) -> some View {
        HStack(spacing: 8) {
            Text(row.period)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(formatTokens(row.summary.totals.totalTokens))
                    .font(.caption2.weight(.medium))
                GeometryReader { proxy in
                    Capsule()
                        .fill(Color.accentColor.opacity(0.64))
                        .frame(width: barWidth(row.summary.totals.totalTokens, maxTokens: maxTokens, maxWidth: proxy.size.width), height: 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(formatCost(row.summary.cost))
                .font(.caption2)
                .foregroundStyle(costNeedsDisclosure(row.summary.cost) ? .orange : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(width: 78, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private func barHeight(_ tokens: Int, maxTokens: Int) -> CGFloat {
        guard maxTokens > 0 else {
            return 4
        }
        return max(4, min(34, CGFloat(tokens) / CGFloat(maxTokens) * 34))
    }

    private func barWidth(_ tokens: Int, maxTokens: Int, maxWidth: CGFloat) -> CGFloat {
        guard maxTokens > 0 else {
            return 0
        }
        return max(3, CGFloat(tokens) / CGFloat(maxTokens) * maxWidth)
    }

    private func formatTokens(_ tokens: Int) -> String {
        tokens.formatted(.number.notation(.compactName))
    }

    private func tokenBreakdownRow(label: String, value: String) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(value)
                .fontWeight(.medium)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .font(.caption2)
    }

    private var panelShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
    }

    private var panelBackground: some View {
        ZStack {
            panelShape
                .fill(.regularMaterial)
                .opacity(model.panelOpacity)
            panelShape
                .fill(panelTint)
        }
    }

    private var panelTint: Color {
        if colorScheme == .dark {
            return Color.black.opacity((1 - model.panelOpacity) * 0.28)
        }
        return Color.white.opacity((1 - model.panelOpacity) * 0.34)
    }

    private var cardFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
    }

    private var tableHeaderFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.045)
    }

    private var panelBorderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.18) : Color.black.opacity(0.10)
    }

    private var panelShadowColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.40) : Color.black.opacity(0.18)
    }

    private func formatCost(_ cost: CostEstimate) -> String {
        guard let usd = cost.usd else {
            return model.strings.unknownPricing
        }

        let value = NSDecimalNumber(decimal: usd).doubleValue
        let base = "$\(value.formatted(.number.precision(.fractionLength(2))))"
        let suffixes = costDisclosureSuffixes(cost)
        guard !suffixes.isEmpty else {
            return base
        }

        return "\(base) · \(suffixes.joined(separator: "/"))"
    }

    private func costNeedsDisclosure(_ cost: CostEstimate) -> Bool {
        cost.hasUnknownPricing || cost.usedFallbackMultiplier
    }

    private func costDisclosureSuffixes(_ cost: CostEstimate) -> [String] {
        var suffixes: [String] = []
        if cost.hasUnknownPricing {
            suffixes.append(model.strings.partialPricing)
        }
        if cost.usedFallbackMultiplier {
            suffixes.append(model.strings.fallbackPricing)
        }
        return suffixes
    }

    private func formatRefreshTime(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}

private enum TrendMode {
    case hours
    case days
}

private struct TrendRow: Identifiable {
    let id: Date
    let period: String
    let summary: UsageSummary
}
