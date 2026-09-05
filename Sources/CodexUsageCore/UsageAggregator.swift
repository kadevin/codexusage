import Foundation

public struct UsageAggregator: Sendable {
    private let calendar: Calendar
    private let pricing: PricingService

    public init(calendar: Calendar = .current, pricing: PricingService) {
        self.calendar = calendar
        self.pricing = pricing
    }

    public func snapshot(events: [CodexUsageEvent], now: Date) -> UsageSnapshot {
        let visibleEvents = unique(events.filter { $0.timestamp <= now })
        let dayStart = calendar.startOfDay(for: now)
        let hourStart = calendar.dateInterval(of: .hour, for: now)?.start ?? now
        let todayEvents = visibleEvents.filter { $0.timestamp >= dayStart }
        let currentHourEvents = visibleEvents.filter { $0.timestamp >= hourStart }
        let breakdown = modelBreakdown(events: todayEvents)
        let warnings = todayEvents.contains(where: \.isFallbackModel) ? ["fallback-model"] : []

        return UsageSnapshot(
            generatedAt: now,
            today: summary(todayEvents),
            currentHour: summary(currentHourEvents),
            recentHours: recentHours(events: visibleEvents, now: now),
            recentDays: recentDays(events: visibleEvents, now: now),
            modelBreakdown: breakdown,
            warnings: warnings
        )
    }

    private func recentHours(events: [CodexUsageEvent], now: Date) -> [HourBucket] {
        let currentHour = calendar.dateInterval(of: .hour, for: now)?.start ?? now
        let eventsByHour = Dictionary(grouping: events) { event in
            calendar.dateInterval(of: .hour, for: event.timestamp)?.start ?? event.timestamp
        }

        return (0..<24).reversed().compactMap { offset in
            guard let start = calendar.date(byAdding: .hour, value: -offset, to: currentHour) else {
                return nil
            }

            return HourBucket(start: start, summary: summary(eventsByHour[start] ?? []))
        }
    }

    private func recentDays(events: [CodexUsageEvent], now: Date) -> [DayBucket] {
        let currentDay = calendar.startOfDay(for: now)
        let eventsByDay = Dictionary(grouping: events) { event in
            calendar.startOfDay(for: event.timestamp)
        }

        return (0..<7).reversed().compactMap { offset in
            guard let start = calendar.date(byAdding: .day, value: -offset, to: currentDay) else {
                return nil
            }

            let dayEvents = eventsByDay[start] ?? []
            return DayBucket(
                start: start,
                summary: summary(dayEvents),
                hourlyBreakdown: hourlyBreakdown(events: dayEvents, dayStart: start),
                modelBreakdown: modelBreakdown(events: dayEvents)
            )
        }
    }

    private func hourlyBreakdown(events: [CodexUsageEvent], dayStart: Date) -> [HourBucket] {
        let eventsByHour = Dictionary(grouping: events) { event in
            calendar.dateInterval(of: .hour, for: event.timestamp)?.start ?? event.timestamp
        }

        return (0..<24).compactMap { hour in
            guard let start = calendar.date(byAdding: .hour, value: hour, to: dayStart) else {
                return nil
            }

            return HourBucket(start: start, summary: summary(eventsByHour[start] ?? []))
        }
    }

    private func modelBreakdown(events: [CodexUsageEvent]) -> [ModelBreakdown] {
        Dictionary(grouping: events, by: \.model)
            .map { model, modelEvents in
                ModelBreakdown(model: model, summary: summary(modelEvents))
            }
            .sorted { lhs, rhs in
                if lhs.summary.totals.totalTokens == rhs.summary.totals.totalTokens {
                    return lhs.model < rhs.model
                }
                return lhs.summary.totals.totalTokens > rhs.summary.totals.totalTokens
            }
    }

    private func summary(_ events: [CodexUsageEvent]) -> UsageSummary {
        let totals = events.reduce(TokenTotals.zero) { partial, event in
            TokenTotals(
                inputTokens: partial.inputTokens + event.inputTokens,
                cachedInputTokens: partial.cachedInputTokens + event.cachedInputTokens,
                outputTokens: partial.outputTokens + event.outputTokens,
                reasoningTokens: partial.reasoningTokens + event.reasoningTokens,
                totalTokens: partial.totalTokens + event.totalTokens
            )
        }

        return UsageSummary(
            totals: totals,
            cost: pricing.estimate(events: events),
            callCount: events.count
        )
    }

    private func unique(_ events: [CodexUsageEvent]) -> [CodexUsageEvent] {
        var seen = Set<UsageEventKey>()
        seen.reserveCapacity(events.count)

        return events.filter { event in
            seen.insert(UsageEventKey(event)).inserted
        }
    }
}

private struct UsageEventKey: Hashable {
    let sessionId: String
    let timestampMilliseconds: Int64
    let model: String
    let inputTokens: Int
    let cachedInputTokens: Int
    let outputTokens: Int
    let reasoningTokens: Int
    let totalTokens: Int

    init(_ event: CodexUsageEvent) {
        self.sessionId = event.sessionId
        self.timestampMilliseconds = Int64((event.timestamp.timeIntervalSince1970 * 1_000).rounded())
        self.model = event.model
        self.inputTokens = event.inputTokens
        self.cachedInputTokens = event.cachedInputTokens
        self.outputTokens = event.outputTokens
        self.reasoningTokens = event.reasoningTokens
        self.totalTokens = event.totalTokens
    }
}
