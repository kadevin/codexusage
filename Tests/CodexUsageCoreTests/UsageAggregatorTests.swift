import CodexUsageCore
import XCTest

final class UsageAggregatorTests: XCTestCase {
    func testAggregatesTodayAndCurrentHour() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date.codexTest("2026-05-24T10:30:00.000Z")
        let events = [
            event("2026-05-23T23:59:59.999Z", model: "previous-model", input: 900, output: 900),
            event("2026-05-24T00:00:00.000Z", model: "fallback-model", input: 10, output: 0, isFallbackModel: true),
            event("2026-05-24T09:55:00.000Z", model: "gpt-5.2-codex", input: 100, output: 50),
            event("2026-05-24T10:00:00.000Z", model: "zeta-model", input: 40, output: 10),
            event("2026-05-24T10:10:00.000Z", model: "alpha-model", input: 200, output: 80),
            event("2026-05-24T10:15:00.000Z", model: "beta-model", input: 140, output: 140),
            event("2026-05-24T10:45:00.000Z", model: "future-model", input: 999, output: 999),
            event("2026-05-25T00:00:00.000Z", model: "future-model", input: 999, output: 999)
        ]

        let snapshot = UsageAggregator(
            calendar: calendar,
            pricing: PricingService(speedMode: .standard, autoDetectedFast: false)
        ).snapshot(events: events, now: now)

