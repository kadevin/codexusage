import AppKit
import Charts
import CodexUsageCore
import SwiftUI

struct UsageView: View {
    @Bindable var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("CodexUsage.showTrend") private var showsTrend = false
    @State private var trendMode: TrendMode = .hours
    @State private var selectedDayStart: Date?
    @State private var hoveredRecentHourStart: Date?
    @State private var hoveredTrendRowID: Date?
    let onContentHeightChanged: ((CGFloat) -> Void)?

    init(model: AppModel, onContentHeightChanged: ((CGFloat) -> Void)? = nil) {
        self.model = model
        self.onContentHeightChanged = onContentHeightChanged
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.strings.codexUsageTitle)
                            .font(.headline)
                        Text("\(model.strings.lastUpdated): \(formatRefreshTime(model.snapshot.generatedAt))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .panelDragArea()
                    .frame(maxWidth: .infinity, alignment: .leading)

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

                officialQuotaSection
                    .panelDragArea()

                Text(model.strings.localEstimate)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .panelDragArea()

                HStack(spacing: 10) {
                    metric(title: model.strings.today, summary: model.snapshot.today)
                    metric(title: model.strings.thisHour, summary: model.snapshot.currentHour)
                }
                .panelDragArea()

                recentHoursChart

                trendSection

                if let first = model.snapshot.modelBreakdown.first {
                    Text("\(model.strings.primaryModelToday): \(first.model)")
                        .font(.caption)
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                        .panelDragArea()
                }

                Text(model.statusMessage)
                    .font(.caption2)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
                    .panelDragArea()
            }
            .padding(14)
            .fixedSize(horizontal: false, vertical: true)
            .background(
                WindowDragHandle()
                    .accessibilityHidden(true)
            )
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: UsageContentHeightKey.self, value: proxy.size.height)
                }
            )
        }
        .frame(width: 360)
        .background(panelBackground)
        .clipShape(panelShape)
        .overlay(
            panelShape
                .stroke(panelBorderColor, lineWidth: 1)
        )
        .onPreferenceChange(UsageContentHeightKey.self) { height in
            DispatchQueue.main.async {
                onContentHeightChanged?(height)
            }
        }
        .onChange(of: showsTrend) { _, isVisible in
            if !isVisible {
                selectedDayStart = nil
            }
        }
        .onChange(of: trendMode) { _, _ in
            selectedDayStart = nil
        }
    }

    @ViewBuilder
    private var officialQuotaSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(model.strings.officialQuota)
                    .font(.caption.weight(.semibold))
                Spacer()
                if let officialUsage = model.officialUsage,
                   officialUsage.resetCreditsAvailable > 0 {
                    Label(
                        "\(officialUsage.resetCreditsAvailable)",
                        systemImage: "arrow.counterclockwise.circle"
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .help(model.strings.resetCredits)
                }
            }

            if let officialUsage = model.officialUsage, !officialUsage.limits.isEmpty {
                ForEach(Array(officialUsage.limits.enumerated()), id: \.element.id) { index, limit in
                    if index > 0 {
                        Divider()
                    }
                    officialLimit(limit)
                }
            } else {
                HStack(spacing: 6) {
                    Image(systemName: model.isOfficialUsageUnavailable ? "exclamationmark.circle" : "clock")
                    Text(
                        model.isOfficialUsageUnavailable
                            ? model.strings.officialQuotaUnavailable
                            : model.strings.loading
                    )
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func officialLimit(_ limit: OfficialUsageLimit) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(limit.name ?? model.strings.codexUsageTitle)
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
                Spacer(minLength: 6)
                if let planType = limit.planType, !planType.isEmpty {
                    Text(planType.uppercased())
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            ForEach(Array(limit.windows.enumerated()), id: \.offset) { _, window in
                officialWindow(window)
            }
        }
    }

    private func officialWindow(_ window: OfficialUsageWindow) -> some View {
        let usedPercent = min(max(window.usedPercent, 0), 100)
        let remainingPercent = window.remainingPercent

        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text(model.strings.quotaWindowLabel(minutes: window.durationMinutes))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: 54, alignment: .leading)

                QuotaProgressBar(
                    progress: Double(remainingPercent) / 100,
                    tint: quotaTint(forRemainingPercent: remainingPercent)
                )

                Text(model.strings.remainingPercentLabel(remainingPercent))
                    .font(.caption2.weight(.medium))
                    .monospacedDigit()
                    .frame(width: 86, alignment: .trailing)
            }

            HStack(spacing: 6) {
                Text(model.strings.usedPercentLabel(usedPercent))
                if let resetsAt = window.resetsAt {
                    Text("\(model.strings.resets) \(resetsAt.formatted(.relative(presentation: .named)))")
                }
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func quotaTint(forRemainingPercent remainingPercent: Int) -> Color {
        switch remainingPercent {
        case ...10:
            return .red
        case ...30:
            return .orange
        default:
            return .accentColor
        }
    }

    private var recentHoursChart: some View {
        let hours = model.snapshot.recentHours
        let hoveredIndex = hoveredRecentHourStart.flatMap { start in
            hours.firstIndex { $0.start == start }
        }
        let hoveredHour = hoveredIndex.map { hours[$0] }
        let maxTokens = hours.map(\.summary.totals.totalTokens).max() ?? 0

        return VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(model.strings.recentHours)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                if let hoveredHour {
                    Text(
                        "\(hoveredHour.start.formatted(date: .omitted, time: .shortened))  "
                            + formatExactTokens(hoveredHour.summary.totals.totalTokens)
                    )
                    .font(.caption2.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                }
            }
            .panelDragArea()

            Chart {
                ForEach(Array(hours.enumerated()), id: \.element.id) { index, bucket in
                    LineMark(
                        x: .value("Hour", index),
                        y: .value("Tokens", bucket.summary.totals.totalTokens)
                    )
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(Color.accentColor)
                }

                if let hoveredIndex, let hoveredHour {
                    RuleMark(x: .value("Selected hour", hoveredIndex))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .foregroundStyle(Color.secondary.opacity(0.45))
                    PointMark(
                        x: .value("Selected hour", hoveredIndex),
                        y: .value("Selected tokens", hoveredHour.summary.totals.totalTokens)
                    )
                    .symbolSize(30)
                    .foregroundStyle(Color.accentColor)
                }
            }
            .chartXScale(domain: 0...max(hours.count - 1, 1))
            .chartYScale(domain: 0...max(maxTokens, 1))
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    if let plotFrame = proxy.plotFrame {
                        let frame = geometry[plotFrame]
                        ChartHoverDragSurface(pointCount: hours.count) { index in
                            hoveredRecentHourStart = index.map { hours[$0].start }
                        }
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                    }
                }
            }
            .frame(height: 58)
            .accessibilityLabel(model.strings.recentHours)
        }
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
                tokenBreakdownRow(label: model.strings.calls, value: formatCallCount(summary.callCount))
                tokenBreakdownRow(label: model.strings.cacheRate, value: formatCacheRate(summary.totals.cacheRate))
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
                    summary: $0.summary,
                    day: nil
                )
            }
        case .days:
            return model.snapshot.recentDays.reversed().map {
                TrendRow(
                    id: $0.start,
                    period: $0.start.formatted(.dateTime.month(.twoDigits).day(.twoDigits)),
                    summary: $0.summary,
                    day: $0
                )
            }
        }
    }

    private func trendTable(rows: [TrendRow]) -> some View {
        VStack(spacing: 0) {
            trendHeader
                .panelDragArea()
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    let maxTokens = rows.map(\.summary.totals.totalTokens).max() ?? 0
                    ForEach(rows) { row in
                        trendRow(row, maxTokens: maxTokens)
                    }
                }
            }
            .frame(height: 154)
        }
        .background(
            WindowDragHandle()
                .accessibilityHidden(true)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.quaternary, lineWidth: 1)
        )
        .popover(item: selectedDayBinding, arrowEdge: .trailing) { day in
            dayDetailPopover(day)
        }
    }

    private var trendHeader: some View {
        HStack(spacing: 6) {
            Text(model.strings.period)
                .frame(width: 42, alignment: .leading)
            Text(model.strings.tokens)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(model.strings.cacheRate)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(width: 44, alignment: .trailing)
            Text(model.strings.calls)
                .frame(width: 34, alignment: .trailing)
            Text(model.strings.cost)
                .frame(width: 60, alignment: .trailing)
            Color.clear
                .frame(width: 8, height: 1)
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(tableHeaderFill)
    }

    @ViewBuilder
    private func trendRow(_ row: TrendRow, maxTokens: Int) -> some View {
        if let day = row.day {
            Button {
                selectedDayStart = day.start
            } label: {
                trendRowContent(row, maxTokens: maxTokens)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .background(
                hoveredTrendRowID == row.id
                    ? Color.accentColor.opacity(0.08)
                    : Color.clear
            )
            .onHover { isHovered in
                hoveredTrendRowID = isHovered ? row.id : nil
            }
            .help(model.strings.viewDayDetails)
            .accessibilityLabel("\(row.period), \(model.strings.viewDayDetails)")
        } else {
            trendRowContent(row, maxTokens: maxTokens)
                .panelDragArea()
        }
    }

    private func trendRowContent(_ row: TrendRow, maxTokens: Int) -> some View {
        HStack(spacing: 6) {
            Text(row.period)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 42, alignment: .leading)

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

            Text(formatCacheRate(row.summary.totals.cacheRate))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(width: 44, alignment: .trailing)

            Text(formatCallCount(row.summary.callCount))
                .font(.caption2)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(width: 34, alignment: .trailing)

            Text(formatCost(row.summary.cost, includesUnit: false))
                .font(.caption2)
                .foregroundStyle(costNeedsDisclosure(row.summary.cost) ? .orange : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(width: 60, alignment: .trailing)

            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
                .frame(width: 8)
                .opacity(row.day == nil ? 0 : 1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
    }

    private var selectedDayBinding: Binding<DayBucket?> {
        Binding(
            get: {
                guard let selectedDayStart else {
                    return nil
                }
                return model.snapshot.recentDays.first { $0.start == selectedDayStart }
            },
            set: { selectedDayStart = $0?.start }
        )
    }

    private func dayDetailPopover(_ day: DayBucket) -> some View {
        let maxHourTokens = day.hourlyBreakdown.map(\.summary.totals.totalTokens).max() ?? 0

        return ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(day.start.formatted(.dateTime.year().month(.wide).day()))
                        .font(.headline)
                    Text(model.strings.tokenDetails)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(formatExactTokens(day.summary.totals.totalTokens))
                        .font(.title2.weight(.semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 8)
                    Text(formatCost(day.summary.cost))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(costNeedsDisclosure(day.summary.cost) ? .orange : .secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }

                VStack(spacing: 5) {
                    detailTokenRow(label: model.strings.inputShort, tokens: day.summary.totals.inputTokens)
                    detailTokenRow(label: model.strings.cachedShort, tokens: day.summary.totals.cachedInputTokens)
                    detailTokenRow(label: model.strings.outputShort, tokens: day.summary.totals.outputTokens)
                    detailTokenRow(label: model.strings.reasoningShort, tokens: day.summary.totals.reasoningTokens)
                    detailTokenRow(label: model.strings.calls, tokens: day.summary.callCount)
                    detailValueRow(
                        label: model.strings.cacheRate,
                        value: formatCacheRate(day.summary.totals.cacheRate)
                    )
                }

                Divider()

                Text(model.strings.hourlyBreakdown)
                    .font(.caption.weight(.semibold))
                detailHeader(first: model.strings.period)
                VStack(spacing: 0) {
                    ForEach(day.hourlyBreakdown.reversed()) { hour in
                        detailHourRow(hour, maxTokens: maxHourTokens)
                    }
                }

                Divider()

                Text(model.strings.modelBreakdown)
                    .font(.caption.weight(.semibold))
                if day.modelBreakdown.isEmpty {
                    Text(model.strings.noModelUsage)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    detailHeader(first: model.strings.models)
                    VStack(spacing: 0) {
                        ForEach(day.modelBreakdown) { item in
                            detailModelRow(item)
                        }
                    }
                }
            }
            .padding(14)
        }
        .frame(width: 340, height: 520)
    }

    private func detailTokenRow(label: String, tokens: Int) -> some View {
        detailValueRow(label: label, value: formatExactTokens(tokens))
    }

    private func detailValueRow(label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .monospacedDigit()
        }
        .font(.caption)
    }

    private func detailHeader(first: String) -> some View {
        HStack(spacing: 5) {
            Text(first)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(model.strings.tokens)
                .frame(width: 72, alignment: .trailing)
            Text(model.strings.cacheRate)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(width: 44, alignment: .trailing)
            Text(model.strings.calls)
                .frame(width: 34, alignment: .trailing)
            Text(model.strings.cost)
                .frame(width: 52, alignment: .trailing)
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(.secondary)
    }

    private func detailHourRow(_ hour: HourBucket, maxTokens: Int) -> some View {
        HStack(spacing: 5) {
            VStack(alignment: .leading, spacing: 2) {
                Text(hour.start.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                GeometryReader { proxy in
                    Capsule()
                        .fill(Color.accentColor.opacity(0.62))
                        .frame(
                            width: barWidth(
                                hour.summary.totals.totalTokens,
                                maxTokens: maxTokens,
                                maxWidth: proxy.size.width
                            ),
                            height: 3
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(formatExactTokens(hour.summary.totals.totalTokens))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(width: 72, alignment: .trailing)
            Text(formatCacheRate(hour.summary.totals.cacheRate))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 44, alignment: .trailing)
            Text(formatCallCount(hour.summary.callCount))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(width: 34, alignment: .trailing)
            Text(formatCost(hour.summary.cost, includesUnit: false))
                .foregroundStyle(costNeedsDisclosure(hour.summary.cost) ? .orange : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(width: 52, alignment: .trailing)
        }
        .font(.caption2)
        .padding(.vertical, 4)
    }

    private func detailModelRow(_ item: ModelBreakdown) -> some View {
        HStack(spacing: 5) {
            Text(item.model)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(formatExactTokens(item.summary.totals.totalTokens))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(width: 72, alignment: .trailing)
            Text(formatCacheRate(item.summary.totals.cacheRate))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 44, alignment: .trailing)
            Text(formatCallCount(item.summary.callCount))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(width: 34, alignment: .trailing)
            Text(formatCost(item.summary.cost, includesUnit: false))
                .foregroundStyle(costNeedsDisclosure(item.summary.cost) ? .orange : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(width: 52, alignment: .trailing)
        }
        .font(.caption2)
        .padding(.vertical, 4)
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

    private func formatExactTokens(_ tokens: Int) -> String {
        tokens.formatted(.number)
    }

    private func formatCallCount(_ count: Int) -> String {
        count.formatted(.number)
    }

    private func formatCacheRate(_ rate: Double?) -> String {
        guard let rate else {
            return "—"
        }

        return rate.formatted(.percent.precision(.fractionLength(1)))
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

    private func formatCost(_ cost: CostEstimate, includesUnit: Bool = true) -> String {
        guard let credits = cost.credits else {
            return model.strings.unknownPricing
        }

        let value = NSDecimalNumber(decimal: credits).doubleValue
        let formattedValue = value.formatted(.number.precision(.fractionLength(0...2)))
        let base = includesUnit ? "\(formattedValue) \(model.strings.creditUnit)" : formattedValue
        let suffixes = costDisclosureSuffixes(cost)
        guard !suffixes.isEmpty else {
            return base
        }

        return "\(base) · \(suffixes.joined(separator: "/"))"
    }

    private func costNeedsDisclosure(_ cost: CostEstimate) -> Bool {
        cost.hasUnknownPricing
    }

    private func costDisclosureSuffixes(_ cost: CostEstimate) -> [String] {
        var suffixes: [String] = []
        if cost.hasUnknownPricing {
            suffixes.append(model.strings.partialPricing)
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
    let day: DayBucket?
}

private struct UsageContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct QuotaProgressBar: View {
    let progress: Double
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.12))
                Capsule()
                    .fill(tint)
                    .frame(width: proxy.size.width * min(max(progress, 0), 1))
            }
        }
        .frame(height: 4)
        .accessibilityElement(children: .ignore)
        .accessibilityValue(progress.formatted(.percent.precision(.fractionLength(0))))
    }
}

private struct WindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowDragHandleNSView {
        WindowDragHandleNSView(frame: .zero)
    }

    func updateNSView(_ nsView: WindowDragHandleNSView, context: Context) {}
}

class WindowDragHandleNSView: NSView {
    override var mouseDownCanMoveWindow: Bool {
        true
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

private struct ChartHoverDragSurface: NSViewRepresentable {
    let pointCount: Int
    let onHover: (Int?) -> Void

    func makeNSView(context: Context) -> ChartHoverDragSurfaceNSView {
        let view = ChartHoverDragSurfaceNSView(frame: .zero)
        view.pointCount = pointCount
        view.onHover = onHover
        return view
    }

    func updateNSView(_ nsView: ChartHoverDragSurfaceNSView, context: Context) {
        nsView.pointCount = pointCount
        nsView.onHover = onHover
    }
}

final class ChartHoverDragSurfaceNSView: WindowDragHandleNSView {
    var pointCount = 0
    var onHover: ((Int?) -> Void)?
    private var hoverTrackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        updateHover(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        updateHover(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        onHover?(nil)
    }

    static func nearestIndex(x: CGFloat, width: CGFloat, pointCount: Int) -> Int? {
        guard width > 0, pointCount > 0 else {
            return nil
        }
        guard pointCount > 1 else {
            return 0
        }
        let progress = min(max(x / width, 0), 1)
        return Int((progress * CGFloat(pointCount - 1)).rounded())
    }

    private func updateHover(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        onHover?(Self.nearestIndex(x: location.x, width: bounds.width, pointCount: pointCount))
    }
}

private struct PanelDragArea<Content: View>: View {
    let content: Content

    var body: some View {
        ZStack {
            WindowDragHandle()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityHidden(true)
            content
                .allowsHitTesting(false)
        }
    }
}

private extension View {
    func panelDragArea() -> some View {
        PanelDragArea(content: self)
    }
}
