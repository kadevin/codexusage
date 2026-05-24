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

    func testDeduplicatesRepeatedCodexUsageEventsUsingCcusageKey() {
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

    private func event(
        _ timestamp: String,
        model: String,
        input: Int,
        output: Int,
        isFallbackModel: Bool = false
    ) -> CodexUsageEvent {
        CodexUsageEvent(
            sessionId: "s",
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
