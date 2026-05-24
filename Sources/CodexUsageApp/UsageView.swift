import CodexUsageCore
import SwiftUI

struct UsageView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(model.strings.codexUsageTitle)
                    .font(.headline)
                Spacer()
                Button {
                    model.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help(model.strings.refresh)
            }

            HStack(spacing: 10) {
                metric(title: model.strings.today, summary: model.snapshot.today)
                metric(title: model.strings.thisHour, summary: model.snapshot.currentHour)
            }

            Text(model.strings.recentHours)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(alignment: .bottom, spacing: 3) {
                ForEach(model.snapshot.recentHours) { bucket in
                    Capsule()
                        .fill(Color.accentColor.opacity(0.65))
                        .frame(width: 7, height: barHeight(bucket.summary.totals.totalTokens))
                }
            }
            .frame(height: 36, alignment: .bottom)

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
        .frame(width: 320)
    }

    private func metric(title: String, summary: UsageSummary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(formatTokens(summary.totals.totalTokens))
                .font(.system(size: 22, weight: .semibold, design: .rounded))
            Text(formatCost(summary.cost))
                .font(.caption)
                .foregroundStyle(summary.cost.hasUnknownPricing ? .orange : .secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
    }

    private func barHeight(_ tokens: Int) -> CGFloat {
        max(4, min(34, CGFloat(tokens) / 200))
    }

    private func formatTokens(_ tokens: Int) -> String {
        tokens.formatted(.number.notation(.compactName))
    }

    private func formatCost(_ cost: CostEstimate) -> String {
        guard let usd = cost.usd else {
            return model.strings.unknownPricing
        }

        let value = NSDecimalNumber(decimal: usd).doubleValue
        return "$\(value.formatted(.number.precision(.fractionLength(2))))"
    }
}