        XCTAssertEqual(snapshot.today.totals.inputTokens, 490)
        XCTAssertEqual(snapshot.currentHour.totals.inputTokens, 380)
        XCTAssertEqual(snapshot.recentHours.count, 24)
        XCTAssertEqual(snapshot.recentHours.first?.start, Date.codexTest("2026-05-23T11:00:00.000Z"))
        XCTAssertEqual(snapshot.recentHours.last?.start, Date.codexTest("2026-05-24T10:00:00.000Z"))
        XCTAssertEqual(snapshot.recentHours.last?.id, snapshot.recentHours.last?.start)
        XCTAssertEqual(snapshot.recentHours.last?.summary.totals.inputTokens, 380)
        XCTAssertEqual(snapshot.recentDays.count, 7)
        XCTAssertEqual(snapshot.recentDays.first?.start, Date.codexTest("2026-05-18T00:00:00.000Z"))
        XCTAssertEqual(snapshot.recentDays.last?.start, Date.codexTest("2026-05-24T00:00:00.000Z"))
        XCTAssertEqual(snapshot.recentDays.last?.summary.totals.inputTokens, 490)
        XCTAssertEqual(snapshot.warnings, ["fallback-model"])
        XCTAssertEqual(
            snapshot.modelBreakdown.map(\.model),
            ["alpha-model", "beta-model", "gpt-5.2-codex", "zeta-model", "fallback-model"]
        )
    }

    func testDeduplicatesRepeatedCodexUsageEventsWithinSameSession() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date.codexTest("2026-05-24T10:30:00.000Z")
        let duplicate = event("2026-05-24T10:00:00.000Z", model: "gpt-5.2-codex", input: 100, output: 20)
        let events = [
            duplicate,
            duplicate,
            event("2026-05-24T10:00:00.000Z", model: "gpt-5.2-codex", input: 101, output: 20)
        ]

        let snapshot = UsageAggregator(
            calendar: calendar,
            pricing: PricingService(speedMode: .standard, autoDetectedFast: false)
        ).snapshot(events: events, now: now)

        XCTAssertEqual(snapshot.today.totals.inputTokens, 201)
        XCTAssertEqual(snapshot.today.totals.outputTokens, 40)
    }

    func testDoesNotDeduplicateMatchingEventsFromDifferentSessions() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date.codexTest("2026-05-24T10:30:00.000Z")
        let events = [
            event(
                "2026-05-24T10:00:00.000Z",
                model: "gpt-5.6-sol",
                input: 100,
                output: 20,
                sessionId: "session-a"
            ),
            event(
                "2026-05-24T10:00:00.000Z",
                model: "gpt-5.6-sol",
                input: 100,
                output: 20,
                sessionId: "session-b"
            )
        ]

        let snapshot = UsageAggregator(
            calendar: calendar,
            pricing: PricingService(speedMode: .standard, autoDetectedFast: false)
        ).snapshot(events: events, now: now)

        XCTAssertEqual(snapshot.today.totals.inputTokens, 200)
        XCTAssertEqual(snapshot.today.callCount, 2)
    }

    func testCallCountsUseDeduplicatedEventsAcrossSummaries() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date.codexTest("2026-05-24T10:30:00.000Z")
        let duplicate = event("2026-05-24T10:00:00.000Z", model: "gpt-5.6-sol", input: 100, output: 20)
        let events = [
            event("2026-05-24T09:55:00.000Z", model: "gpt-5.6-sol", input: 50, output: 10),
            duplicate,
            duplicate,
            event("2026-05-24T10:10:00.000Z", model: "gpt-5.6-luna", input: 30, output: 5)
        ]

        let snapshot = UsageAggregator(
            calendar: calendar,
            pricing: PricingService(speedMode: .standard, autoDetectedFast: false)
        ).snapshot(events: events, now: now)

        XCTAssertEqual(snapshot.today.callCount, 3)
        XCTAssertEqual(snapshot.currentHour.callCount, 2)
        XCTAssertEqual(snapshot.recentHours.suffix(2).map(\.summary.callCount), [1, 2])
        XCTAssertEqual(snapshot.recentDays.last?.summary.callCount, 3)
        XCTAssertEqual(snapshot.modelBreakdown.map(\.summary.callCount), [2, 1])
    }

    func testDailyDetailsContainAll24HourlyBuckets() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date.codexTest("2026-05-24T23:30:00.000Z")
        let events = [
            event("2026-05-24T01:15:00.000Z", model: "gpt-5.6-luna", input: 100, output: 20),
            event("2026-05-24T22:45:00.000Z", model: "gpt-5.6-sol", input: 200, output: 50)
        ]

        let snapshot = UsageAggregator(
            calendar: calendar,
            pricing: PricingService(speedMode: .standard, autoDetectedFast: false)
        ).snapshot(events: events, now: now)
        let hours = snapshot.recentDays.last?.hourlyBreakdown

        XCTAssertEqual(hours?.count, 24)
        XCTAssertEqual(hours?.first?.start, Date.codexTest("2026-05-24T00:00:00.000Z"))
        XCTAssertEqual(hours?[1].summary.totals.totalTokens, 120)
        XCTAssertEqual(hours?[22].summary.totals.totalTokens, 250)
    }

    func testDailyDetailsGroupModelsAndSortByTokenUsage() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date.codexTest("2026-05-24T23:30:00.000Z")
        let events = [
            event("2026-05-24T01:15:00.000Z", model: "gpt-5.6-luna", input: 100, output: 20),
            event("2026-05-24T02:15:00.000Z", model: "gpt-5.6-luna", input: 50, output: 10),
            event("2026-05-24T22:45:00.000Z", model: "gpt-5.6-sol", input: 200, output: 50)
        ]

        let snapshot = UsageAggregator(
            calendar: calendar,
            pricing: PricingService(speedMode: .standard, autoDetectedFast: false)
        ).snapshot(events: events, now: now)
        let models = snapshot.recentDays.last?.modelBreakdown

        XCTAssertEqual(models?.map(\.model), ["gpt-5.6-sol", "gpt-5.6-luna"])
        XCTAssertEqual(models?.map(\.summary.totals.totalTokens), [250, 180])
    }

    private func event(
        _ timestamp: String,
        model: String,
        input: Int,
        output: Int,
        isFallbackModel: Bool = false,
        sessionId: String = "s"
    ) -> CodexUsageEvent {
        CodexUsageEvent(
            sessionId: sessionId,
            timestamp: Date.codexTest(timestamp),
            model: model,
            inputTokens: input,
            cachedInputTokens: 0,
            outputTokens: output,
            reasoningTokens: 0,
            totalTokens: input + output,
            sourceFile: URL(fileURLWithPath: "/tmp/s.jsonl"),
            isFallbackModel: isFallbackModel
        )
    }
}

private extension Date {
    static func codexTest(_ value: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)!
    }
}
