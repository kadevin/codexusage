import CodexUsageCore
import XCTest

final class SmokeTests: XCTestCase {
    func testTokenTotalsZero() {
        XCTAssertEqual(TokenTotals.zero.totalTokens, 0)
        XCTAssertEqual(SpeedMode.allCases, [.auto, .standard, .fast])
    }

    func testPublicSummaryInitializers() {
        let totals = TokenTotals(
            inputTokens: 100,
            cachedInputTokens: 25,
            outputTokens: 40,
            reasoningTokens: 10,
            totalTokens: 140
        )
        let cost = CostEstimate(
            usd: Decimal(string: "0.12"),
            hasUnknownPricing: false,
            usedFallbackMultiplier: false
        )
        let summary = UsageSummary(totals: totals, cost: cost)

        XCTAssertEqual(summary.totals.inputTokens, 100)
        XCTAssertEqual(summary.totals.cachedInputTokens, 25)
        XCTAssertEqual(summary.cost.usd, Decimal(string: "0.12"))
        XCTAssertFalse(summary.cost.hasUnknownPricing)
        XCTAssertFalse(summary.cost.usedFallbackMultiplier)
    }

    func testCodexUsageEventKeepsCachedInputTokensSeparate() {
        let event = CodexUsageEvent(
            sessionId: "session-1",
            timestamp: Date(timeIntervalSince1970: 0),
            model: "codex-test",
            inputTokens: 10,
            cachedInputTokens: 25,
            outputTokens: 5,
            reasoningTokens: 2,
            totalTokens: 15,
            sourceFile: URL(fileURLWithPath: "/tmp/session.jsonl")
        )

        XCTAssertEqual(event.cachedInputTokens, 25)
    }
}
