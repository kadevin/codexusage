import CodexUsageCore
import XCTest

final class UsageAggregatorTests: XCTestCase {
    func testAggregatesTodayAndCurrentHour() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date.codexTest("2026-05-24T10:30:00.000Z")
        let events = [
            event("2026-05-24T09:55:00.000Z", input: 100, output: 50),
            event("2026-05-24T10:10:00.000Z", input: 200, output: 80),
            event("2026-05-23T10:10:00.000Z", input: 900, output: 900)
        ]

        let snapshot = UsageAggregator(
            calendar: calendar,
            pricing: PricingService(speedMode: .standard, autoDetectedFast: false)
        ).snapshot(events: events, now: now)

        XCTAssertEqual(snapshot.today.totals.inputTokens, 300)
        XCTAssertEqual(snapshot.currentHour.totals.inputTokens, 200)
        XCTAssertEqual(snapshot.recentHours.count, 24)
        XCTAssertEqual(snapshot.modelBreakdown.first?.model, "gpt-5.2-codex")
    }

    private func event(_ timestamp: String, input: Int, output: Int) -> CodexUsageEvent {
        CodexUsageEvent(
            sessionId: "s",
            timestamp: Date.codexTest(timestamp),
            model: "gpt-5.2-codex",
            inputTokens: input,
            cachedInputTokens: 0,
            outputTokens: output,
            reasoningTokens: 0,
            totalTokens: input + output,
            sourceFile: URL(fileURLWithPath: "/tmp/s.jsonl")
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
